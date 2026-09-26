"""Thin data access layer (excerpt)."""
import os

import psycopg

_conn = None


def _db():
    global _conn
    if _conn is None:
        _conn = psycopg.connect(
            host=os.environ["DB_HOST"],
            dbname=os.environ["DB_NAME"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            sslmode="require",
        )
    return _conn


def insert_export(job: dict) -> None:
    with _db().cursor() as cur:
        cur.execute(
            "INSERT INTO exports.jobs (id, tenant_id, range_start, range_end, status) "
            "VALUES (%s, %s, %s, %s, 'queued')",
            (job["export_id"], job["tenant_id"], job["start"], job["end"]),
        )
    _db().commit()


def get_export(export_id: str) -> dict | None:
    with _db().cursor() as cur:
        cur.execute(
            "SELECT id, tenant_id, status, s3_key FROM exports.jobs WHERE id = %s",
            (export_id,),
        )
        row = cur.fetchone()
    if row is None:
        return None
    return {"id": row[0], "tenant_id": row[1], "status": row[2], "s3_key": row[3]}
