"""Property-based tests for the Neurohub Global Registry.

Covers the pure / fast correctness properties from
``.kiro/specs/neurohub-global-registry/design.md``. The stateful API properties
(creation round-trip, soft-delete visibility, ownership, etc.) are exercised by
the integration tests in ``test_registry_artefacts.py``.
"""

from __future__ import annotations

import hashlib

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from jose import jwt
from pydantic import ValidationError

from neurohub.app.services.auth_service import (
    ALGORITHM,
    SECRET_KEY,
    get_password_hash,
    verify_password,
)
from neurohub.app.services.object_storage import build_storage_key, compute_sha256
from neurohub.app.services.registry_auth_service import issue_access_token, verify_token
from neurohub.app.utils.uri_parser import ArtefactType, URIParseError, build_uri, parse_uri
from neurohub.contracts.registry_contracts import ArtefactCreate
from neurohub.db.models import UserDB

_IDENTIFIER = st.from_regex(r"[a-z0-9][a-z0-9-]{0,10}", fullmatch=True)
_TYPES = st.sampled_from([t.value for t in ArtefactType])


@st.composite
def _valid_uris(draw: st.DrawFn) -> str:
    """Generate a conformant ``neurohub://`` URI string."""
    type_ = draw(_TYPES)
    owner = "/".join(draw(st.lists(_IDENTIFIER, min_size=1, max_size=2)))
    slug = draw(_IDENTIFIER)
    base = f"neurohub://{type_}/{owner}/{slug}"
    if draw(st.booleans()):
        a, b, c = (draw(st.integers(0, 999)) for _ in range(3))
        return f"{base}@{a}.{b}.{c}"
    return base


# Feature: neurohub-global-registry, Property 9: URI round-trip
@settings(max_examples=100)
@given(uri=_valid_uris())
def test_uri_round_trip(uri: str) -> None:
    """build_uri(parse_uri(s)) == s."""
    assert build_uri(parse_uri(uri)) == uri


# Feature: neurohub-global-registry, Property 10: URI parse idempotence
@settings(max_examples=100)
@given(uri=_valid_uris())
def test_uri_parse_idempotence(uri: str) -> None:
    """Parsing twice yields identical fields."""
    assert parse_uri(build_uri(parse_uri(uri))) == parse_uri(uri)


# Feature: neurohub-global-registry, Property 11: URI parse error — wrong scheme
@settings(max_examples=100)
@given(
    scheme=st.from_regex(r"[a-z]{1,8}", fullmatch=True).filter(lambda s: s != "neurohub"),
    rest=_valid_uris(),
)
def test_uri_wrong_scheme(scheme: str, rest: str) -> None:
    """A wrong scheme prefix raises, naming the received scheme."""
    with pytest.raises(URIParseError) as exc:
        parse_uri(rest.replace("neurohub://", f"{scheme}://", 1))
    assert scheme in str(exc.value)


# Feature: neurohub-global-registry, Property 24: object storage key pattern
@settings(max_examples=100)
@given(type_=_TYPES, owner=_IDENTIFIER, slug=_IDENTIFIER, filename=_IDENTIFIER)
def test_storage_key_pattern(type_: str, owner: str, slug: str, filename: str) -> None:
    """The storage key matches {type}/{owner}/{slug}/{version}/{filename}, no traversal."""
    key = build_storage_key(type_, owner, slug, "1.0.0", f"{filename}.nir")
    assert key == f"{type_}/{owner}/{slug}/1.0.0/{filename}.nir"
    assert ".." not in key.split("/")


# Feature: neurohub-global-registry, Property 4 (component): checksum determinism
@settings(max_examples=100)
@given(data=st.binary(max_size=512))
def test_checksum_matches_hashlib(data: bytes) -> None:
    """compute_sha256 equals hashlib.sha256 hexdigest."""
    assert compute_sha256(data) == hashlib.sha256(data).hexdigest()


# Feature: neurohub-global-registry, Property 30: invalid artefact type rejection
@settings(max_examples=100)
@given(
    bad_type=st.text(min_size=1, max_size=20).filter(
        lambda s: s not in {t.value for t in ArtefactType}
    )
)
def test_invalid_type_rejected(bad_type: str) -> None:
    """ArtefactCreate rejects any non-canonical type with the type field named."""
    with pytest.raises(ValidationError) as exc:
        ArtefactCreate(type=bad_type, slug="lif", version="1.0.0")
    assert any(e["loc"] == ("type",) for e in exc.value.errors())


# Feature: neurohub-global-registry, Property 6: identifier format validation
@settings(max_examples=100)
@given(
    bad_slug=st.text(min_size=1, max_size=12).filter(
        lambda s: __import__("re").fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", s) is None
    )
)
def test_invalid_slug_rejected(bad_slug: str) -> None:
    """ArtefactCreate rejects a malformed slug, naming the slug field."""
    with pytest.raises(ValidationError) as exc:
        ArtefactCreate(type="snn_model", slug=bad_slug, version="1.0.0")
    assert any(e["loc"] == ("slug",) for e in exc.value.errors())


# Feature: neurohub-global-registry, Property 22: JWT claims completeness
@settings(max_examples=50)
@given(username=_IDENTIFIER, is_admin=st.booleans())
def test_jwt_claims_completeness(username: str, is_admin: bool) -> None:
    """An issued access token carries user_id, username, roles and exp claims."""
    user = UserDB(
        id=f"id-{username}",
        username=username,
        email=f"{username}@x.test",
        full_name="X",
        hashed_password="x",
        is_active=True,
        is_admin=is_admin,
    )
    token = issue_access_token(user)
    payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    assert payload["user_id"] == user.id
    assert payload["username"] == username
    assert payload["roles"] == (["admin"] if is_admin else ["user"])
    assert "exp" in payload
    # verify_token accepts the freshly issued token.
    assert verify_token(token)["username"] == username


# Feature: neurohub-global-registry, Property 23: password storage safety
# Printable ASCII keeps the byte length == char length, within bcrypt's 72-byte limit.
# deadline=None: bcrypt hashing is intentionally slow and exceeds Hypothesis's default.
@settings(max_examples=20, deadline=None)
@given(
    password=st.text(
        alphabet=st.characters(min_codepoint=33, max_codepoint=126), min_size=1, max_size=64
    )
)
def test_password_storage_safety(password: str) -> None:
    """The stored hash never equals the plaintext and verifies correctly."""
    hashed = get_password_hash(password)
    assert hashed != password
    assert verify_password(password, hashed) is True
