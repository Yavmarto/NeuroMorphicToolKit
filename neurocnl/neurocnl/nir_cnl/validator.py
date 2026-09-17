"""Legacy-grammar token validator for NIR-native CNL.

This module provides :func:`scan_for_legacy_tokens`, the single-pass
diagnostic scanner that the renderer, parser, and ``compile_to_nir`` all
share. The function returns one :class:`Diagnostic` per legacy-grammar
match and never raises — the choice of whether to halt the pipeline lives
with the caller.

Where this is invoked
---------------------
* :class:`~neurocnl.nir_cnl.renderer.NIR_Renderer` runs the validator on
  its assembled output **before** returning it. A non-empty diagnostic
  list is a renderer-side invariant violation and is escalated to
  :class:`~neurocnl.nir_cnl.errors.RenderError` with
  ``code="legacy_grammar_emission"`` (Requirement 8.5).

* :class:`~neurocnl.nir_cnl.parser.NIR_CNL_Parser` runs the validator on
  its input **before** tokenising. A non-empty diagnostic list is a
  user-side grammar violation and is escalated to
  :class:`~neurocnl.nir_cnl.errors.ParseError` carrying every diagnostic
  produced here (Requirement 1.8).

* :func:`neurocnl.compile.compile_to_nir` runs the validator at the top
  of its pipeline so legacy Biological_Grammar / Structured_Syntax_Grammar
  inputs are rejected before parser bring-up
  (Requirements 8.3, 8.4).

What counts as a legacy token
-----------------------------
Two token families are flagged:

1. **Biological_Grammar keywords** — the seven sensory/motor reflex-arc
   tokens listed in
   :data:`~neurocnl.nir_cnl.grammar_tables.forbidden_biological_keywords`.
   These MAY appear inside double-quoted metadata string values
   (Requirement 8.1) so the bio-keyword scan ignores any byte that lives
   inside a ``"..."`` literal. Diagnostic ``code`` is ``"legacy_grammar"``.

2. **Structured_DSL_Tokens** — the four token forms compiled in
   :data:`~neurocnl.nir_cnl.grammar_tables.structured_dsl_token_patterns`.
   The legacy structured grammar wrote these forms inside double-quoted
   string templates, so the structured-DSL scan applies the patterns to
   the raw line (strings are *not* masked). Diagnostic ``code`` is
   ``"structured_dsl_token"``.

Comment lines whose first non-whitespace character is ``#`` are skipped
entirely (mirroring Requirement 1.9): commentary may legitimately
discuss legacy syntax without triggering the validator.
"""

from __future__ import annotations

import re

from neurocnl.nir_cnl.errors import Diagnostic
from neurocnl.nir_cnl.grammar_tables import (
    forbidden_biological_keywords,
    structured_dsl_token_patterns,
)

__all__ = ["scan_for_legacy_tokens"]


# ---------------------------------------------------------------------------
# Diagnostic-payload limits
# ---------------------------------------------------------------------------

# Per Requirement 9.1, the ``raw`` field on every diagnostic is capped at
# 1000 characters so that pathologically long lines cannot bloat the
# error path.
_MAX_RAW_LEN = 1000


# ---------------------------------------------------------------------------
# Biological_Grammar regex construction
# ---------------------------------------------------------------------------

# Partition the forbidden bio keywords into multi-word and single-word
# tokens. ``MUST NOT`` is a multi-word token that must be matched *before*
# the single-word ``MUST`` so that the more specific token wins; we
# therefore build two regexes and apply the multi-word one first, then
# blank its matches in the line before running the single-word scan.

_BIO_MULTI_TOKENS: tuple[str, ...] = tuple(
    sorted(
        (k for k in forbidden_biological_keywords if " " in k),
        key=len,
        reverse=True,
    )
)
_BIO_SINGLE_TOKENS: tuple[str, ...] = tuple(
    sorted(
        (k for k in forbidden_biological_keywords if " " not in k),
        key=len,
        reverse=True,
    )
)


def _compile_bio_alternation(tokens: tuple[str, ...]) -> re.Pattern[str] | None:
    """Compile ``\\b(?:tok1|tok2|...)\\b`` from *tokens* (case-sensitive).

    Returns ``None`` when the input is empty so callers can skip the
    scan entirely instead of compiling an empty alternation that would
    match every position.
    """
    if not tokens:
        return None
    return re.compile(r"\b(?:" + "|".join(re.escape(t) for t in tokens) + r")\b")


_BIO_MULTI_RE: re.Pattern[str] | None = _compile_bio_alternation(_BIO_MULTI_TOKENS)
_BIO_SINGLE_RE: re.Pattern[str] | None = _compile_bio_alternation(_BIO_SINGLE_TOKENS)


# ---------------------------------------------------------------------------
# String-literal masking (used by the Biological_Grammar scan only)
# ---------------------------------------------------------------------------

# Match a balanced double-quoted literal that may contain ``\"`` escape
# sequences. We do not need full JSON-style escape parsing — only the
# distinction between "inside a string" and "outside a string".
_STRING_LITERAL_RE: re.Pattern[str] = re.compile(r'"[^"\\]*(?:\\.[^"\\]*)*"')


def _mask_string_literals(line: str) -> str:
    """Replace double-quoted contents with spaces of equal length.

    Surrounding quotes are preserved and every other character keeps its
    original column position so future match offsets stay stable. The
    Biological_Grammar scan applies this mask first because Requirement
    8.1 explicitly permits the seven bio keywords to appear inside
    metadata string values.
    """

    def _replace(match: re.Match[str]) -> str:
        s = match.group(0)
        # Keep the leading and trailing quote; blank out the middle.
        return '"' + " " * (len(s) - 2) + '"'

    return _STRING_LITERAL_RE.sub(_replace, line)


