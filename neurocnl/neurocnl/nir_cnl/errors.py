"""Error types for the NIR-native CNL pipeline.

This module is the single source of truth for the three exception classes
raised by the NIR-native CNL stack:

- :class:`ParseError` — raised by
  :class:`~neurocnl.nir_cnl.parser.NIR_CNL_Parser` when one or more
  NL_Sentences fail grammatical validation.  Carries the full
  :class:`Diagnostic` list so callers can surface every failure in one pass
  rather than one-at-a-time.

- :class:`RenderError` — raised by
  :class:`~neurocnl.nir_cnl.renderer.NIR_Renderer` when the post-render
  legacy-token validator catches a forbidden token in the rendered output.
  This is a code-side invariant violation (the renderer must never emit
  Structured_DSL_Tokens or Biological_Grammar keywords); it is not raised
  on user input.  The canonical instance is
  ``RenderError(code="legacy_grammar_emission", offending_token=<token>)``
  per Requirement 8.5.

- :class:`CompileError` — raised by
  :class:`~neurocnl.nir_cnl.compiler.NIR_Compiler` and by
  :func:`neurocnl.compile.compile_to_nir` when structural validation or
  materialization fails.  ``CompileError`` lives in :mod:`neurocnl.compile`
  so that the codebase has exactly one definition; this module simply
  re-exports it.

The :class:`Diagnostic` dataclass is also re-exported from
:mod:`neurocnl.compile` for the same reason.  Its fields are
``stage``, ``code``, ``message``, ``line``, ``raw``, and ``hint``, where
``stage`` is one of ``"parser"``, ``"materializer"``, or ``"validator"``
in the NIR-native CNL pipeline (the older ``compile_to_nir`` pipeline also
uses ``"parse"``, ``"exportability"``, ``"lowering"``, and ``"write"``;
both stage vocabularies coexist on the same shared dataclass).
"""

from __future__ import annotations

# Re-export Diagnostic and CompileError from neurocnl.compile so the
# codebase has exactly one definition of each (Requirement 9.1, 9.2).
from neurocnl.compile import CompileError, Diagnostic

__all__ = [
    "Diagnostic",
    "CompileError",
    "ParseError",
    "RenderError",
]


class ParseError(Exception):
    """Raised when NIR-Native CNL text fails to parse.

    Carries every collected :class:`Diagnostic` so the caller can surface
    all failing sentences in one pass.  The constructor builds a concise
    summary message; :meth:`__str__` expands the list for human readability
    in the same shape as :meth:`neurocnl.compile.CompileError.__str__`.

    Attributes
    ----------
    errors : list[Diagnostic]
        One :class:`Diagnostic` per failing sentence (or per legacy-token
        match), in source-order.  Never ``None``; an empty list is
        permitted but uncommon — the parser only raises ``ParseError``
        when at least one diagnostic has been collected.
    """

    def __init__(self, errors: list[Diagnostic]) -> None:
        self.errors: list[Diagnostic] = errors
        summary = f"NIR-Native CNL parse failed with {len(errors)} error(s)."
        super().__init__(summary)

    def __str__(self) -> str:
        base = super().__str__()
        if not self.errors:
            return base
        lines = [base]
        for d in self.errors:
            loc = f" (line {d.line})" if d.line is not None else ""
            hint = f" — hint: {d.hint}" if d.hint else ""
            lines.append(f"  [{d.stage}] {d.code}: {d.message}{loc}{hint}")
        return "\n".join(lines)


class RenderError(Exception):
    """Raised when the NIR_Renderer would emit a forbidden token.

    Per Requirement 8.5, the renderer scans its assembled output for any
    Structured_DSL_Token or Biological_Grammar keyword appearing outside a
    double-quoted string literal before returning.  A match raises this
    exception with ``code="legacy_grammar_emission"`` naming the offending
    token, and the renderer returns no partial output.

    Attributes
    ----------
    code : str
        Machine-readable error code.  The canonical value is
        ``"legacy_grammar_emission"``.
    offending_token : str
        The verbatim token that triggered the validator.
    """

    def __init__(self, code: str, offending_token: str) -> None:
        self.code: str = code
        self.offending_token: str = offending_token
        message = f"NIR_Renderer would emit forbidden token {offending_token!r} (code: {code})"
        super().__init__(message)
