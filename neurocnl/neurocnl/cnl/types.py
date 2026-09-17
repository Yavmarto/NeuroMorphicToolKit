"""Type definitions for CNL parser output."""

from typing import NotRequired, TypedDict


class ErrorDetail(TypedDict, total=False):
    """Structured error detail for parse and validation failures."""

    code: str
    message: str
    hint: str
    examples: list[str]
    line: int
    raw: str
    source: str
    field: str
    value: float | int | str | list[int] | None
    lines: list[int]
    name: str
    reason: str
    check: str
    detail: str
    result: bool
    description: str


class ParsedSentence(TypedDict):
    """Structured output from parsing a single CNL sentence."""

    concept: str
    subject: str
    action: str
    verb: str
    negated: bool
    condition: str | None
    raw: str
    line: NotRequired[int]
    shape: NotRequired[list[int]]
    connectivity_pattern: NotRequired[str]
    connectivity_mask: NotRequired[list[list[int]]]
    locality_radius: NotRequired[float]
    connection_density: NotRequired[float]
    matrix_kind: NotRequired[str]
    weight_matrix: NotRequired[list[list[float]]]
    weight_vector: NotRequired[list[float]]
    weight_shape: NotRequired[list[int]]


class ParseResult(TypedDict):
    """Dictionary for a single line parsing result."""

    line: int
    raw: str
    parsed: ParsedSentence | None
    valid: bool
    error: str | None
    error_detail: ErrorDetail | None
