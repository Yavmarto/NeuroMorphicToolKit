"""Property-based tests for the CLI ``neurohub://`` URI parser.

Covers correctness Properties 9-14 from
``.kiro/specs/neurohub-global-registry/design.md`` against the CLI's
``uri_parser`` copy, including behavioural equivalence with the backend copy
(Property 14).
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from neurocli.uri_parser import ArtefactType, URIParseError, build_uri, parse_uri

_IDENTIFIER = st.from_regex(r"[a-z0-9][a-z0-9-]{0,10}", fullmatch=True)
_TYPES = st.sampled_from([t.value for t in ArtefactType])


@st.composite
def _versions(draw: st.DrawFn) -> str:
    """Generate a valid MAJOR.MINOR.PATCH semver string."""
    a, b, c = (draw(st.integers(min_value=0, max_value=999)) for _ in range(3))
    return f"{a}.{b}.{c}"


@st.composite
def _valid_uris(draw: st.DrawFn) -> str:
    """Generate a conformant ``neurohub://`` URI string."""
    type_ = draw(_TYPES)
    owner_segments = draw(st.lists(_IDENTIFIER, min_size=1, max_size=2))
    owner = "/".join(owner_segments)
    slug = draw(_IDENTIFIER)
    base = f"neurohub://{type_}/{owner}/{slug}"
    if draw(st.booleans()):
        return f"{base}@{draw(_versions())}"
    return base


# Feature: neurohub-global-registry, Property 9: URI round-trip
@settings(max_examples=100)
@given(uri=_valid_uris())
def test_uri_round_trip(uri: str) -> None:
    """build_uri(parse_uri(s)) == s for any conformant URI."""
    assert build_uri(parse_uri(uri)) == uri


# Feature: neurohub-global-registry, Property 10: URI parse idempotence
@settings(max_examples=100)
@given(uri=_valid_uris())
def test_uri_parse_idempotence(uri: str) -> None:
    """Parsing twice yields identical component fields."""
    assert parse_uri(build_uri(parse_uri(uri))) == parse_uri(uri)


# Feature: neurohub-global-registry, Property 11: URI parse error — wrong scheme
@settings(max_examples=100)
@given(
    scheme=st.text(alphabet="abcdefghijklmnopqrstuvwxyz", min_size=1, max_size=8).filter(
        lambda s: s != "neurohub"
    ),
    rest=_valid_uris(),
)
def test_uri_parse_error_wrong_scheme(scheme: str, rest: str) -> None:
    """A non-neurohub scheme raises with the received prefix in the message."""
    bad = rest.replace("neurohub://", f"{scheme}://", 1)
    with pytest.raises(URIParseError) as exc:
        parse_uri(bad)
    assert scheme in str(exc.value)


# Feature: neurohub-global-registry, Property 12: URI parse error — invalid semver
@settings(max_examples=100)
@given(
    type_=_TYPES,
    owner=_IDENTIFIER,
    slug=_IDENTIFIER,
    bad_version=st.text(min_size=1, max_size=8).filter(
        lambda v: __import__("re").fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", v) is None
        and "/" not in v
        and "@" not in v
    ),
)
def test_uri_parse_error_invalid_semver(type_: str, owner: str, slug: str, bad_version: str) -> None:
    """A non-semver @version raises; the same URI without @version does not."""
    with pytest.raises(URIParseError):
        parse_uri(f"neurohub://{type_}/{owner}/{slug}@{bad_version}")
    # No @version segment must NOT raise.
    parse_uri(f"neurohub://{type_}/{owner}/{slug}")


# Feature: neurohub-global-registry, Property 13: URI parse error — missing fields
@settings(max_examples=100)
@given(type_=_TYPES, slug=_IDENTIFIER)
def test_uri_parse_error_missing_fields(type_: str, slug: str) -> None:
    """A neurohub:// URI missing the owner or slug segment raises."""
    with pytest.raises(URIParseError):
        parse_uri(f"neurohub://{type_}")  # only type
    with pytest.raises(URIParseError):
        parse_uri(f"neurohub://{type_}/{slug}")  # type + one segment, no slug pair


def _load_backend_parser() -> ModuleType | None:
    """Import the backend uri_parser copy by path, or return None if unavailable."""
    repo_root = Path(__file__).resolve().parents[3]
    backend_path = repo_root / "Neurohub" / "neurohub" / "app" / "utils" / "uri_parser.py"
    if not backend_path.exists():
        return None
    spec = importlib.util.spec_from_file_location("_backend_uri_parser", backend_path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module  # needed for dataclass string-annotation resolution
    spec.loader.exec_module(module)
    return module


# Feature: neurohub-global-registry, Property 14: CLI–backend URI parse equivalence
@settings(max_examples=100)
@given(uri=_valid_uris())
def test_cli_backend_uri_parse_equivalence(uri: str) -> None:
    """The CLI and backend parsers produce identical field values for valid inputs."""
    backend = _load_backend_parser()
    if backend is None:
        pytest.skip("backend uri_parser not available")
    cli_parsed = parse_uri(uri)
    backend_parsed = backend.parse_uri(uri)
    assert cli_parsed.scheme == backend_parsed.scheme
    assert cli_parsed.type.value == backend_parsed.type.value
    assert cli_parsed.owner == backend_parsed.owner
    assert cli_parsed.slug == backend_parsed.slug
    assert cli_parsed.version == backend_parsed.version


@settings(max_examples=50)
@given(
    scheme=st.text(alphabet="abcdefghijklmnopqrstuvwxyz", min_size=1, max_size=8).filter(
        lambda s: s != "neurohub"
    ),
    rest=_valid_uris(),
)
def test_cli_backend_equivalence_on_errors(scheme: str, rest: str) -> None:
    """Both parsers reject the same invalid input with their URIParseError type."""
    backend = _load_backend_parser()
    if backend is None:
        pytest.skip("backend uri_parser not available")
    bad = rest.replace("neurohub://", f"{scheme}://", 1)
    with pytest.raises(URIParseError):
        parse_uri(bad)
    with pytest.raises(backend.URIParseError):
        backend.parse_uri(bad)
