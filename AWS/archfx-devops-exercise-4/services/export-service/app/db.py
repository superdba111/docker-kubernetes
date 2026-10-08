"""Thin data access layer (excerpt).

One pooled connection per request. The previous single global connection was
shared by every request thread, so one request's transaction (and any lock in
it) could silently absorb another's statements.
"""
import os

from psycopg_pool import ConnectionPool

_pool: ConnectionPool | None = None


def _conninfo() -> str:
    from psycopg.conninfo import make_conninfo

    return make_conninfo(
        host=os.environ["DB_HOST"],
        port=os.environ.get("DB_PORT"),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        # Always TLS in govhigh. Overridable only so tests can use a local DB.
        sslmode=os.environ.get("DB_SSLMODE", "require"),
    )


def _db() -> ConnectionPool:
    global _pool
    if _pool is None:
        _pool = ConnectionPool(_conninfo(), min_size=1, max_size=10, open=True)
    return _pool


def create_export_if_idle(job: dict, max_active: int) -> bool:
    """Insert the job unless the tenant already has max_active queued/running
    exports. Check and insert run under a per-tenant advisory lock in one
    transaction, so concurrent requests for the same tenant can't both pass the
    check. Returns False if the tenant is at its limit."""
    with _db().connection() as conn, conn.transaction(), conn.cursor() as cur:
        cur.execute(
            "SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))",
            (f"export-service:tenant:{job['tenant_id']}",),
        )
        cur.execute(
            "SELECT count(*) FROM exports.jobs "
            "WHERE tenant_id = %s AND status IN ('queued', 'running')",
            (job["tenant_id"],),
        )
        if cur.fetchone()[0] >= max_active:
            return False
        cur.execute(
            "INSERT INTO exports.jobs (id, tenant_id, range_start, range_end, status) "
            "VALUES (%s, %s, %s, %s, 'queued')",
            (job["export_id"], job["tenant_id"], job["start"], job["end"]),
        )
    return True


def get_export(export_id: str, tenant_id: str) -> dict | None:
    """Return the export only if it belongs to tenant_id."""
    with _db().connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT id, tenant_id, status, s3_key FROM exports.jobs "
            "WHERE id = %s AND tenant_id = %s",
            (export_id, tenant_id),
        )
        row = cur.fetchone()
    if row is None:
        return None
    return {"id": row[0], "tenant_id": row[1], "status": row[2], "s3_key": row[3]}


def mark_failed(export_id: str) -> None:
    with _db().connection() as conn, conn.cursor() as cur:
        cur.execute(
            "UPDATE exports.jobs SET status = 'failed' WHERE id = %s AND status = 'queued'",
            (export_id,),
        )
