"""Integration tests for the Global Registry artefact + community surface."""

from __future__ import annotations

import hashlib
import tempfile
import uuid
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient

import neurohub.app.services.object_storage as object_storage
from neurohub.app.limiter import limiter


@pytest.fixture(autouse=True)
def _local_storage() -> Generator[None, None, None]:
    """Use fresh local storage and disable rate limiting for functional tests."""
    tmp = tempfile.mkdtemp(prefix="registry-test-")
    import os

    prev = os.environ.get("OBJECT_STORAGE_LOCAL_PATH")
    prev_url = os.environ.get("OBJECT_STORAGE_URL")
    os.environ.pop("OBJECT_STORAGE_URL", None)  # force local backend
    os.environ["OBJECT_STORAGE_LOCAL_PATH"] = tmp
    object_storage._storage = None  # reset singleton
    limiter_was_enabled = limiter.enabled
    limiter.enabled = False  # rate limiting is exercised in test_registry_rate_limiting
    yield
    limiter.enabled = limiter_was_enabled
    object_storage._storage = None
    if prev is not None:
        os.environ["OBJECT_STORAGE_LOCAL_PATH"] = prev
    if prev_url is not None:
        os.environ["OBJECT_STORAGE_URL"] = prev_url


def _auth_headers(client: TestClient, username: str | None = None) -> tuple[dict[str, str], str]:
    """Register and log in a fresh user; return (auth headers, username)."""
    username = username or f"user-{uuid.uuid4().hex[:8]}"
    reg = client.post(
        "/api/v1/auth/register",
        json={
            "username": username,
            "email": f"{username}@example.com",
            "full_name": "Test Publisher",
            "password": "s3cret-pass",
        },
    )
    assert reg.status_code == 201, reg.text
    login = client.post(
        "/api/v1/auth/login", json={"username": username, "password": "s3cret-pass"}
    )
    assert login.status_code == 200, login.text
    token = login.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}, username


def _push(
    client: TestClient,
    headers: dict[str, str],
    *,
    slug: str = "lif-base",
    version: str = "1.0.0",
    blob: bytes = b"spiking-weights",
    type_: str = "snn_model",
    extra: dict[str, str] | None = None,
) -> object:
    """Upload an artefact via multipart and return the response."""
    data = {"type": type_, "slug": slug, "version": version}
    if extra:
        data.update(extra)
    return client.post(
        "/api/v1/artefacts",
        files={"file": (f"{slug}.nir", blob)},
        data=data,
        headers=headers,
    )


def test_create_get_round_trip(client: TestClient) -> None:
    """POST then GET returns identical metadata and a canonical URI (Property 1)."""
    headers, username = _auth_headers(client)
    resp = _push(client, headers, extra={"description": "A LIF baseline", "tags": "snn,baseline"})
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["neurohub_uri"] == f"neurohub://snn_model/{username}/lif-base@1.0.0"
    assert body["owner"] == username
    assert body["sha256"] == hashlib.sha256(b"spiking-weights").hexdigest()

    got = client.get(f"/api/v1/artefacts/{username}/lif-base/1.0.0")
    assert got.status_code == 200
    assert got.json()["description"] == "A LIF baseline"
    assert sorted(got.json()["tags"]) == ["baseline", "snn"]


def test_duplicate_returns_409(client: TestClient) -> None:
    """Re-pushing the same identifier is rejected with 409."""
    headers, _ = _auth_headers(client)
    assert _push(client, headers).status_code == 201
    assert _push(client, headers).status_code == 409


def test_invalid_type_returns_422(client: TestClient) -> None:
    """An unknown artefact type is rejected with 422 (Property 30)."""
    headers, _ = _auth_headers(client)
    assert _push(client, headers, type_="not_a_type").status_code == 422


def test_unauthenticated_create_returns_401(client: TestClient) -> None:
    """Creating without a token returns 401 + WWW-Authenticate (Property 21)."""
    resp = _push(client, headers={})
    assert resp.status_code == 401
    assert resp.headers.get("WWW-Authenticate") == "Bearer"


def test_latest_version_resolution(client: TestClient) -> None:
    """Version-less GET resolves to the semantic maximum (Property 7)."""
    headers, username = _auth_headers(client)
    for v in ["1.0.0", "1.2.0", "1.10.0", "2.0.1"]:
        assert _push(client, headers, version=v).status_code == 201
    latest = client.get(f"/api/v1/artefacts/{username}/lif-base")
    assert latest.status_code == 200
    assert latest.json()["version"] == "2.0.1"


def test_version_list_descending(client: TestClient) -> None:
    """Version list is returned in strictly descending semver order (Property 8)."""
    headers, username = _auth_headers(client)
    for v in ["1.0.0", "1.10.0", "1.2.0"]:
        _push(client, headers, version=v)
    versions = client.get(f"/api/v1/artefacts/{username}/lif-base/versions").json()
    assert versions == ["1.10.0", "1.2.0", "1.0.0"]


