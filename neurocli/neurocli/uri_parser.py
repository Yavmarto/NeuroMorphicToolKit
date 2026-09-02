"""Pure-function parser for ``neurohub://`` artefact URIs.

This module has **no I/O dependencies** and is the single source of truth for the
``neurohub://`` URI grammar. It is copied verbatim from the Neurohub backend
(``Neurohub/neurohub/app/utils/uri_parser.py``); the two copies must stay
byte-for-byte equivalent so the CLI and backend agree on parsing (correctness
Property 14).

URI grammar::

    neurohub://{type}/{owner}/{slug}[@{version}]

where ``{owner}`` is either ``{username}`` or ``{org}/{username}`` (so the path
between ``{type}`` and ``{slug}`` is one or two segments). ``{version}``, when
present, is a ``MAJOR.MINOR.PATCH`` semantic version.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import StrEnum

SCHEME = "neurohub"
_SCHEME_PREFIX = f"{SCHEME}://"

# Identifier rule: 1-64 chars, lowercase alphanumerics and hyphens, must start
# with an alphanumeric (Requirement 2.1 / 2.6). \Z (not $) anchors at the very
# end so a trailing newline is rejected.
_IDENTIFIER_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,63}\Z")
# Semantic version: MAJOR.MINOR.PATCH (non-negative integers, no leading zeros).
_SEMVER_RE = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\Z")


class ArtefactType(StrEnum):
    """The nine canonical artefact type keys for the registry."""

    cnl_template = "cnl_template"
    cnlspace = "cnlspace"
    snn_model = "snn_model"
    dataset = "dataset"
    hardware_profile = "hardware_profile"
    encoding_preset = "encoding_preset"
    benchmark_baseline = "benchmark_baseline"
    custom_node = "custom_node"
    benchmark_result = "benchmark_result"


class URIParseError(ValueError):
    """Raised when a string is not a conformant ``neurohub://`` URI."""


@dataclass(frozen=True)
class NeurohubURI:
    """A parsed ``neurohub://`` URI.

    Attributes:
        scheme: Always ``"neurohub"``.
        type: One of the nine canonical artefact types.
        owner: ``"{username}"`` or ``"{org}/{username}"``.
        slug: The artefact slug.
        version: A ``MAJOR.MINOR.PATCH`` string, or ``None`` when absent.
    """

    scheme: str
    type: ArtefactType
    owner: str
    slug: str
    version: str | None


def _validate_identifier(value: str, field: str) -> str:
    """Validate an owner segment or slug against the identifier rule.

    Args:
        value: The candidate identifier.
        field: The field name to name in the error message.

    Returns:
        The validated identifier unchanged.

    Raises:
        URIParseError: If the identifier violates the format constraint.
    """
    if not _IDENTIFIER_RE.match(value):
        raise URIParseError(
            f"Invalid {field} '{value}': must be 1-64 lowercase alphanumeric or "
            f"hyphen characters and start with an alphanumeric"
        )
    return value


def parse_uri(uri: str) -> NeurohubURI:
    """Parse a ``neurohub://`` URI into its component fields.

    Args:
        uri: The URI string to parse.

    Returns:
        The parsed :class:`NeurohubURI`.

    Raises:
        URIParseError: For a wrong scheme prefix, an invalid segment count, a
            missing type or slug, an unknown artefact type, an invalid owner or
            slug identifier, or an invalid semantic version in the ``@version``
            position.
    """
    if not uri.startswith(_SCHEME_PREFIX):
        received = uri.split("://", 1)[0] if "://" in uri else uri
        raise URIParseError(f"Invalid scheme '{received}': URI must start with '{_SCHEME_PREFIX}'")

    remainder = uri[len(_SCHEME_PREFIX) :]

    version: str | None = None
    if "@" in remainder:
        path_part, _, version_part = remainder.rpartition("@")
        if not _SEMVER_RE.match(version_part):
            raise URIParseError(f"Invalid version '{version_part}': must be MAJOR.MINOR.PATCH semver")
        version = version_part
    else:
        path_part = remainder

    segments = path_part.split("/")
    # type + owner(1-2) + slug → 3 or 4 segments.
    if len(segments) not in (3, 4) or any(seg == "" for seg in segments):
        raise URIParseError(
            f"Invalid URI structure '{uri}': expected neurohub://{{type}}/{{owner}}/{{slug}}[@{{version}}]"
        )

    type_segment = segments[0]
    slug = segments[-1]
    owner_segments = segments[1:-1]

    try:
        artefact_type = ArtefactType(type_segment)
    except ValueError as exc:
        valid = ", ".join(t.value for t in ArtefactType)
        raise URIParseError(f"Invalid type '{type_segment}': must be one of {valid}") from exc

    for owner_segment in owner_segments:
        _validate_identifier(owner_segment, "owner")
    _validate_identifier(slug, "slug")

    owner = "/".join(owner_segments)
    return NeurohubURI(
        scheme=SCHEME,
        type=artefact_type,
        owner=owner,
        slug=slug,
        version=version,
    )


def build_uri(parsed: NeurohubURI) -> str:
    """Reconstruct the URI string from a parsed :class:`NeurohubURI`.

    Guarantees the round-trip invariant ``build_uri(parse_uri(s)) == s`` for any
    conformant input ``s`` (correctness Property 9).

    Args:
        parsed: The parsed URI components.

    Returns:
        The ``neurohub://`` URI string.
    """
    base = f"{_SCHEME_PREFIX}{parsed.type.value}/{parsed.owner}/{parsed.slug}"
    if parsed.version is not None:
        return f"{base}@{parsed.version}"
    return base
