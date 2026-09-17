"""Token-cursor utilities shared by every NIR-Native CNL sentence parser.

Extracted from :mod:`neurocnl.nir_cnl.parser` (Stage 6 refactor, extended
in a later pass). This module owns identifier validation, the greedy
longest-match phrase matchers, the bare value-token parsers (int tuple /
value tuple / scalar number / int scalar), the metadata string-unquoting
helper, and the clause-level cursor helpers built on top of them (bare
keyword consumption, clause-boundary lookahead, param-/metadata-clause
assembly, and Train-clause classification) — the generic building blocks
that every per-sentence parser in :mod:`~neurocnl.nir_cnl.parser`
composes. Behaviour, diagnostics, and error codes are unchanged by this
move.
"""

from __future__ import annotations

import re

from neurocnl.nir_cnl.diagnostics import SentenceError
from neurocnl.nir_cnl.grammar_tables import (
    ParamSpec,
    loss_function_id_to_phrase,
    loss_function_phrase_to_id,
    noun_phrase_to_primitive,
    optimizer_id_to_phrase,
    optimizer_phrase_to_id,
    parameter_phrases,
    training_strategy_id_to_phrase,
    training_strategy_phrase_to_id,
)
from neurocnl.nir_cnl.ir_types import ArraySpec, ArrayValues
from neurocnl.nir_cnl.tokenizer import Token

__all__ = [
    "_IDENTIFIER_TOKEN_KINDS",
    "_SORTED_NOUN_PHRASES",
    "_classify_train_clause",
    "_consume_longest_noun_phrase",
    "_consume_longest_param_phrase",
    "_consume_longest_phrase",
    "_expect_word",
    "_find_clause_end",
    "_merge_clause_parts",
    "_parse_int_scalar",
    "_parse_int_tuple",
    "_parse_metadata_clause",
    "_parse_param_clause",
    "_parse_scalar_number",
    "_parse_value_tuple",
    "_sorted_param_phrases",
    "_unquote_string",
    "_validate_identifier",
]


# ---------------------------------------------------------------------------
# Identifier validation (Requirement 1.3)
# ---------------------------------------------------------------------------


# The canonical Requirement 1.3 contract is ``[A-Za-z_][A-Za-z0-9_]*``,
# but the renderer is required (Requirement 3.3) to round-trip every
# ``nir.NIRGraph.nodes`` dict key verbatim, and the eight reference
# fixtures contain digit-leading keys (``"0"``, ``"12"``) and dotted
# keys (``"lif1.w_rec"``, ``"lif1.lif"``). Rejecting these on the
# parser side would make Requirement 6 unreachable for the very
# fixtures it pins. We therefore widen the accepted identifier
# alphabet to also admit a leading digit and an internal ``.``
# segment separator while keeping every other property of the
# original contract — length 1–64, no whitespace, no quoting, no
# Structured_DSL_Tokens (the legacy-token validator runs first).
_IDENTIFIER_RE = re.compile(
    r"^(?:[A-Za-z_][A-Za-z0-9_]*"
    r"|\d+"
    r"|[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)$"
)
_IDENTIFIER_MAX_LEN = 64
# Token kinds that may appear at an identifier slot. ``word`` covers
# the canonical ``[A-Za-z_]…`` form; ``number`` covers digit-only
# fixture keys such as ``"0"``; ``dotted`` covers dotted fixture keys
# such as ``"lif1.w_rec"``.
_IDENTIFIER_TOKEN_KINDS = ("word", "number", "dotted")


def _validate_identifier(name: str) -> bool:
    """Return ``True`` iff *name* matches the Requirement 1.3 contract."""
    return (
        1 <= len(name) <= _IDENTIFIER_MAX_LEN and _IDENTIFIER_RE.match(name) is not None
    )


# ---------------------------------------------------------------------------
# Greedy phrase matchers
# ---------------------------------------------------------------------------


# A canonical alphabetised list of valid noun phrases used in the
# ``unknown_primitive_phrase`` diagnostic hint.
_SORTED_NOUN_PHRASES: list[str] = sorted(noun_phrase_to_primitive.keys())


