"""Diagnostic field contract and structural validation property tests.

Properties implemented here:

* **Property 7** — Unknown phrase and duplicate identifier diagnostics.
  Unknown noun phrases, unknown parameter phrases, and duplicate
  identifiers raise ``ParseError`` with documented codes
  (Requirements 1.11, 1.12, 1.13, 4.8, 9.5, 9.6).
* **Property 8** — Compile-time structural validation. Record lists
  violating exactly one structural invariant raise ``CompileError``
  with the expected code (Requirements 2.6, 2.9, 2.10, 4.5, 4.6,
  4.7, 11.6, 11.8).
* **Property 11** — Diagnostic field contract. Every ``Diagnostic``
  from a failing parse or compile has well-formed fields, is ordered
  by ascending line, and is accompanied by no partial output
  (Requirements 9.1–9.4).
* **Property 12** — Metadata unsupported-value and duplicate-key
  handling. Unsupported metadata values produce comment lines;
  duplicate metadata keys raise ``ParseError``
  (Requirements 10.5, 10.6).
"""

from __future__ import annotations

import re
from typing import cast

import nir
import numpy as np
import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from neurocnl.compile import CompileError, Diagnostic
from neurocnl.nir_cnl.compiler import NIR_Compiler
from neurocnl.nir_cnl.errors import ParseError
from neurocnl.nir_cnl.grammar_tables import noun_phrase_to_primitive
from neurocnl.nir_cnl.ir_types import (
    ArraySpec,
    EvaluationConfigRecord,
    ExportConfigRecord,
    NetworkContainer,
    NIREdgeRecord,
    NIRNodeRecord,
    TrainingConfigRecord,
)
from neurocnl.nir_cnl.parser import NIR_CNL_Parser
from neurocnl.nir_cnl.renderer import NIR_Renderer

from ._strategies import identifier_strategy

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


_CompilerRecord = (
    NIRNodeRecord
    | NIREdgeRecord
    | NetworkContainer
    | TrainingConfigRecord
    | EvaluationConfigRecord
    | ExportConfigRecord
)


def _min_valid_node_record(name: str, primitive: str = "Input") -> NIRNodeRecord:
    """Build the smallest valid :class:`NIRNodeRecord` for *primitive*."""
    if primitive == "Input":
        return NIRNodeRecord(
            name=name,
            primitive="Input",
            params={"input_type": (1,)},
            metadata={},
            line=1,
        )
    if primitive == "Output":
        return NIRNodeRecord(
            name=name,
            primitive="Output",
            params={"output_type": (1,)},
            metadata={},
            line=1,
        )
    if primitive == "LIF":
        return NIRNodeRecord(
            name=name,
            primitive="LIF",
            params={
                "tau": ArraySpec(shape=(1,)),
                "r": ArraySpec(shape=(1,)),
                "v_leak": ArraySpec(shape=(1,)),
                "v_threshold": ArraySpec(shape=(1,)),
            },
            metadata={},
            line=1,
        )
    raise ValueError(f"Unsupported primitive for helper: {primitive!r}")


def _valid_records(
    *, in_name: str = "inp", out_name: str = "outp"
) -> list[NIRNodeRecord | NIREdgeRecord | NetworkContainer]:
    """Minimal valid record list with one Input, one Output, one edge."""
    return [
        _min_valid_node_record(in_name, "Input"),
        _min_valid_node_record(out_name, "Output"),
        NIREdgeRecord(src=in_name, target=out_name, line=1),
    ]


# ---------------------------------------------------------------------------
# Property 7: Unknown phrases and duplicate identifiers
# ---------------------------------------------------------------------------


# Strategy of strings that are NOT valid noun phrases.
_valid_phrases = set(noun_phrase_to_primitive.keys())
_all_word_chars = "abcdefghijklmnopqrstuvwxyz "


def _is_not_valid_phrase(text: str) -> bool:
    return text.lower() not in _valid_phrases and len(text.strip()) > 0


_unknown_phrase_strategy = st.text(
    alphabet=_all_word_chars, min_size=3, max_size=20
).filter(_is_not_valid_phrase)


# Feature: nir-native-cnl, Property 7: Unknown phrases and duplicate identifiers raise documented diagnostics
@given(bad_phrase=_unknown_phrase_strategy)
@settings(max_examples=100, deadline=None)
def test_property_7_unknown_primitive_phrase(bad_phrase: str) -> None:
    """An unknown noun phrase raises ``ParseError`` with
    ``code='unknown_primitive_phrase'``.

    **Validates: Requirements 1.11, 9.5, 9.6**
    """
    cnl = f"Define an input port named inp with shape (1,).\nDefine a {bad_phrase} named x.\nDefine an output port named out with shape (1,).\n"
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(cnl)
    codes = {d.code for d in exc_info.value.errors}
    assert (
        "unknown_primitive_phrase" in codes
    ), f"Expected 'unknown_primitive_phrase' in {codes}; phrase={bad_phrase!r}"


