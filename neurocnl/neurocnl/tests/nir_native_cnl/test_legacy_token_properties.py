"""Property tests for legacy-token rejection and non-emission.

Two properties from the design's correctness-property catalogue:

* **Property 2** — Renderer never emits legacy-grammar tokens. For any
  random :class:`nir.NIRGraph` over the 18 Primitives, the rendered
  text passes :func:`scan_for_legacy_tokens` with an empty diagnostic
  list (Requirements 3.8, 8.1, 8.2, 8.5).
* **Property 3** — Parser rejects every legacy-grammar input. For any
  CNL text obtained by splicing a Biological_Grammar keyword or a
  Structured_DSL_Token into otherwise-valid prose,
  :class:`NIR_CNL_Parser` raises :class:`ParseError` carrying at least
  one diagnostic whose ``code`` is ``"structured_dsl_token"`` or
  ``"legacy_grammar"`` (Requirements 1.8, 8.3, 8.4).

Both tests run 100 Hypothesis examples per
``@settings(max_examples=100)``.
"""

from __future__ import annotations

import nir
import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from neurocnl.compile import CompileError, compile_to_nir
from neurocnl.nir_cnl import NIR_CNL_Parser
from neurocnl.nir_cnl.errors import ParseError
from neurocnl.nir_cnl.grammar_tables import forbidden_biological_keywords
from neurocnl.nir_cnl.pipeline_config import PipelineConfig
from neurocnl.nir_cnl.renderer import NIR_Renderer
from neurocnl.nir_cnl.validator import scan_for_legacy_tokens

from ._strategies import nir_graph_strategy, pipeline_config_strategy

# ---------------------------------------------------------------------------
# Property 2: Renderer never emits legacy tokens
# ---------------------------------------------------------------------------


# Feature: nir-native-cnl, Property 2: Renderer never emits legacy-grammar tokens
@given(graph=nir_graph_strategy())
@settings(max_examples=100, deadline=None)
def test_property_2_renderer_never_emits_legacy_tokens(graph: nir.NIRGraph) -> None:
    """The renderer's output must contain no Biological_Grammar
    keywords (outside double-quoted strings) and no Structured_DSL_Tokens.

    **Validates: Requirements 3.8, 8.1, 8.2, 8.5**
    """
    text = NIR_Renderer().render(graph)
    diagnostics = scan_for_legacy_tokens(text)
    assert (
        diagnostics == []
    ), f"Renderer emitted legacy tokens: {[d.code for d in diagnostics]}\ntext:\n{text}"


# Feature: pipeline-cnl, Property 2 (pipeline variant): render_pipeline_config
# never emits legacy-grammar tokens either.
@given(cfg=pipeline_config_strategy())
@settings(max_examples=100, deadline=None)
def test_property_2_pipeline_renderer_never_emits_legacy_tokens(
    cfg: PipelineConfig,
) -> None:
    text = NIR_Renderer().render_pipeline_config(cfg)
    diagnostics = scan_for_legacy_tokens(text)
    assert (
        diagnostics == []
    ), f"render_pipeline_config emitted legacy tokens: {[d.code for d in diagnostics]}\ntext:\n{text}"


def test_pipeline_keywords_do_not_collide_with_forbidden_biological_keywords() -> None:
    """None of the new Train/Evaluate/Export grammar keywords or
    closed-vocabulary phrase words may overlap with the
    Biological_Grammar denylist — a collision would make the legacy-
    token gate misfire on ordinary pipeline CNL text."""
    pipeline_words = {
        "train",
        "evaluate",
        "export",
        "epochs",
        "optimizer",
        "training",
        "strategy",
        "loss",
        "metrics",
        "trained",
        "script",
        "adam",
        "sgd",
        "adamw",
        "rmsprop",
        "surrogate",
        "gradient",
        "bptt",
        "rate",
        "coding",
        "mse",
        "count",
        "cross",
        "entropy",
        "membrane",
        "potential",
        "nir",
    }
    forbidden_lower = {k.lower() for k in forbidden_biological_keywords}
    assert not (pipeline_words & forbidden_lower)


# ---------------------------------------------------------------------------
# Property 3: Parser rejects every legacy-grammar input
# ---------------------------------------------------------------------------


# Strategy of biological-grammar tokens.
_BIO_TOKENS: tuple[str, ...] = (
    "sensory",
    "motor",
    "MUST",
    "threshold_firing",
    "refractory_period",
    "STDP",
)


# Synthesised structured-DSL token snippets. We assemble these from
# pieces so the test source itself does not contain literal
# Structured_DSL_Token forms (which would trip the static-scan
# invariant test that covers this same directory).
def _quoted_id_arrow_quoted_id() -> str:
    return '"' + "in" + '"' + " -> " + '"' + "out" + '"'


def _primitive_quoted_id() -> str:
    return "LIF" + ' "' + "lif1" + '"'


_STRUCT_TOKENS: tuple[str, ...] = (
    _quoted_id_arrow_quoted_id(),
    _primitive_quoted_id(),
)


_BASE_PROSE: str = (
    "Define a network named demo.\n"
    "Define an input port named in1 with shape (1,).\n"
    "Define an output port named out1 with shape (1,).\n"
    "Connect in1 to out1.\n"
)


def _splice(prose: str, token: str, position: int) -> str:
    """Splice *token* into *prose* on a new line at *position*."""
    lines = prose.splitlines(keepends=True)
    if not lines:
        return token + "\n"
    pos = position % (len(lines) + 1)
    return "".join(lines[:pos]) + token + "\n" + "".join(lines[pos:])


# Feature: nir-native-cnl, Property 3: Parser rejects every legacy-grammar input
@given(
    token=st.sampled_from(_BIO_TOKENS + _STRUCT_TOKENS),
    position=st.integers(min_value=0, max_value=10),
)
@settings(max_examples=100, deadline=None)
def test_property_3_parser_rejects_legacy_inputs(token: str, position: int) -> None:
    """``NIR_CNL_Parser`` must raise :class:`ParseError` carrying at
    least one ``structured_dsl_token`` or ``legacy_grammar`` diagnostic
    when the input contains a Biological_Grammar keyword or a
    Structured_DSL_Token.

    ``compile_to_nir`` must likewise raise :class:`CompileError` whose
    diagnostics include ``code="legacy_grammar"`` (the unified entry
    point routes legacy-shape inputs through the same validator —
    Requirement 8.4).

    **Validates: Requirements 1.8, 8.3, 8.4**
    """
    spliced = _splice(_BASE_PROSE, token, position)

    # Parser path.
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(spliced)
    codes = {d.code for d in exc_info.value.errors}
    assert codes & {
        "structured_dsl_token",
        "legacy_grammar",
    }, f"ParseError diagnostics did not flag the legacy input. Codes: {codes}; token={token!r}"

    # compile_to_nir path. The unified entry point must also reject
    # the input with code='legacy_grammar' per Requirement 8.4.
    with pytest.raises(CompileError) as exc_info_compile:
        compile_to_nir(spliced)
    compile_codes = {d.code for d in exc_info_compile.value.diagnostics}
    assert "legacy_grammar" in compile_codes, (
        f"compile_to_nir did not raise legacy_grammar diagnostic; "
        f"got codes={compile_codes}; token={token!r}"
    )