def _consume_longest_phrase(
    tokens: list[Token], pos: int, phrase_to_id: dict[str, str]
) -> tuple[str | None, int]:
    """Greedy-match the longest entry of *phrase_to_id* at *pos*.

    Generic longest-match routine shared by every closed-vocabulary
    lookup in the grammar (Primitive noun phrases, and the pipeline
    optimizer/training-strategy/loss-function/export-target phrase
    tables). Compares case-insensitively. Returns the mapped id and the
    number of tokens consumed, or ``(None, 0)`` when no candidate
    matches.
    """
    remaining = len(tokens) - pos
    candidates = sorted(phrase_to_id.keys(), key=lambda p: (-len(p.split()), p))
    for phrase in candidates:
        phrase_tokens = phrase.split()
        n = len(phrase_tokens)
        if n > remaining:
            continue
        ok = True
        for i in range(n):
            tok = tokens[pos + i]
            if tok.kind != "word" or tok.value.lower() != phrase_tokens[i]:
                ok = False
                break
        if ok:
            return phrase_to_id[phrase], n
    return None, 0


def _consume_longest_noun_phrase(
    tokens: list[Token], pos: int
) -> tuple[str | None, int]:
    """Greedy-match the longest entry of ``noun_phrase_to_primitive``.

    Compares case-insensitively (Requirement 1.10). Returns the
    primitive class name and the number of tokens consumed, or
    ``(None, 0)`` when no candidate matches.
    """
    return _consume_longest_phrase(tokens, pos, noun_phrase_to_primitive)


def _sorted_param_phrases(primitive: str) -> list[str]:
    """Alphabetised list of every parameter phrase for *primitive*.

    Used as the ``hint`` payload for ``unknown_parameter_phrase``
    diagnostics (Requirement 1.12).
    """
    if primitive not in parameter_phrases:
        return []
    return sorted(spec.phrase for spec in parameter_phrases[primitive].values())


def _consume_longest_param_phrase(
    tokens: list[Token], pos: int, primitive: str
) -> tuple[str | None, ParamSpec | None, int]:
    """Greedy-match the longest parameter phrase for *primitive*.

    Returns ``(arg_name, spec, n_consumed)``. ``arg_name`` is ``None``
    when no phrase matches.
    """
    if primitive not in parameter_phrases:
        return None, None, 0
    table = parameter_phrases[primitive]
    candidates = sorted(
        table.items(),
        key=lambda kv: (-len(kv[1].phrase.split()), kv[1].phrase),
    )
    remaining = len(tokens) - pos
    for arg_name, spec in candidates:
        phrase_tokens = spec.phrase.split()
        n = len(phrase_tokens)
        if n > remaining:
            continue
        ok = True
        for i in range(n):
            tok = tokens[pos + i]
            if tok.kind != "word" or tok.value.lower() != phrase_tokens[i]:
                ok = False
                break
        if ok:
            return arg_name, spec, n
    return None, None, 0


# ---------------------------------------------------------------------------
# Value-token parsers
# ---------------------------------------------------------------------------


def _parse_int_tuple(
    tokens: list[Token], pos: int, *, validate_shape: bool = True
) -> tuple[tuple[int, ...], int]:
    """Parse ``(d1, d2, ..., dN)`` where each dᵢ is a positive integer.

    Per Requirement 4.3 / 11.7, when ``validate_shape`` is true each
    ``dᵢ`` must lie in the inclusive range ``[1, 4096]`` and be an
    integer. Trailing commas (``(N,)`` for the 1-D mandatory form per
    Requirement 2.5) are accepted.
    """
    if pos >= len(tokens) or tokens[pos].kind != "lparen":
        raise SentenceError(
            code="invalid_shape",
            message="Expected '(' to begin tuple literal.",
            hint="Use the form: (d1, d2, ...) — for 1-D, (N,).",
        )
    pos += 1  # consume '('
    values: list[int] = []
    while pos < len(tokens) and tokens[pos].kind != "rparen":
        if tokens[pos].kind == "comma":
            pos += 1
            continue
        if tokens[pos].kind != "number":
            raise SentenceError(
                code="invalid_shape",
                message=(
                    f"Expected integer in tuple literal, got {tokens[pos].value!r}."
                ),
                hint="Tuple entries must be positive integers in [1, 4096].",
            )
        raw = tokens[pos].value
        try:
            v = int(raw)
        except ValueError:
            raise SentenceError(
                code="invalid_shape",
                message=(f"Tuple entry {raw!r} is not an integer."),
                hint="Tuple entries must be positive integers in [1, 4096].",
            ) from None
        if validate_shape and not (1 <= v <= 4096):
            raise SentenceError(
                code="invalid_shape",
                message=(f"Tuple entry {v} is outside the documented range [1, 4096]."),
                hint="Each dimension must be a positive integer ≤ 4096.",
            )
        values.append(v)
        pos += 1
    if pos >= len(tokens):
        raise SentenceError(
            code="invalid_shape",
            message="Unclosed tuple literal: missing ')'.",
        )
    pos += 1  # consume ')'
    return tuple(values), pos