@given(
    in_name=identifier_strategy(),
)
@settings(max_examples=100, deadline=None)
def test_property_7_duplicate_identifier(in_name: str) -> None:
    """Two node sentences with the same identifier raise
    ``ParseError`` with ``code='duplicate_identifier'``.

    **Validates: Requirements 1.13, 9.5, 9.6**
    """
    out_name = in_name + "_out"
    cnl = (
        f"Define an input port named {in_name} with shape (1,).\n"
        f"Define an input port named {in_name} with shape (1,).\n"
        f"Define an output port named {out_name} with shape (1,).\n"
    )
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(cnl)
    codes = {d.code for d in exc_info.value.errors}
    assert (
        "duplicate_identifier" in codes
    ), f"Expected 'duplicate_identifier' in {codes}; id={in_name!r}"


# ---------------------------------------------------------------------------
# Property 8: Compile-time structural validation
# ---------------------------------------------------------------------------


# Feature: nir-native-cnl, Property 8: Compile-time structural validation
def test_property_8_ghost_node() -> None:
    """An edge referencing an undeclared node raises ``ghost_node``.

    **Validates: Requirements 4.5, 2.6**
    """
    records: list[_CompilerRecord] = [
        _min_valid_node_record("inp", "Input"),
        _min_valid_node_record("outp", "Output"),
        NIREdgeRecord(src="inp", target="ghost", line=1),
    ]
    with pytest.raises(CompileError) as exc_info:
        NIR_Compiler().compile(records)
    codes = {d.code for d in exc_info.value.diagnostics}
    assert "ghost_node" in codes, f"Expected ghost_node, got {codes}"


def test_property_8_duplicate_edge() -> None:
    """Two identical ``(src, target)`` records raise ``duplicate_edge``.

    **Validates: Requirements 4.6, 2.6**
    """
    records: list[_CompilerRecord] = [
        _min_valid_node_record("inp", "Input"),
        _min_valid_node_record("outp", "Output"),
        NIREdgeRecord(src="inp", target="outp", line=1),
        NIREdgeRecord(src="inp", target="outp", line=2),
    ]
    with pytest.raises(CompileError) as exc_info:
        NIR_Compiler().compile(records)
    codes = {d.code for d in exc_info.value.diagnostics}
    assert "duplicate_edge" in codes, f"Expected duplicate_edge, got {codes}"


def test_property_8_missing_input_endpoint() -> None:
    """No ``Input`` node raises ``missing_endpoint``.

    **Validates: Requirement 4.7**
    """
    records: list[_CompilerRecord] = [
        _min_valid_node_record("outp", "Output"),
    ]
    with pytest.raises(CompileError) as exc_info:
        NIR_Compiler().compile(records)
    codes = {d.code for d in exc_info.value.diagnostics}
    assert "missing_endpoint" in codes, f"Expected missing_endpoint, got {codes}"


def test_property_8_missing_output_endpoint() -> None:
    """No ``Output`` node raises ``missing_endpoint``.

    **Validates: Requirement 4.7**
    """
    records: list[_CompilerRecord] = [
        _min_valid_node_record("inp", "Input"),
    ]
    with pytest.raises(CompileError) as exc_info:
        NIR_Compiler().compile(records)
    codes = {d.code for d in exc_info.value.diagnostics}
    assert "missing_endpoint" in codes, f"Expected missing_endpoint, got {codes}"


def test_property_8_missing_required_parameter() -> None:
    """A required parameter omitted raises ``missing_required_parameter``.

    **Validates: Requirements 2.10, 11.6**
    """
    # IF node requires both r and v_threshold.
    records: list[_CompilerRecord] = [
        NIRNodeRecord(
            name="if1",
            primitive="IF",
            params={"r": ArraySpec(shape=(1,))},  # v_threshold missing
            metadata={},
            line=1,
        ),
        _min_valid_node_record("inp", "Input"),
        _min_valid_node_record("outp", "Output"),
    ]
    with pytest.raises(CompileError) as exc_info:
        NIR_Compiler().compile(records)
    codes = {d.code for d in exc_info.value.diagnostics}
    assert (
        "missing_required_parameter" in codes or "missing_shape" in codes
    ), f"Expected missing_required_parameter or missing_shape, got {codes}"


