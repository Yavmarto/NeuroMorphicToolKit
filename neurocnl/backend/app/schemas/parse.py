"""Pydantic models for the /api/parse endpoint."""

from pydantic import BaseModel

from backend.app.schemas.common import ErrorDetail


class ParsedSpec(BaseModel):
    concept: str
    subject: str
    action: str
    verb: str
    negated: bool
    condition: str | None = None
    shape: list[int] | None = None
    connectivity_pattern: str | None = None
    connectivity_mask: list[list[int]] | None = None
    locality_radius: float | None = None
    connection_density: float | None = None


class ParseSentence(BaseModel):
    line: int
    raw: str
    parsed: ParsedSpec | None = None
    valid: bool
    error: str | None = None
    error_detail: ErrorDetail | None = None


class ParseRequest(BaseModel):
    spec: str


class ParseResponse(BaseModel):
    sentences: list[ParseSentence]
    total: int
    errors: int
