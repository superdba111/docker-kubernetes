"""Per-tenant concurrency limit against a real Postgres.

Skipped unless EXPORT_TEST_PG=1 and DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD
point at a disposable database (DB_SSLMODE=disable is fine locally).
"""
import os
import threading
import time
import uuid

import pytest

pytestmark = pytest.mark.skipif(
    os.environ.get("EXPORT_TEST_PG") != "1", reason="needs a disposable Postgres"
)

import db  # noqa: E402

SCHEMA = """
DROP SCHEMA IF EXISTS exports CASCADE;
CREATE SCHEMA exports;
CREATE TABLE exports.jobs (
    id uuid PRIMARY KEY,
    tenant_id text NOT NULL,
    range_start date NOT NULL,
    range_end date NOT NULL,
    status text NOT NULL,
    s3_key text
);
"""


@pytest.fixture(autouse=True)
def fresh_schema():
    with db._db().connection() as conn:
        conn.execute(SCHEMA)


def _job(tenant):
    return {"export_id": str(uuid.uuid4()), "tenant_id": tenant,
            "start": "2026-01-01", "end": "2026-02-01"}


def _hammer(fn, tenant, n=20):
    barrier = threading.Barrier(n)
    results = []

    def run():
        barrier.wait()
        results.append(fn(_job(tenant)))

    threads = [threading.Thread(target=run) for _ in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return results


def _active(tenant):
    with db._db().connection() as conn:
        return conn.execute(
            "SELECT count(*) FROM exports.jobs WHERE tenant_id = %s", (tenant,)
        ).fetchone()[0]


def _naive_check_then_insert(job, max_active=1):
    """The pattern this replaced: separate check and insert, no lock."""
    with db._db().connection() as conn:
        n = conn.execute(
            "SELECT count(*) FROM exports.jobs WHERE tenant_id = %s AND status IN ('queued','running')",
            (job["tenant_id"],),
        ).fetchone()[0]
    if n >= max_active:
        return False
    time.sleep(0.05)  # widen the window, as a slow request would
    with db._db().connection() as conn:
        conn.execute(
            "INSERT INTO exports.jobs (id, tenant_id, range_start, range_end, status) "
            "VALUES (%s, %s, %s, %s, 'queued')",
            (job["export_id"], job["tenant_id"], job["start"], job["end"]),
        )
    return True


def test_naive_pattern_races():
    # Control: shows the race is real, so the next test means something.
    results = _hammer(_naive_check_then_insert, "tenant-a")
    assert results.count(True) > 1
    assert _active("tenant-a") > 1


def test_only_one_concurrent_export_per_tenant():
    results = _hammer(lambda job: db.create_export_if_idle(job, max_active=1), "tenant-a")
    assert results.count(True) == 1
    assert _active("tenant-a") == 1


def test_tenants_do_not_block_each_other():
    assert db.create_export_if_idle(_job("tenant-a"), max_active=1)
    assert db.create_export_if_idle(_job("tenant-b"), max_active=1)
    assert not db.create_export_if_idle(_job("tenant-a"), max_active=1)


def test_finished_exports_free_the_slot():
    job = _job("tenant-a")
    assert db.create_export_if_idle(job, max_active=1)
    db.mark_failed(job["export_id"])
    assert db.create_export_if_idle(_job("tenant-a"), max_active=1)
