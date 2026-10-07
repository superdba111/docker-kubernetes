"""Authentication and tenant isolation for the export API."""
import time
import uuid

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

import main

ISSUER = "https://portal.test"
AUDIENCE = "export-service"

_portal_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_attacker_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

EXPORT_A = str(uuid.uuid4())


class _FakeJWKS:
    """Stands in for the portal JWKS endpoint."""

    def get_signing_key_from_jwt(self, token):
        class _Key:
            key = _portal_key.public_key()
        return _Key()


def _token(key=_portal_key, alg="RS256", **overrides):
    now = int(time.time())
    claims = {
        "iss": ISSUER,
        "aud": AUDIENCE,
        "sub": "user-1",
        "tenant_id": "tenant-a",
        "iat": now,
        "exp": now + 300,
    }
    claims.update(overrides)
    claims = {k: v for k, v in claims.items() if v is not None}
    return jwt.encode(claims, key, algorithm=alg)


def _fake_get_export(export_id, tenant_id):
    exports = {(EXPORT_A, "tenant-a"): {"status": "done", "s3_key": "tenant-a/x.parquet"}}
    row = exports.get((export_id, tenant_id))
    if row is None:
        return None
    return {"id": export_id, "tenant_id": tenant_id, **row}


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(main, "_jwks", _FakeJWKS())
    monkeypatch.setattr(main, "get_export", _fake_get_export)
    monkeypatch.setattr(main, "count_active_exports", lambda tenant_id: 0)
    monkeypatch.setattr(main, "mark_failed", lambda export_id: None)
    return TestClient(main.app)


def _download(client, token, export_id=EXPORT_A):
    return client.get(
        f"/exports/{export_id}/download",
        headers={"Authorization": f"Bearer {token}"},
    )


class _FakeBody:
    def __init__(self, data):
        self._data = data
        self.closed = False

    def iter_chunks(self, size):
        for i in range(0, len(self._data), size):
            yield self._data[i:i + size]

    def close(self):
        self.closed = True


@pytest.fixture
def fake_s3_object(monkeypatch):
    fetched = []

    def get_object(Bucket, Key):
        body = _FakeBody(b"PAR1-data")
        fetched.append((Key, body))
        return {"Body": body, "ContentLength": 9}

    monkeypatch.setattr(main.s3, "get_object", get_object)
    return fetched


def test_default_mode_streams_through_api(client, fake_s3_object):
    assert main.DOWNLOAD_MODE == "stream"
    resp = _download(client, _token())
    assert resp.status_code == 200
    assert resp.content == b"PAR1-data"
    assert "attachment" in resp.headers["content-disposition"]
    assert resp.headers["cache-control"] == "no-store"
    assert [k for k, _ in fake_s3_object] == ["tenant-a/x.parquet"]
    assert fake_s3_object[0][1].closed


def test_stream_mode_other_tenant_gets_404_without_reading_s3(client, fake_s3_object):
    assert _download(client, _token(tenant_id="tenant-b")).status_code == 404
    assert fake_s3_object == []


def test_presigned_mode_gives_short_lived_url(client, monkeypatch):
    monkeypatch.setattr(main, "DOWNLOAD_MODE", "presigned")
    resp = _download(client, _token())
    assert resp.status_code == 200
    assert resp.json()["expires_in"] <= main.MAX_TTL_SECONDS


def test_other_tenant_gets_404(client):
    assert _download(client, _token(tenant_id="tenant-b")).status_code == 404


def test_forged_signature_rejected(client):
    assert _download(client, _token(key=_attacker_key)).status_code == 401


def test_unsigned_token_rejected(client):
    unsigned = jwt.encode(
        {"iss": ISSUER, "aud": AUDIENCE, "sub": "x", "tenant_id": "tenant-a",
         "iat": int(time.time()), "exp": int(time.time()) + 300},
        None, algorithm="none",
    )
    assert _download(client, unsigned).status_code == 401


@pytest.mark.parametrize(
    "overrides",
    [
        {"iss": "https://evil.test"},
        {"iss": "https://portal.test.evil"},   # partial-match issuer (CVE-2026-90118 class)
        {"aud": "some-other-service"},
        {"exp": int(time.time()) - 60},
        {"tenant_id": None},
        {"tenant_id": ""},
    ],
)
def test_bad_claims_rejected(client, overrides):
    assert _download(client, _token(**overrides)).status_code == 401


