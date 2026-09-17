"""Characterization tests for the extracted NIR-CNL tokenizer."""

from neurocnl.nir_cnl import parser
from neurocnl.nir_cnl.tokenizer import Token, split_sentences, tokenize


def test_parser_keeps_tokenizer_compatibility_exports() -> None:
    assert parser.Token is Token
    assert parser._tokenize is tokenize
    assert parser._split_sentences is split_sentences


def test_tokenizer_preserves_line_numbers_comments_and_numeric_periods() -> None:
    tokens = tokenize(
        "# ignored\nDefine a 2D convolution layer named conv.\nSet value to 1.0."
    )

    assert all(token.line != 1 for token in tokens)
    assert Token(kind="word", value="2D", line=2) in tokens
    assert Token(kind="number", value="1.0", line=3) in tokens
    assert len(split_sentences(tokens)) == 2