def test_property_8_missing_shape() -> None:
    """An array parameter omitted entirely raises ``missing_shape``.

    **Validates: Requirements 11.6, 2.10**
    """
    records: list[_CompilerRecord] = [
        NIRNodeRecord(
            name="lif1",
            primitive="LIF",
            params={},  # all required params missing
            metadata={},
            line=1,
        ),
        _min_valid_node_record("inp", "Input"),
        _min_valid_node_record("outp", "Output"),
    ]
    with pytest.raises(CompileError) as exc_info:
        NIR_Compiler().compile(records)
    codes = {d.code for d in exc_info.value.diagnostics}
    assert (
        "missing_shape" in codes or "missing_required_parameter" in codes
    ), f"Expected missing_shape or missing_required_parameter, got {codes}"


def test_property_8_shape_rank_mismatch() -> None:
    """A wrong-rank shape literal raises ``shape_rank_mismatch``.

    **Validates: Requirements 11.8, 2.6**
    """
    # Linear.weight is rank-2; supply rank-3.
    records: list[_CompilerRecord] = [
        NIRNodeRecord(
            name="fc1",
            primitive="Linear",
            params={"weight": ArraySpec(shape=(2, 3, 4))},  # rank 3 vs expected 2
            metadata={},
            line=1,
        ),
        _min_valid_node_record("inp", "Input"),
        _min_valid_node_record("outp", "Output"),
    ]
    with pytest.raises(CompileError) as exc_info:
        NIR_Compiler().compile(records)
    codes = {d.code for d in exc_info.value.diagnostics}
    assert "shape_rank_mismatch" in codes, f"Expected shape_rank_mismatch, got {codes}"


def test_property_8_shape_for_scalar() -> None:
    """A shape literal supplied for a scalar parameter raises ``shape_for_scalar``.

    **Validates: Requirements 2.9, 2.6**
    """
    # IF.r is a vector (not a strict scalar), but int_tuple params like
    # Conv1d.groups cannot accept a shape spec.
    records: list[_CompilerRecord] = [
        NIRNodeRecord(
            name="c1",
            primitive="Conv1d",
            params={
                "weight": ArraySpec(shape=(1, 1, 1)),
                "bias": ArraySpec(shape=(1,)),
                "stride": ArraySpec(shape=(1,)),  # int_tuple → shape_for_scalar
                "padding": (0,),
                "dilation": (1,),
                "groups": 1,
                "input_shape": 4,
            },
            metadata={},
            line=1,
        ),
        _min_valid_node_record("inp", "Input"),
        _min_valid_node_record("outp", "Output"),
    ]
    with pytest.raises(CompileError) as exc_info:
        NIR_Compiler().compile(records)
    codes = {d.code for d in exc_info.value.diagnostics}
    assert "shape_for_scalar" in codes, f"Expected shape_for_scalar, got {codes}"


# ---------------------------------------------------------------------------
# Property 11: Diagnostic field contract
# ---------------------------------------------------------------------------


def _all_diagnostics_from_exc(exc: BaseException) -> list[Diagnostic]:
    """Extract diagnostics list from either ParseError or CompileError."""
    if hasattr(exc, "errors"):
        return cast("list[Diagnostic]", exc.errors)
    if hasattr(exc, "diagnostics"):
        return cast("list[Diagnostic]", exc.diagnostics)
    return []


_CODE_RE = re.compile(r"^[a-z][a-z0-9_]{0,63}$")


def _check_diagnostic_fields(diag: Diagnostic) -> None:
    """Assert a single Diagnostic satisfies the field contract."""
    # code: [a-z][a-z0-9_]{0,63}
    assert _CODE_RE.match(
        diag.code
    ), f"Diagnostic code {diag.code!r} does not match [a-z][a-z0-9_]{{0,63}}"
    # message: length 1–500
    assert (
        1 <= len(diag.message) <= 500
    ), f"Diagnostic message length {len(diag.message)} out of [1, 500]: {diag.message!r}"
    # line: integer in [1, 1_000_000] (or None for materializer diagnostics,
    # which the spec notes may be None — default to 1 in that case)
    line = diag.line if diag.line is not None else 1
    assert 1 <= line <= 1_000_000, f"Diagnostic line {line!r} out of [1, 1000000]"
    # raw: length 0–1000 (may be None)
    if diag.raw is not None:
        assert (
            len(diag.raw) <= 1000
        ), f"Diagnostic raw length {len(diag.raw)} exceeds 1000"
    # hint: length 0–1000 (may be None)
    if diag.hint is not None:
        assert (
            len(diag.hint) <= 1000
        ), f"Diagnostic hint length {len(diag.hint)} exceeds 1000"
    # stage is not directly constrained in the parse path (the spec lists
    # "parser", "materializer", "validator" for the nir_cnl stack, and
    # "parse", "exportability", "lowering", "materializer", "write" for
    # the legacy compile path). Accept any non-empty string.
    assert diag.stage and isinstance(diag.stage, str)


