"""Sentence-scoped diagnostic utilities for the NIR-CNL parser."""

from __future__ import annotations

from neurocnl.nir_cnl.errors import Diagnostic
from neurocnl.nir_cnl.tokenizer import Token

__all__ = [
    "MAX_DIAGNOSTICS",
    "MAX_RAW_LEN",
    "SentenceError",
    "diagnostic_from_sentence",
    "finalize_diagnostics",
    "sentence_raw",
]


# Requirement 9.1 caps each diagnostic's ``raw`` field at 1000 chars.
MAX_RAW_LEN = 1000

# Requirement 9.4 caps the diagnostic list at 10 000 entries.
MAX_DIAGNOSTICS = 10_000


class SentenceError(Exception):
    """Stop one sentence parse while retaining structured error details."""

    __slots__ = ("code", "msg", "hint")

    def __init__(self, code: str, message: str, hint: str = "") -> None:
        super().__init__(message)
        self.code = code
        self.msg = message
        self.hint = hint


def sentence_raw(tokens: list[Token]) -> str:
    """Reassemble a sentence for a bounded diagnostic payload."""
    return " ".join(token.value for token in tokens)


def diagnostic_from_sentence(
    error: SentenceError,
    tokens: list[Token],
) -> Diagnostic:
    """Convert an internal sentence failure to the public diagnostic contract."""
    line = tokens[0].line if tokens else None
    return Diagnostic(
        stage="parser",
        code=error.code,
        message=error.msg,
        line=line,
        raw=sentence_raw(tokens)[:MAX_RAW_LEN],
        hint=error.hint,
    )


def finalize_diagnostics(diagnostics: list[Diagnostic]) -> list[Diagnostic]:
    """Return diagnostics in stable source order and enforce the public cap."""
    diagnostics.sort(key=lambda diagnostic: diagnostic.line or 0)
    del diagnostics[MAX_DIAGNOSTICS:]
    return diagnostics