def _parse_value_tuple(tokens: list[Token], pos: int) -> tuple[tuple[float, ...], int]:
    """Parse ``(v1, v2, ..., vM)`` as a flat tuple of floats.

    Used for the ``<phrase> values (...)`` clause of array-bearing
    parameters (Requirement 5.13). Trailing commas are accepted.
    """
    if pos >= len(tokens) or tokens[pos].kind != "lparen":
        raise SentenceError(
            code="invalid_value",
            message="Expected '(' to begin values list.",
        )
    pos += 1
    values: list[float] = []
    while pos < len(tokens) and tokens[pos].kind != "rparen":
        if tokens[pos].kind == "comma":
            pos += 1
            continue
        if tokens[pos].kind != "number":
            raise SentenceError(
                code="invalid_value",
                message=(f"Expected number in values list, got {tokens[pos].value!r}."),
            )
        try:
            values.append(float(tokens[pos].value))
        except ValueError:
            raise SentenceError(
                code="invalid_value",
                message=(f"Could not parse {tokens[pos].value!r} as a number."),
            ) from None
        pos += 1
    if pos >= len(tokens):
        raise SentenceError(
            code="invalid_value",
            message="Unclosed values list: missing ')'.",
        )
    pos += 1
    return tuple(values), pos


def _parse_scalar_number(tokens: list[Token], pos: int) -> tuple[float | int, int]:
    """Parse a single numeric token.

    Returns a Python ``int`` when the source token contains neither a
    decimal point nor an exponent and a ``float`` otherwise. The
    distinction matters for round-trip identity of integer structural
    parameters such as ``groups`` and ``start_dim``.
    """
    if pos >= len(tokens) or tokens[pos].kind != "number":
        got = tokens[pos].value if pos < len(tokens) else "<end of sentence>"
        raise SentenceError(
            code="invalid_value",
            message=f"Expected numeric literal, got {got!r}.",
        )
    raw = tokens[pos].value
    if "." in raw or "e" in raw.lower():
        return float(raw), pos + 1
    return int(raw), pos + 1


def _parse_int_scalar(tokens: list[Token], pos: int, phrase: str) -> tuple[int, int]:
    """Parse a single integer numeric token (``int_scalar`` kind)."""
    if pos >= len(tokens) or tokens[pos].kind != "number":
        got = tokens[pos].value if pos < len(tokens) else "<end of sentence>"
        raise SentenceError(
            code="invalid_value",
            message=f"Expected integer for {phrase!r}, got {got!r}.",
        )
    raw = tokens[pos].value
    try:
        return int(raw), pos + 1
    except ValueError:
        raise SentenceError(
            code="invalid_value",
            message=f"Expected integer for {phrase!r}, got {raw!r}.",
        ) from None


# ---------------------------------------------------------------------------
# Metadata-value helpers
# ---------------------------------------------------------------------------


