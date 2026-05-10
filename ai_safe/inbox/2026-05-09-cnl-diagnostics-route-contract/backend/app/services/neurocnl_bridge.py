"""
CNL parsing bridge service.
"""

from typing import Any, TypedDict


class ErrorDetail(TypedDict, total=False):
    """Structured error detail shape for CNL diagnostics."""
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


class ParseError(Exception):
    """Parse error with structured detail."""
    
    def __init__(self, detail: ErrorDetail):
        self.detail = detail
        super().__init__(detail.get("message", "Parse error"))


def parse_spec_text(spec_text: str) -> list[dict[str, Any]]:
    """
    Parse CNL specification text into structured results.
    
    Returns one dict per non-empty line with:
    - line: int - line number (1-indexed)
    - raw: str - original line text
    - parsed: dict | None - parsed structure if valid
    - valid: bool - whether parsing succeeded
    - error: str | None - error message if invalid
    - error_detail: ErrorDetail | None - structured error detail if invalid
    
    Args:
        spec_text: CNL specification text to parse
        
    Returns:
        List of parse result dicts
    """
    # This is a stub implementation that would delegate to the actual parser
    # The real implementation would call the CNL parser and preserve its structured output
    raise NotImplementedError("parse_spec_text must be implemented by the actual parser integration")
