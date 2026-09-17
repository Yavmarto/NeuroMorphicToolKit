"""Characterization tests for extracted NIR-CNL diagnostic utilities."""

from neurocnl.nir_cnl import parser
from neurocnl.nir_cnl.diagnostics import (
    MAX_DIAGNOSTICS,
    MAX_RAW_LEN,
    SentenceError,
    diagnostic_from_sentence,
    finalize_diagnostics,
    sentence_raw,
)
from neurocnl.nir_cnl.errors import Diagnostic
from neurocnl.nir_cnl.tokenizer import Token


def test_parser_keeps_diagnostic_compatibility_aliases() -> None:
    assert parser._SentenceError is SentenceError
    assert parser._MAX_DIAGNOSTICS == MAX_DIAGNOSTICS
    assert parser._MAX_RAW_LEN == MAX_RAW_LEN
    assert parser._sentence_raw is sentence_raw


def test_sentence_error_maps_to_bounded_public_diagnostic() -> None:
    tokens = [Token(kind="word", value="x" * (MAX_RAW_LEN + 1), line=4)]

    diagnostic = diagnostic_from_sentence(
        SentenceError("syntax_error", "Bad sentence.", "Fix it."),
        tokens,
    )

    assert diagnostic == Diagnostic(
        stage="parser",
        code="syntax_error",
        message="Bad sentence.",
        line=4,
        raw="x" * MAX_RAW_LEN,
        hint="Fix it.",
    )


def test_finalize_diagnostics_is_stable_and_capped() -> None:
    diagnostics = [
        Diagnostic("parser", "later", "later", 2, "", ""),
        Diagnostic("parser", "first", "first", 1, "", ""),
        Diagnostic("parser", "same-line", "same-line", 2, "", ""),
    ]

    result = finalize_diagnostics(diagnostics)

    assert result is diagnostics
    assert [diagnostic.code for diagnostic in result] == [
        "first",
        "later",
        "same-line",
    ]