def test_immutable_fields_preserved_on_update(client: TestClient) -> None:
    """PUT changes mutable fields only; immutable fields stay fixed (Property 2)."""
    headers, username = _auth_headers(client)
    _push(client, headers)
    before = client.get(f"/api/v1/artefacts/{username}/lif-base/1.0.0").json()
    upd = client.put(
        f"/api/v1/artefacts/{username}/lif-base/1.0.0",
        json={"description": "updated"},
        headers=headers,
    )
    assert upd.status_code == 200
    after = upd.json()
    assert after["description"] == "updated"
    for field in ("type", "owner", "slug", "version", "sha256", "created_at"):
        assert after[field] == before[field]


def test_non_owner_cannot_modify(client: TestClient) -> None:
    """A non-owner is forbidden from updating/deleting (Property 5)."""
    owner_headers, username = _auth_headers(client)
    _push(client, owner_headers)
    other_headers, _ = _auth_headers(client)
    upd = client.put(
        f"/api/v1/artefacts/{username}/lif-base/1.0.0",
        json={"description": "hijack"},
        headers=other_headers,
    )
    assert upd.status_code == 403
    delete = client.delete(f"/api/v1/artefacts/{username}/lif-base/1.0.0", headers=other_headers)
    assert delete.status_code == 403


def test_soft_delete_then_404(client: TestClient) -> None:
    """After delete, GET returns 404 and it drops from search (Property 3)."""
    headers, username = _auth_headers(client)
    _push(client, headers)
    assert (
        client.delete(f"/api/v1/artefacts/{username}/lif-base/1.0.0", headers=headers).status_code
        == 204
    )
    assert client.get(f"/api/v1/artefacts/{username}/lif-base/1.0.0").status_code == 404
    results = client.get("/api/v1/search", params={"q": "lif-base"}).json()
    assert all(i["owner"] != username for i in results["items"])


def test_download_round_trip_and_checksum(client: TestClient) -> None:
    """Download serves the blob with a matching checksum (Property 4)."""
    headers, username = _auth_headers(client)
    blob = b"the-actual-weights-payload"
    _push(client, headers, blob=blob)
    dl = client.get(f"/api/v1/artefacts/{username}/lif-base/1.0.0/download", follow_redirects=True)
    assert dl.status_code == 200
    assert dl.content == blob
    assert dl.headers["X-Artefact-SHA256"] == hashlib.sha256(blob).hexdigest()


def test_search_filters_and_degraded_flag(client: TestClient) -> None:
    """Search applies filters and reports a non-degraded local index."""
    headers, username = _auth_headers(client)
    _push(client, headers, slug="lif-base", extra={"tags": "snn"})
    _push(client, headers, slug="izh-base", type_="dataset")
    res = client.get("/api/v1/search", params={"type": "snn_model", "owner": username})
    body = res.json()
    assert res.status_code == 200
    assert body["search_degraded"] is False
    assert all(i["type"] == "snn_model" and i["owner"] == username for i in body["items"])
    assert any(i["slug"] == "lif-base" for i in body["items"])


def test_rating_aggregate(client: TestClient) -> None:
    """Ratings aggregate as mean over distinct raters; re-rating replaces (Property 20)."""
    owner_headers, username = _auth_headers(client)
    _push(client, owner_headers)
    a_headers, _ = _auth_headers(client)
    b_headers, _ = _auth_headers(client)
    client.post(
        f"/api/v1/artefacts/{username}/lif-base/ratings", json={"value": 4}, headers=a_headers
    )
    res = client.post(
        f"/api/v1/artefacts/{username}/lif-base/ratings", json={"value": 2}, headers=b_headers
    )
    body = res.json()
    assert body["rating_count"] == 2
    assert body["average_rating"] == 3.0
    # A re-submits a new rating -> replaces, count stays 2.
    res2 = client.post(
        f"/api/v1/artefacts/{username}/lif-base/ratings", json={"value": 5}, headers=a_headers
    )
    assert res2.json()["rating_count"] == 2
    assert res2.json()["average_rating"] == 3.5


def test_comment_round_trip_and_bounds(client: TestClient) -> None:
    """Comments round-trip and enforce the 1-4000 length bound (Properties 17/18)."""
    headers, username = _auth_headers(client)
    _push(client, headers)
    text = "great model — 你好"
    posted = client.post(
        f"/api/v1/artefacts/{username}/lif-base/comments",
        json={"content": text},
        headers=headers,
    )
    assert posted.status_code == 201
    assert posted.json()["content"] == text
    too_long = client.post(
        f"/api/v1/artefacts/{username}/lif-base/comments",
        json={"content": "x" * 4001},
        headers=headers,
    )
    assert too_long.status_code == 422


def test_follow_self_and_duplicate(client: TestClient) -> None:
    """Self-follow is 400 and duplicate follow is 409."""
    headers, username = _auth_headers(client)
    target_headers, target = _auth_headers(client)
    assert client.post(f"/api/v1/users/{username}/follow", headers=headers).status_code == 400
    assert client.post(f"/api/v1/users/{target}/follow", headers=headers).status_code == 201
    assert client.post(f"/api/v1/users/{target}/follow", headers=headers).status_code == 409


def test_health_reports_ok(client: TestClient) -> None:
    """The registry health endpoint reports ok with local storage available."""
    res = client.get("/api/v1/health")
    assert res.status_code == 200
    body = res.json()
    assert body["db"] == "connected"
    assert body["storage"] == "connected"
    assert body["status"] == "ok"
