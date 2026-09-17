"""Tests for extract_numeric utility."""

from neurocnl.utils import extract_numeric


def test_extract_integer() -> None:
    assert extract_numeric("exceeds 5") == 5.0


def test_extract_float() -> None:
    assert extract_numeric("time constant of 0.02 seconds") == 0.02


def test_extract_first_number() -> None:
    assert extract_numeric("between 1.0 and 2.0") == 1.0


def test_no_number_returns_none() -> None:
    assert extract_numeric("no numbers here") is None


def test_none_input() -> None:
    assert extract_numeric(None) is None


def test_empty_string() -> None:
    assert extract_numeric("") is None


def test_default_value() -> None:
    assert extract_numeric("no number", default=42.0) == 42.0


def test_default_not_used_when_number_present() -> None:
    assert extract_numeric("value is 3.14", default=0.0) == 3.14