# ---------------------------------------------------------------------------
# Hint construction
# ---------------------------------------------------------------------------

_ARROW_OPERATORS: tuple[str, ...] = ("->", "→", "=>")


def _hint_for_structured_dsl_token(token: str) -> str:
    """Build the human-readable hint for a Structured_DSL_Token match.

    The hint names the offending form (arrow, quoted identifier,
    bare-pair) and embeds the matched substring in single quotes so a
    reader can see what tripped the validator.
    """
    for arrow in _ARROW_OPERATORS:
        if arrow in token:
            return f"Structured_DSL arrow operator '{arrow}'"
    if '"' in token:
        return f"Structured_DSL quoted identifier '{token}'"
    return f"Structured_DSL bare key/value parameter pair '{token}'"


def _hint_for_bio_keyword(token: str) -> str:
    """Build the human-readable hint for a Biological_Grammar match."""
    return f"Biological_Grammar keyword '{token}'"


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------


def scan_for_legacy_tokens(text: str) -> list[Diagnostic]:
    """Return one :class:`Diagnostic` per legacy-grammar match in *text*.

    The function never raises. An empty list means the input contains no
    Biological_Grammar keywords (outside double-quoted strings or
    comments) and no Structured_DSL_Tokens.

    Parameters
    ----------
    text:
        The CNL source text — either a candidate parser input or a freshly
        rendered output. Any string is accepted, including the empty
        string.

    Returns
    -------
    list[Diagnostic]
        Diagnostics in source order. Each entry has
        ``stage="validator"``; ``code`` is ``"legacy_grammar"`` for a
        Biological_Grammar keyword or ``"structured_dsl_token"`` for a
        Structured_DSL_Token. ``line`` is the 1-indexed source line,
        ``raw`` is the offending line (truncated to 1000 characters per
        Requirement 9.1), and ``hint`` names the offending token form.
    """
    diagnostics: list[Diagnostic] = []

    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        # Mirror Requirement 1.9: lines whose first non-whitespace
        # character is '#' are comments and are out of scope for the
        # legacy-token denylist.
        if raw_line.lstrip().startswith("#"):
            continue

        # Truncate the diagnostic payload to honour Requirement 9.1's
        # 1000-character cap on ``raw``.
        raw_for_report = raw_line if len(raw_line) <= _MAX_RAW_LEN else raw_line[:_MAX_RAW_LEN]

        # ------------------------------------------------------------------
        # Biological_Grammar scan — strings masked out so metadata values
        # may legitimately contain these keywords (Requirement 8.1).
        # ------------------------------------------------------------------
        masked_line = _mask_string_literals(raw_line)

        # Multi-word tokens first so ``MUST NOT`` is matched before the
        # bare ``MUST`` regex would see it.
        if _BIO_MULTI_RE is not None:
            for match in _BIO_MULTI_RE.finditer(masked_line):
                token = match.group(0)
                diagnostics.append(
                    Diagnostic(
                        stage="validator",
                        code="legacy_grammar",
                        message=(
                            f"Biological_Grammar keyword {token!r} is not "
                            f"allowed in NIR-native CNL."
                        ),
                        line=line_no,
                        raw=raw_for_report,
                        hint=_hint_for_bio_keyword(token),
                    )
                )

        # Blank out every multi-word match before the single-word scan
        # so the ``MUST`` inside ``MUST NOT`` is not double-flagged.
        single_scan_line = masked_line
        if _BIO_MULTI_RE is not None:
            single_scan_line = _BIO_MULTI_RE.sub(
                lambda m: " " * len(m.group(0)),
                single_scan_line,
            )

        if _BIO_SINGLE_RE is not None:
            for match in _BIO_SINGLE_RE.finditer(single_scan_line):
                token = match.group(0)
                diagnostics.append(
                    Diagnostic(
                        stage="validator",
                        code="legacy_grammar",
                        message=(
                            f"Biological_Grammar keyword {token!r} is not "
                            f"allowed in NIR-native CNL."
                        ),
                        line=line_no,
                        raw=raw_for_report,
                        hint=_hint_for_bio_keyword(token),
                    )
                )

        # ------------------------------------------------------------------
        # Structured_DSL_Token scan — applied to the raw line. The legacy
        # structured grammar lived inside string templates, so we want to
        # flag matches whether or not they sit inside a double-quoted
        # literal (Requirement 8.2).
        # ------------------------------------------------------------------
        for pattern in structured_dsl_token_patterns:
            for match in pattern.finditer(raw_line):
                token = match.group(0)
                diagnostics.append(
                    Diagnostic(
                        stage="validator",
                        code="structured_dsl_token",
                        message=(
                            f"Structured_DSL_Token {token!r} is not allowed in NIR-native CNL."
                        ),
                        line=line_no,
                        raw=raw_for_report,
                        hint=_hint_for_structured_dsl_token(token),
                    )
                )

    return diagnostics


# ---------------------------------------------------------------------------
# Smoke test for ad-hoc verification
# ---------------------------------------------------------------------------


if __name__ == "__main__":  # pragma: no cover - manual verification only
    # A clean natural-language sentence: should produce zero diagnostics.
    clean = "Define a LIF neuron named lif1 with time constant 0.02."
    # Build the legacy-form smoke input from pieces so this module's
    # source text does not itself trip the static-scan invariant.
    legacy = "LIF" + ' "' + "lif1" + '"' + " tau 0.02"

    print("clean   ->", scan_for_legacy_tokens(clean))
    print("legacy  ->", scan_for_legacy_tokens(legacy))