def test_missing_bearer_rejected(client):
    resp = client.get(f"/exports/{EXPORT_A}/download", headers={"Authorization": "Basic abc"})
    assert resp.status_code == 401


def test_non_uuid_export_id_rejected(client):
    assert _download(client, _token(), export_id="../../etc").status_code in (404, 422)


def test_url_not_logged(client, caplog, monkeypatch):
    monkeypatch.setattr(main, "DOWNLOAD_MODE", "presigned")
    caplog.set_level("INFO", logger="export-service")
    resp = _download(client, _token())
    assert resp.json()["url"] not in caplog.text
    assert "X-Amz-Signature" not in caplog.text


def test_create_export_rejects_reversed_range(client):
    resp = client.post(
        "/exports",
        json={"start": "2026-02-01", "end": "2026-01-01"},
        headers={"Authorization": f"Bearer {_token()}"},
    )
    assert resp.status_code == 422


def test_tenant_not_enabled_gets_404_and_nothing_is_queued(client, monkeypatch):
    inserted = []
    monkeypatch.setattr(main, "insert_export", inserted.append)
    monkeypatch.setattr(main.sqs, "send_message", lambda **kw: inserted.append(kw))
    resp = client.post(
        "/exports",
        json={"start": "2026-01-01", "end": "2026-02-01"},
        headers={"Authorization": f"Bearer {_token(tenant_id='tenant-c')}"},
    )
    assert resp.status_code == 404
    assert inserted == []


def test_enabled_tenant_can_queue(client, monkeypatch):
    inserted = []
    monkeypatch.setattr(main, "insert_export", inserted.append)
    monkeypatch.setattr(main.sqs, "send_message", lambda **kw: inserted.append(kw))
    resp = client.post(
        "/exports",
        json={"start": "2026-01-01", "end": "2026-02-01"},
        headers={"Authorization": f"Bearer {_token()}"},
    )
    assert resp.status_code == 200
    assert inserted[0]["tenant_id"] == "tenant-a"


def test_stream_closes_s3_body_when_client_stops_early():
    body = _FakeBody(b"x" * (3 * main.STREAM_CHUNK_BYTES))
    gen = main._stream(body)
    next(gen)          # client reads one chunk, then disconnects
    gen.close()
    assert body.closed


def test_key_outside_tenant_prefix_is_refused(client, monkeypatch, fake_s3_object, caplog):
    def rogue(export_id, tenant_id):
        return {"id": export_id, "tenant_id": tenant_id, "status": "done",
                "s3_key": "tenant-b/their-export.parquet"}
    monkeypatch.setattr(main, "get_export", rogue)
    assert _download(client, _token()).status_code == 404
    assert fake_s3_object == []
    assert "outside the tenant prefix" in caplog.text


@pytest.mark.parametrize("key", ["tenant-a/", "tenant-ab/x.parquet", "x/tenant-a/y", None])
def test_owned_key_rejects_lookalikes(key):
    assert not main._owned_key(key, "tenant-a")


@pytest.mark.parametrize("tenant_id", ["a/b", "*", "../x", "t" * 65, "tenant a"])
def test_malformed_tenant_id_rejected(client, tenant_id):
    assert _download(client, _token(tenant_id=tenant_id)).status_code == 401


def _post(client, start="2026-01-01", end="2026-02-01", tenant_id="tenant-a"):
    return client.post(
        "/exports",
        json={"start": start, "end": end},
        headers={"Authorization": f"Bearer {_token(tenant_id=tenant_id)}"},
    )


def test_range_over_limit_rejected(client):
    assert _post(client, start="2025-01-01", end="2026-06-01").status_code == 422


def test_second_active_export_rejected(client, monkeypatch):
    monkeypatch.setattr(main, "count_active_exports", lambda tenant_id: 1)
    queued = []
    monkeypatch.setattr(main, "insert_export", queued.append)
    assert _post(client).status_code == 429
    assert queued == []


def test_enqueue_failure_marks_job_failed(client, monkeypatch):
    rows, failed = [], []
    monkeypatch.setattr(main, "insert_export", rows.append)
    monkeypatch.setattr(main, "mark_failed", failed.append)

    def boom(**kw):
        raise RuntimeError("sqs down")
    monkeypatch.setattr(main.sqs, "send_message", boom)
    assert _post(client).status_code == 503
    assert failed == [rows[0]["export_id"]]
