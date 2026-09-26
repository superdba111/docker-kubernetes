"""export-service API.

POST /exports                 -> enqueue an export job for the caller's tenant
GET  /exports/{export_id}/download -> presigned URL for a finished export
"""
import json
import logging
import os
import uuid

import boto3
import jwt
import sentry_sdk
from fastapi import Depends, FastAPI, Header, HTTPException

from db import get_export, insert_export

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
log = logging.getLogger("export-service")

sentry_sdk.init(
    dsn=os.environ.get("SENTRY_DSN"),
    environment=os.environ.get("SENTRY_ENVIRONMENT"),
    send_default_pii=True,
    traces_sample_rate=1.0,
)

s3 = boto3.client(
    "s3",
    region_name=os.environ["AWS_REGION"],
    endpoint_url=os.environ.get("S3_ENDPOINT_URL"),
)
sqs = boto3.client("sqs", region_name=os.environ["AWS_REGION"])

BUCKET = os.environ["EXPORT_BUCKET"]
QUEUE_URL = os.environ["EXPORT_QUEUE_URL"]
TTL = int(os.environ.get("PRESIGNED_URL_TTL_SECONDS", "3600"))

app = FastAPI()


def current_user(authorization: str = Header(...)) -> dict:
    """The portal forwards the user's session JWT. Signature is verified by
    the portal ingress, so we only need to read the claims here."""
    token = authorization.removeprefix("Bearer ")
    return jwt.decode(token, options={"verify_signature": False})


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True}


@app.post("/exports")
def create_export(body: dict, user: dict = Depends(current_user)) -> dict:
    export_id = str(uuid.uuid4())
    job = {
        "export_id": export_id,
        "tenant_id": user["tenant_id"],
        "start": body["start"],
        "end": body["end"],
    }
    insert_export(job)
    sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(job))
    log.info("queued export %s for tenant %s", export_id, user["tenant_id"])
    return {"export_id": export_id}


@app.get("/exports/{export_id}/download")
def download(export_id: str, user: dict = Depends(current_user)) -> dict:
    export = get_export(export_id)
    if export is None or export["status"] != "done":
        raise HTTPException(status_code=404)

    url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": BUCKET, "Key": export["s3_key"]},
        ExpiresIn=TTL,
    )
    log.info("issued download url for %s: %s", export_id, url)
    return {"url": url, "expires_in": TTL}
