"""export-service API.

POST /exports                 -> enqueue an export job for the caller's tenant
GET  /exports/{export_id}/download -> presigned URL for a finished export
"""
import datetime
import json
import logging
import os
import uuid

import boto3
import jwt
import sentry_sdk
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, model_validator

from db import get_export, insert_export

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
log = logging.getLogger("export-service")

sentry_sdk.init(
    dsn=os.environ.get("SENTRY_DSN"),
    environment=os.environ.get("SENTRY_ENVIRONMENT"),
    # In-boundary Sentry only (DSN from Secrets Manager). Error payloads count
    # as CUI, so keep request bodies, headers and user data out of them.
    send_default_pii=False,
    max_request_body_size="never",
    traces_sample_rate=float(os.environ.get("SENTRY_TRACES_SAMPLE_RATE", "0")),
)

# Endpoints come from the SDK so AWS_USE_FIPS_ENDPOINT=true selects the FIPS
# hosts (boundary section 3). Presigned URLs are then also on s3-fips.
s3 = boto3.client("s3", region_name=os.environ["AWS_REGION"])
sqs = boto3.client("sqs", region_name=os.environ["AWS_REGION"])

BUCKET = os.environ["EXPORT_BUCKET"]
QUEUE_URL = os.environ["EXPORT_QUEUE_URL"]

# Presigned URLs are bearer credentials. Keep them short-lived; the portal asks
# for a fresh one each time the user clicks Download. (URLs signed with IRSA
# session credentials stop working when the session expires anyway, so a
# multi-day TTL was never going to hold.)
MAX_TTL_SECONDS = 3600
TTL = min(int(os.environ.get("PRESIGNED_URL_TTL_SECONDS", "900")), MAX_TTL_SECONDS)


def _required_env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError(f"{name} must be set")
    return value


# The portal's session JWTs are verified here, not only at the ingress: the
# service must not trust claims from anything that can reach the pod.
JWT_ISSUER = _required_env("JWT_ISSUER")
JWT_AUDIENCE = _required_env("JWT_AUDIENCE")
JWT_ALGORITHMS = ["RS256"]
_jwks = jwt.PyJWKClient(_required_env("JWT_JWKS_URL"), cache_keys=True)

# Feature flag. Exports are off for every tenant unless explicitly enabled
# (launch plan: one customer first). Not-enabled tenants get 404, as if the
# feature didn't exist.
ENABLED_TENANTS = frozenset(
    t.strip() for t in os.environ.get("EXPORT_ENABLED_TENANTS", "").split(",") if t.strip()
)

app = FastAPI()


def current_user(authorization: str = Header(...)) -> dict:
    """Verify the portal session JWT and return its claims."""
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401)
    try:
        key = _jwks.get_signing_key_from_jwt(token).key
        claims = jwt.decode(
            token,
            key,
            algorithms=JWT_ALGORITHMS,
            audience=JWT_AUDIENCE,
            issuer=JWT_ISSUER,
            options={"require": ["exp", "iat", "iss", "aud", "sub", "tenant_id"]},
        )
    except jwt.PyJWKClientConnectionError:
        log.exception("could not fetch JWKS")
        raise HTTPException(status_code=503)
    except jwt.PyJWTError as exc:
        log.info("rejected token: %s", type(exc).__name__)
        raise HTTPException(status_code=401)
    if not isinstance(claims["tenant_id"], str) or not claims["tenant_id"]:
        raise HTTPException(status_code=401)
    return claims


def enabled_user(user: dict = Depends(current_user)) -> dict:
    if user["tenant_id"] not in ENABLED_TENANTS:
        raise HTTPException(status_code=404)
    return user


class ExportRequest(BaseModel):
    start: datetime.date
    end: datetime.date

    @model_validator(mode="after")
    def _ordered(self) -> "ExportRequest":
        if self.end < self.start:
            raise ValueError("end must not be before start")
        return self


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True}


@app.post("/exports")
def create_export(body: ExportRequest, user: dict = Depends(enabled_user)) -> dict:
    export_id = str(uuid.uuid4())
    job = {
        "export_id": export_id,
        # Tenant always comes from the verified token, never from the body.
        "tenant_id": user["tenant_id"],
        "start": body.start.isoformat(),
        "end": body.end.isoformat(),
    }
    insert_export(job)
    sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(job))
    log.info("queued export %s for tenant %s", export_id, user["tenant_id"])
    return {"export_id": export_id}


@app.get("/exports/{export_id}/download")
def download(export_id: uuid.UUID, user: dict = Depends(enabled_user)) -> dict:
    # Scoped by tenant in the query. Another tenant's export looks exactly like
    # a missing one (404), so export IDs can't be probed.
    export = get_export(str(export_id), user["tenant_id"])
    if export is None or export["status"] != "done":
        raise HTTPException(status_code=404)

    url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": BUCKET, "Key": export["s3_key"]},
        ExpiresIn=TTL,
    )
    # Never log the URL itself: anyone holding it can download the export.
    log.info(
        "issued download url for export %s tenant %s sub %s ttl %ss",
        export_id, user["tenant_id"], user["sub"], TTL,
    )
    return {"url": url, "expires_in": TTL}
