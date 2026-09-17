"""Pydantic v2 contracts for the Neurohub Global Registry (``/api/v1`` surface).

These own the artefact, model-card, search, and community-interaction payloads.
The canonical :class:`ArtefactType` enum is sourced from the shared URI parser so
the registry, the URI grammar, and the CLI never drift apart.
"""

import re

from pydantic import BaseModel, ConfigDict, Field, field_validator

from neurohub.app.utils.uri_parser import ArtefactType

__all__ = [
    "ArtefactType",
    "NeuroBenchScore",
    "ModelCard",
    "ArtefactCreate",
    "ArtefactUpdate",
    "ArtefactResponse",
    "ArtefactListItem",
    "RatingCreate",
    "CommentCreate",
    "CommentResponse",
    "FollowCreate",
    "SearchResponse",
]

# Identifier rule shared with the URI parser: 1-64 lowercase alphanumeric or
# hyphen characters, starting with an alphanumeric (Requirement 2.1).
# \Z anchors at the very end of the string (unlike $, which also matches before a
# trailing newline) so identifiers containing a trailing newline are rejected.
_IDENTIFIER_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,63}\Z")
_SEMVER_RE = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\Z")

MAX_DESCRIPTION_LEN = 1000
MAX_TAGS = 20
MAX_README_LEN = 65535
MAX_COMMENT_LEN = 4000


class NeuroBenchScore(BaseModel):
    """A single NeuroBench metric entry attached to a model card."""

    model_config = ConfigDict(populate_by_name=True)

    benchmark: str
    metric: str | None = None
    value: float | None = None
    hardware_target: str | None = None


class ModelCard(BaseModel):
    """Structured documentation for an ``snn_model`` artefact.

    Unrecognised fields are ignored on input; the artefact router reports any
    stripped field names in a ``warnings`` array (Requirement 5.5).

    ``neurobench_scores`` also doubles as the score payload for a standalone
    ``benchmark_result`` artefact (one run's raw metric values, as opposed to
    ``benchmark_baseline``'s curated reference set) — no separate contract is
    needed since the shape is identical either way.
    """

    model_config = ConfigDict(extra="ignore", populate_by_name=True)

    architecture: str | None = None
    training_framework: str | None = None
    training_dataset: str | None = None
    hardware_targets: list[str] = Field(default_factory=list)
    neurobench_scores: list[NeuroBenchScore] = Field(default_factory=list)
    licence: str | None = None
    ethical_considerations: str | None = None
    readme_md: str | None = Field(default=None, max_length=MAX_README_LEN)


class ArtefactCreate(BaseModel):
    """Metadata payload for ``POST /api/v1/artefacts`` (the blob is multipart).

    ``owner`` is assigned server-side from the authenticated publisher, so it is
    not part of this submission body.
    """

    model_config = ConfigDict(populate_by_name=True)

    type: ArtefactType
    slug: str
    version: str
    description: str | None = Field(default=None, max_length=MAX_DESCRIPTION_LEN)
    tags: list[str] = Field(default_factory=list, max_length=MAX_TAGS)
    readme: str | None = Field(default=None, max_length=MAX_README_LEN)
    model_card: ModelCard | None = None

    @field_validator("slug")
    @classmethod
    def slug_must_be_valid(cls, v: str) -> str:
        """Validate the slug against the canonical identifier rule."""
        if not _IDENTIFIER_RE.match(v):
            raise ValueError(
                "slug must be 1-64 lowercase alphanumeric or hyphen characters "
                "and start with an alphanumeric"
            )
        return v

    @field_validator("version")
    @classmethod
    def version_must_be_semver(cls, v: str) -> str:
        """Validate the version is MAJOR.MINOR.PATCH semver."""
        if not _SEMVER_RE.match(v):
            raise ValueError("version must be MAJOR.MINOR.PATCH semver")
        return v


class ArtefactUpdate(BaseModel):
    """Mutable-only update payload for ``PUT /api/v1/artefacts/...``.

    Immutable fields (``type``, ``owner``, ``slug``, ``version``, ``sha256``,
    ``created_at``) are intentionally absent and cannot be changed (Property 2).
    """

    model_config = ConfigDict(populate_by_name=True)

    description: str | None = Field(default=None, max_length=MAX_DESCRIPTION_LEN)
    tags: list[str] | None = Field(default=None, max_length=MAX_TAGS)
    readme: str | None = Field(default=None, max_length=MAX_README_LEN)
    model_card: ModelCard | None = None


class ArtefactResponse(BaseModel):
    """Full artefact representation including the canonical URI and download URL."""

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)

    id: str
    type: ArtefactType
    owner: str
    slug: str
    version: str
    description: str | None = None
    tags: list[str] = Field(default_factory=list)
    readme: str | None = None
    sha256: str
    file_size_bytes: int
    download_count: int = 0
    average_rating: float = 0.0
    rating_count: int = 0
    model_card: ModelCard | None = None
    created_at: str
    updated_at: str
    neurohub_uri: str
    download_url: str | None = None
    warnings: list[str] = Field(default_factory=list)


class ArtefactListItem(BaseModel):
    """Card-grid projection of an artefact for search and discovery feeds."""

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)

    type: ArtefactType
    owner: str
    slug: str
    version: str
    description: str | None = None
    average_rating: float = 0.0
    rating_count: int = 0
    download_count: int = 0
    neurohub_uri: str


class RatingCreate(BaseModel):
    """Body for submitting or replacing a 1-5 star rating."""

    value: int = Field(..., ge=1, le=5)


class CommentCreate(BaseModel):
    """Body for posting a comment (1-4000 characters)."""

    content: str = Field(..., min_length=1, max_length=MAX_COMMENT_LEN)


class CommentResponse(BaseModel):
    """A persisted comment."""

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)

    id: str
    artefact_id: str
    author_id: str
    content: str
    created_at: str


class FollowCreate(BaseModel):
    """Body for following a publisher."""

    followed_user_id: str


class SearchResponse(BaseModel):
    """Paginated search results with a degraded-mode flag."""

    model_config = ConfigDict(populate_by_name=True)

    items: list[ArtefactListItem]
    total: int
    page: int
    page_size: int
    next_cursor: str | None = None
    search_degraded: bool = False

    @field_validator("page_size")
    @classmethod
    def page_size_in_range(cls, v: int) -> int:
        """Bound the page size to a sane range."""
        if not 1 <= v <= 100:
            raise ValueError("page_size must be between 1 and 100")
        return v
