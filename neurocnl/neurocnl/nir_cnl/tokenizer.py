"""Tokenization primitives for NIR-native controlled natural language."""

from __future__ import annotations

import re
from dataclasses import dataclass

__all__ = ["Token", "split_sentences", "tokenize"]


@dataclass(frozen=True, slots=True)
class Token:
    """One grammar lexeme with its original value and one-indexed line."""

    kind: str
    value: str
    line: int


_NUMBER_PATTERN = r"-?(?:\d+\.\d+|\.\d+|\d+)(?:[eE][+-]?\d+)?"
_WORD_PATTERN = r"[A-Za-z_][A-Za-z0-9_-]*"
_NUMWORD_PATTERN = r"\d+[A-DF-Za-df-z][A-Za-z0-9_]*"
_DOTTED_NAME_PATTERN = r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+"
_STRING_PATTERN = r'"(?:[^"\\]|\\.)*"'

_TOKEN_RE = re.compile(
    "|".join(
        [
            r"(?P<lparen>\()",
            r"(?P<rparen>\))",
            r"(?P<comma>,)",
            r"(?P<string>" + _STRING_PATTERN + ")",
            r"(?P<dotted>" + _DOTTED_NAME_PATTERN + ")",
            r"(?P<numword>" + _NUMWORD_PATTERN + ")",
            r"(?P<number>" + _NUMBER_PATTERN + ")",
            r"(?P<word>" + _WORD_PATTERN + ")",
            r"(?P<period>\.)",
            r"(?P<ws>\s+)",
        ]
    )
)


def tokenize(text: str) -> list[Token]:
    """Tokenize text while dropping full-line comments and whitespace."""
    tokens: list[Token] = []
    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        if raw_line.lstrip().startswith("#"):
            continue
        pos = 0
        while pos < len(raw_line):
            match = _TOKEN_RE.match(raw_line, pos)
            if match is None:
                pos += 1
                continue
            kind = match.lastgroup
            value = match.group(0)
            pos = match.end()
            if kind == "ws":
                continue
            if kind == "numword":
                kind = "word"
            if kind is None:
                continue
            tokens.append(Token(kind=kind, value=value, line=line_no))
    return tokens


def split_sentences(tokens: list[Token]) -> list[list[Token]]:
    """Split tokens on periods while retaining an unterminated final sentence."""
    sentences: list[list[Token]] = []
    current: list[Token] = []
    for token in tokens:
        if token.kind == "period":
            if current:
                sentences.append(current)
                current = []
        else:
            current.append(token)
    if current:
        sentences.append(current)
    return sentences