def _unquote_string(token_value: str) -> str:
    """Strip surrounding double quotes and decode common escapes.

    Recognised escapes: ``\\n``, ``\\t``, ``\\r``, ``\\"``, ``\\\\``.
    Any other ``\\X`` sequence is preserved literally so the parser
    cannot lose information from a metadata payload it does not
    understand.
    """
    if len(token_value) >= 2 and token_value[0] == '"' and token_value[-1] == '"':
        body = token_value[1:-1]
    else:
        body = token_value
    out: list[str] = []
    i = 0
    n = len(body)
    while i < n:
        ch = body[i]
        if ch == "\\" and i + 1 < n:
            nxt = body[i + 1]
            if nxt == "n":
                out.append("\n")
            elif nxt == "t":
                out.append("\t")
            elif nxt == "r":
                out.append("\r")
            elif nxt == '"':
                out.append('"')
            elif nxt == "\\":
                out.append("\\")
            else:
                out.append(body[i : i + 2])
            i += 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


# ---------------------------------------------------------------------------
# Sentence-clause cursor helpers
# ---------------------------------------------------------------------------
#
# Relocated from :mod:`neurocnl.nir_cnl.parser` alongside the other
# generic, grammar-agnostic building blocks every per-sentence parser
# composes: bare keyword consumption, clause-boundary lookahead, and the
# param-clause / metadata-clause assemblers built directly on top of the
# phrase matchers and value-token parsers above. Behaviour, diagnostics,
# and error codes are unchanged by this move.


def _expect_word(
    tokens: list[Token], pos: int, expected: str, *, code: str = "syntax_error"
) -> int:
    """Consume one word token whose lower-cased value equals *expected*."""
    if pos >= len(tokens):
        raise SentenceError(
            code=code,
            message=(f"Expected keyword {expected!r} but reached end of sentence."),
        )
    tok = tokens[pos]
    if tok.kind != "word" or tok.value.lower() != expected.lower():
        raise SentenceError(
            code=code,
            message=f"Expected keyword {expected!r}, got {tok.value!r}.",
        )
    return pos + 1


def _find_clause_end(tokens: list[Token], pos: int) -> int:
    """Return the index of the next top-level clause connective.

    A clause runs from *pos* up to (but not including) the next comma
    token or bare ``and`` word token, or to the end of the sentence.
    Pipeline clause values never contain parentheses, so no nesting
    tracking is needed (unlike the node-sentence parameter grammar).
    """
    i = pos
    while i < len(tokens):
        if tokens[i].kind == "comma":
            return i
        if tokens[i].kind == "word" and tokens[i].value.lower() == "and":
            return i
        i += 1
    return i


def _parse_param_clause(
    tokens: list[Token], pos: int, primitive: str
) -> tuple[str, str, object, int]:
    """Parse one ``with``-clause for *primitive*.

    Returns ``(arg_name, sub_form, value, new_pos)`` where ``sub_form``
    is one of ``"shape"``, ``"values"``, ``"scalar"``, ``"int_tuple"``,
    or ``"int_scalar"``. The caller merges multiple sub-forms targeting
    the same ``arg_name`` (typically ``shape`` + ``values``) into the
    final :class:`ArrayValues` / :class:`ArraySpec` value.
    """
    arg_name, spec, n = _consume_longest_param_phrase(tokens, pos, primitive)
    if arg_name is None or spec is None:
        valid = _sorted_param_phrases(primitive)
        raise SentenceError(
            code="unknown_parameter_phrase",
            message=(f"Unknown parameter phrase for primitive {primitive!r}."),
            hint=(
                f"Valid phrases: {', '.join(valid)}"
                if valid
                else "No parameters defined for this primitive."
            ),
        )
    pos += n
    kind = spec.kind

    if kind in ("tensor", "vector"):
        # Either the sub-keyword ``shape``/``values``, or — for
        # ``vector`` only — a bare numeric literal that the compiler
        # broadcasts to the documented shape.
        if (
            pos < len(tokens)
            and tokens[pos].kind == "word"
            and tokens[pos].value.lower() == "shape"
        ):
            pos += 1
            shape, pos = _parse_int_tuple(tokens, pos, validate_shape=True)
            return arg_name, "shape", shape, pos
        if (
            pos < len(tokens)
            and tokens[pos].kind == "word"
            and tokens[pos].value.lower() == "values"
        ):
            pos += 1
            vals, pos = _parse_value_tuple(tokens, pos)
            return arg_name, "values", vals, pos
        if kind == "vector" and pos < len(tokens) and tokens[pos].kind == "number":
            v, pos = _parse_scalar_number(tokens, pos)
            return arg_name, "scalar", float(v), pos
        raise SentenceError(
            code="invalid_value",
            message=(
                f"Expected 'shape', 'values', or scalar after phrase {spec.phrase!r}."
            ),
        )

    if kind == "int_tuple":
        # Structural integer tuples (``stride``, ``padding``,
        # ``dilation``, ``kernel_size``, ``input_shape``) are not
        # shape literals — Requirements 4.3 and 4.9 pin the
        # ``[1, 4096]`` range to shape literals only. Permit zero
        # and the full int range here so legitimate values such as
        # ``padding (0, 0)`` round-trip.
        result, pos = _parse_int_tuple(tokens, pos, validate_shape=False)
        return arg_name, "int_tuple", result, pos

    if kind == "int_scalar":
        v, pos = _parse_int_scalar(tokens, pos, spec.phrase)
        return arg_name, "int_scalar", v, pos

    if kind == "scalar":
        v, pos = _parse_scalar_number(tokens, pos)
        return arg_name, "scalar", float(v), pos

    # Defensive — every documented kind is handled above. Reaching this
    # branch indicates a grammar-table change without a parser update.
    raise SentenceError(
        code="syntax_error",
        message=f"Internal: unhandled ParamSpec.kind {kind!r}.",
    )


