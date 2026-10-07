"""export-service API.

POST /exports                 -> enqueue an export job for the caller's tenant
GET  /exports/{export_id}/download -> the finished export, streamed (default),
                                      or a presigned URL when enabled
"""
import datetime
import json
import logging
import os
import re
import uuid

import boto3
import jwt
import sentry_sdk
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, model_validator

from db import count_active_exports, get_export, insert_export, mark_failed

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

# How exports reach the customer. "stream": the file is streamed through this
# API and the portal, the only approved internet-facing path (boundary section
# 5). "presigned": the browser downloads straight from S3; only switch to this
# once the ISSO confirms that path is covered by the SSP (review A4).
DOWNLOAD_MODE = os.environ.get("DOWNLOAD_MODE", "stream")
if DOWNLOAD_MODE not in ("stream", "presigned"):
    raise RuntimeError(f"DOWNLOAD_MODE must be 'stream' or 'presigned', not {DOWNLOAD_MODE!r}")
STREAM_CHUNK_BYTES = 1024 * 1024

# Abuse/cost limits per request and per tenant (review G3).
MAX_RANGE_DAYS = int(os.environ.get("EXPORT_MAX_RANGE_DAYS", "366"))
MAX_ACTIVE_PER_TENANT = int(os.environ.get("EXPORT_MAX_ACTIVE_PER_TENANT", "1"))

# Tenant IDs are used as S3 key prefixes and IAM session tags, so they must be
# unambiguous: no "/", no wildcards, bounded length.
TENANT_ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}")


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
    tenant_id = claims["tenant_id"]
    if not isinstance(tenant_id, str) or not TENANT_ID_RE.fullmatch(tenant_id):
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
        if (self.end - self.start).days > MAX_RANGE_DAYS:
            raise ValueError(f"date range must be at most {MAX_RANGE_DAYS} days")
        return self


def _owned_key(key: str | None, tenant_id: str) -> bool:
    """Exports live under "<tenant_id>/". Never trust the DB row's key alone:
    the API role can read the whole exports bucket."""
    prefix = f"{tenant_id}/"
    return isinstance(key, str) and key.startswith(prefix) and len(key) > len(prefix)


def _stream(body):
    """Yield the S3 object in chunks and always release the connection, including
    when the client disconnects mid-download."""
    try:
        yield from body.iter_chunks(STREAM_CHUNK_BYTES)
    finally:
        body.close()


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True}


@app.post("/exports")
def create_export(body: ExportRequest, user: dict = Depends(enabled_user)) -> dict:
    if count_active_exports(user["tenant_id"]) >= MAX_ACTIVE_PER_TENANT:
        raise HTTPException(status_code=429, detail="an export is already in progress")

    export_id = str(uuid.uuid4())
    job = {
        "export_id": export_id,
        # Tenant always comes from the verified token, never from the body.
        "tenant_id": user["tenant_id"],
        "start": body.start.isoformat(),
        "end": body.end.isoformat(),
    }
    insert_export(job)
    # The DB row is the source of truth; the worker must ignore messages whose
    # job isn't 'queued'. If the send fails, fail the row so it doesn't sit in
    # 'queued' forever and block the tenant's concurrency slot.
    try:
        sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(job))
    except Exception:
        log.exception("failed to enqueue export %s", export_id)
        mark_failed(export_id)
        raise HTTPException(status_code=503, detail="could not queue export, try again")
    log.info("queued export %s for tenant %s", export_id, user["tenant_id"])
    return {"export_id": export_id}


@app.get("/exports/{export_id}/download")
def download(export_id: uuid.UUID, user: dict = Depends(enabled_user)):
    # Scoped by tenant in the query. Another tenant's export looks exactly like
    # a missing one (404), so export IDs can't be probed.
    export = get_export(str(export_id), user["tenant_id"])
    if export is None or export["status"] != "done":
        raise HTTPException(status_code=404)
    if not _owned_key(export["s3_key"], user["tenant_id"]):
        # The row belongs to this tenant but points outside its prefix: a bug
        # or tampering. Refuse, and make it visible.
        log.error("export %s for tenant %s has a key outside the tenant prefix", export_id, user["tenant_id"])
        raise HTTPException(status_code=404)

    if DOWNLOAD_MODE == "stream":
        obj = s3.get_object(Bucket=BUCKET, Key=export["s3_key"])
        log.info(
            "streaming export %s tenant %s sub %s bytes %s",
            export_id, user["tenant_id"], user["sub"], obj["ContentLength"],
        )
        return StreamingResponse(
            _stream(obj["Body"]),
            media_type="application/vnd.apache.parquet",
            headers={
                "Content-Disposition": f'attachment; filename="export-{export_id}.parquet"',
                "Content-Length": str(obj["ContentLength"]),
                "Cache-Control": "no-store",
            },
        )

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
