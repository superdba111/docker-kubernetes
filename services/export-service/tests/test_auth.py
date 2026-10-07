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
    return TestClient(main.app)


def _download(client, token, export_id=EXPORT_A):
    return client.get(
        f"/exports/{export_id}/download",
        headers={"Authorization": f"Bearer {token}"},
    )


def test_owner_gets_short_lived_url(client):
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


def test_url_not_logged(client, caplog):
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