def _merge_clause_parts(
    working: dict[str, dict[str, object]],
) -> dict[str, int | float | ArraySpec | ArrayValues | tuple[int, ...]]:
    """Collapse the per-arg sub-form map into the final ``params`` dict.

    The CNL grammar lets the renderer split an array-bearing parameter
    across two clauses (``<phrase> shape (...)`` and ``<phrase> values
    (...)``). The accumulator stores each piece under its sub-form key
    while parsing; this helper merges them into the canonical record
    types used by the compiler.
    """
    out: dict[str, int | float | ArraySpec | ArrayValues | tuple[int, ...]] = {}
    for arg, parts in working.items():
        if "shape" in parts and "values" in parts:
            out[arg] = ArrayValues(
                shape=parts["shape"],  # type: ignore[arg-type]
                values=parts["values"],  # type: ignore[arg-type]
            )
        elif "shape" in parts:
            out[arg] = ArraySpec(shape=parts["shape"])  # type: ignore[arg-type]
        elif "values" in parts:
            # ``values`` without ``shape`` is unusual; preserve the raw
            # tuple so the compiler can either reject it or treat it as
            # a 1-D vector at materialisation time.
            out[arg] = parts["values"]  # type: ignore[assignment]
        elif "scalar" in parts:
            out[arg] = parts["scalar"]  # type: ignore[assignment]
        elif "int_tuple" in parts:
            out[arg] = parts["int_tuple"]  # type: ignore[assignment]
        elif "int_scalar" in parts:
            out[arg] = parts["int_scalar"]  # type: ignore[assignment]
    return out


def _parse_metadata_clause(
    tokens: list[Token], pos: int, metadata: dict[str, str | int | float]
) -> int:
    """Consume one ``annotated with metadata <key> equal to <value>`` clause.

    Mutates *metadata* in place. Raises a ``duplicate_metadata_key``
    sentence error when the key has already been recorded for this
    sentence (Requirement 10.6).
    """
    pos = _expect_word(tokens, pos, "annotated")
    pos = _expect_word(tokens, pos, "with")
    pos = _expect_word(tokens, pos, "metadata")
    if pos >= len(tokens) or tokens[pos].kind != "word":
        raise SentenceError(
            code="syntax_error",
            message="Expected metadata key after 'metadata'.",
        )
    key = tokens[pos].value
    pos += 1
    pos = _expect_word(tokens, pos, "equal")
    pos = _expect_word(tokens, pos, "to")
    if pos >= len(tokens):
        raise SentenceError(
            code="syntax_error",
            message="Expected metadata value after 'equal to'.",
        )
    tok = tokens[pos]
    value: str | int | float
    if tok.kind == "string":
        value = _unquote_string(tok.value)
        pos += 1
    elif tok.kind == "number":
        v, pos = _parse_scalar_number(tokens, pos)
        value = v
    else:
        raise SentenceError(
            code="syntax_error",
            message=(f"Metadata value must be a string or number, got {tok.value!r}."),
        )
    if key in metadata:
        raise SentenceError(
            code="duplicate_metadata_key",
            message=f"Duplicate metadata key {key!r}.",
            hint="Each metadata key may appear at most once per node.",
        )
    metadata[key] = value
    return pos