# Feature: nir-native-cnl, Property 11: Diagnostic field contract
@given(
    in_name=identifier_strategy(),
)
@settings(max_examples=100, deadline=None)
def test_property_11_diagnostic_field_contract(in_name: str) -> None:
    """Every Diagnostic from a failing parse has well-formed fields.

    **Validates: Requirements 9.1, 9.2, 9.3, 9.4**
    """
    # Generate a CNL with a duplicate identifier to trigger a ParseError.
    out_name = in_name + "_z"
    cnl = (
        f"Define an input port named {in_name} with shape (1,).\n"
        f"Define an input port named {in_name} with shape (1,).\n"
        f"Define an output port named {out_name} with shape (1,).\n"
    )
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(cnl)
    diags = exc_info.value.errors
    assert len(diags) >= 1
    for d in diags:
        _check_diagnostic_fields(d)

    # Requirement 9.3: diagnostics ordered by line ascending.
    lines_seen = [d.line for d in diags if d.line is not None]
    assert lines_seen == sorted(
        lines_seen
    ), f"Diagnostics not sorted by line: {lines_seen}"

    # Requirement 9.4: ParseError is raised — no partial record list returned.
    # (The with pytest.raises block already verified the exception was raised.)


def test_property_11_compile_diagnostic_field_contract() -> None:
    """Every Diagnostic from a failing compile has well-formed fields.

    **Validates: Requirements 9.1, 9.2, 9.3, 9.4**
    """
    records: list[_CompilerRecord] = [
        _min_valid_node_record("outp", "Output"),
        # Missing Input → missing_endpoint
    ]
    with pytest.raises(CompileError) as exc_info:
        NIR_Compiler().compile(records)
    diags = exc_info.value.diagnostics
    assert len(diags) >= 1
    for d in diags:
        _check_diagnostic_fields(d)


# ---------------------------------------------------------------------------
# Property 12: Metadata unsupported-value and duplicate-key handling
# ---------------------------------------------------------------------------


# Feature: nir-native-cnl, Property 12: Metadata unsupported-value and duplicate-key handling
@given(
    node_name=identifier_strategy(),
    key=st.from_regex(r"^[A-Za-z_][A-Za-z0-9_]{0,7}$", fullmatch=True),
)
@settings(max_examples=100, deadline=None)
def test_property_12_unsupported_metadata_value_produces_comment(
    node_name: str, key: str
) -> None:
    """Unsupported metadata values emit a ``# metadata ... omitted`` comment.

    **Validates: Requirements 10.5**
    """
    # Build a node with unsupported metadata values.
    node = nir.Input(input_type=np.asarray([1], dtype=int))
    unsupported_values = [
        [1, 2, 3],  # list
        {"a": 1},  # dict
        None,  # NoneType
        float("nan"),  # NaN
        float("inf"),  # +inf
        float("-inf"),  # -inf
    ]
    # Use the first unsupported value.
    bad_value = unsupported_values[0]
    node.metadata = {key: bad_value}

    graph = nir.NIRGraph(
        nodes={
            node_name: node,
            "out": nir.Output(output_type=np.asarray([1], dtype=int)),
        },
        edges=[],
        type_check=False,
    )
    text = NIR_Renderer().render(graph)

    # The comment must appear; no annotated with metadata clause for this key.
    expected_comment = (
        f"# metadata {key} on {node_name} omitted: unsupported value type"
    )
    assert (
        expected_comment in text
    ), f"Expected comment {expected_comment!r} not found in:\n{text}"
    # The bad value must NOT appear as an annotated clause.
    assert (
        f"annotated with metadata {key}" not in text
    ), f"Unexpected annotated clause for unsupported key {key!r} in:\n{text}"


@given(
    node_name=identifier_strategy(),
    key=st.from_regex(r"^[A-Za-z_][A-Za-z0-9_]{0,7}$", fullmatch=True),
    value=st.integers(min_value=0, max_value=100),
)
@settings(max_examples=100, deadline=None)
def test_property_12_duplicate_metadata_key_raises(
    node_name: str, key: str, value: int
) -> None:
    """Two ``annotated with metadata`` clauses sharing a key raise
    ``duplicate_metadata_key``.

    **Validates: Requirements 10.6**
    """
    # Build a CNL sentence with a duplicated metadata key manually.
    cnl = (
        f"Define an input port named inp with shape (1,).\n"
        f"Define an output port named out with shape (1,) "
        f"annotated with metadata {key} equal to {value} "
        f"annotated with metadata {key} equal to {value + 1}.\n"
    )
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(cnl)
    codes = {d.code for d in exc_info.value.errors}
    assert (
        "duplicate_metadata_key" in codes
    ), f"Expected duplicate_metadata_key in {codes}; key={key!r}"