def _classify_train_clause(clause_tokens: list[Token]) -> tuple[str, object]:
    """Classify one ``Train`` sentence ``with``-clause.

    Returns ``(kind, value)`` where ``kind`` is one of
    ``"learning_rate"``, ``"batch_size"``, ``"optimizer"``,
    ``"training_strategy"``, or ``"loss_function"``. Clause kind is
    determined by inspecting the clause's fixed keyword position: the
    two numeric clauses (``learning rate``, ``batch size``) are
    identified by their leading two-word phrase; the three
    closed-vocabulary clauses (optimizer, training strategy, loss
    function) are identified by their *trailing* fixed suffix, since
    the closed-vocabulary value phrase precedes the suffix
    (e.g. ``Adam optimizer``, ``surrogate gradient training
    strategy``, ``mse count loss``).
    """
    lowered = [
        tok.value.lower() if tok.kind == "word" else tok.value for tok in clause_tokens
    ]

    if (
        len(clause_tokens) >= 3
        and lowered[0] == "learning"
        and lowered[1] == "rate"
        and clause_tokens[2].kind == "number"
    ):
        if len(clause_tokens) != 3:
            raise SentenceError(
                code="syntax_error",
                message="Unexpected tokens in 'learning rate' clause.",
            )
        return "learning_rate", float(clause_tokens[2].value)

    if (
        len(clause_tokens) >= 3
        and lowered[0] == "batch"
        and lowered[1] == "size"
        and clause_tokens[2].kind == "number"
    ):
        if len(clause_tokens) != 3:
            raise SentenceError(
                code="syntax_error",
                message="Unexpected tokens in 'batch size' clause.",
            )
        v, _pos = _parse_int_scalar(clause_tokens, 2, "batch size")
        return "batch_size", v

    if (
        clause_tokens
        and clause_tokens[-1].kind == "word"
        and lowered[-1] == "optimizer"
    ):
        phrase = " ".join(lowered[:-1])
        optimizer_id = optimizer_phrase_to_id.get(phrase)
        if optimizer_id is None:
            raise SentenceError(
                code="unknown_optimizer_phrase",
                message=f"Unknown optimizer phrase {phrase!r}.",
                hint=f"Valid optimizers: {', '.join(sorted(optimizer_id_to_phrase.values()))}",
            )
        return "optimizer", optimizer_id

    if len(clause_tokens) >= 3 and lowered[-2:] == ["training", "strategy"]:
        phrase = " ".join(lowered[:-2])
        strategy_id = training_strategy_phrase_to_id.get(phrase)
        if strategy_id is None:
            raise SentenceError(
                code="unknown_training_strategy_phrase",
                message=f"Unknown training strategy phrase {phrase!r}.",
                hint=(
                    "Valid training strategies: "
                    f"{', '.join(sorted(training_strategy_id_to_phrase.values()))}"
                ),
            )
        return "training_strategy", strategy_id

    if clause_tokens and clause_tokens[-1].kind == "word" and lowered[-1] == "loss":
        phrase = " ".join(lowered[:-1])
        loss_id = loss_function_phrase_to_id.get(phrase)
        if loss_id is None:
            raise SentenceError(
                code="unknown_loss_function_phrase",
                message=f"Unknown loss function phrase {phrase!r}.",
                hint=(
                    "Valid loss functions: "
                    f"{', '.join(sorted(loss_function_id_to_phrase.values()))}"
                ),
            )
        return "loss_function", loss_id

    raw = " ".join(tok.value for tok in clause_tokens)
    raise SentenceError(
        code="syntax_error",
        message=f"Unrecognised training clause: {raw!r}.",
        hint=(
            "Expected 'learning rate <n>', 'batch size <n>', "
            "'<optimizer> optimizer', '<strategy> training strategy', "
            "or '<loss> loss'."
        ),
    )
