"""End-to-end proof that a CNL-declared network timestep reaches
snnTorch codegen's ``nir.LIF`` beta/threshold conversion.

Goes through the real, full pipeline (``compile_to_nir`` ->
``_generate_snntorch_code``), not hand-built ``nir.NIRGraph`` objects,
to prove the ``nir_cnl`` grammar addition actually wires into the
existing codegen hook end to end. The expected numbers are not new
arithmetic to trust — they're the same tau/r/threshold combination
already pinned by ``test_lif_codegen_matches_oracle_formula`` (baseline,
no metadata) and ``test_lif_codegen_dt_metadata_override`` (dt=0.001)
in ``test_notebook_codegen.py``.

_Validates: nir_cnl network-timestep grammar extension reaches
backend.app.routers.notebook's snnTorch codegen unchanged_
"""

from __future__ import annotations

from backend.app.routers.notebook import (
    PipelineConfigPayload,
    PipelinePhasesPayload,
    _build_v2_notebook,
    _generate_snntorch_code,
)
from neurocnl.compile import compile_to_nir

_SPEC = "\n".join(
    [
        "Define a network named demo{network_clause}.",
        "Define an input port named in1 with shape (1,).",
        "Define a LIF neuron named n1 with time constant 0.0025, resistance 1.0,"
        " leak voltage 0.0, and firing threshold 0.1.",
        "Define an output port named out1 with shape (1,).",
        "in1 connects to n1.",
        "n1 connects to out1.",
    ]
)


def test_undeclared_network_timestep_matches_pre_existing_1e4_default() -> None:
    """No declared timestep -> byte-identical to the pinned pre-fix default."""
    code, _ = _generate_snntorch_code(compile_to_nir(_SPEC.format(network_clause="")))
    assert "beta=0.960000, threshold=2.5000" in code


def test_declared_network_timestep_changes_beta_and_threshold() -> None:
    """Declaring timestep=0.001 must reach node.metadata['dt'] and change
    the emitted beta/threshold exactly as test_lif_codegen_dt_metadata_override
    pins for the same tau/r/threshold with dt=0.001."""
    code, _ = _generate_snntorch_code(
        compile_to_nir(_SPEC.format(network_clause=" with timestep 0.001"))
    )
    assert "beta=0.600000, threshold=0.2500" in code


def test_explicit_node_dt_override_wins_over_declared_network_timestep() -> None:
    spec = _SPEC.format(network_clause=" with timestep 0.001").replace(
        "and firing threshold 0.1.",
        "and firing threshold 0.1, annotated with metadata dt equal to 0.0005.",
    )
    code, _ = _generate_snntorch_code(compile_to_nir(spec))
    # dt=0.0005 (not 0.001): beta = 1 - 0.0005/0.0025 = 0.8, w_scale = 0.2,
    # threshold = 0.1 / 0.2 = 0.5.
    assert "beta=0.800000, threshold=0.5000" in code


# ---------------------------------------------------------------------------
# Guardrail warning cell
# ---------------------------------------------------------------------------

_WARNING_SPEC = "\n".join(
    [
        "Define a network named demo{network_clause}.",
        "Define an input port named in1 with shape (1,).",
        "Define a LIF neuron named n1 with time constant 0.02, resistance 1.0,"
        " leak voltage 0.0, and firing threshold 1.0.",
        "Define an output port named out1 with shape (1,).",
        "in1 connects to n1.",
        "n1 connects to out1.",
    ]
)


def _build_nb(network_clause: str):
    graph = compile_to_nir(_WARNING_SPEC.format(network_clause=network_clause))
    cfg = PipelineConfigPayload(framework="snntorch_sim")
    nb, _ = _build_v2_notebook(
        _WARNING_SPEC.format(network_clause=network_clause),
        graph,
        cfg,
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    return " ".join("".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown")


def test_warning_cell_appears_for_undeclared_default_unreachable_threshold() -> None:
    """tau=0.02, threshold=1.0, no declared timestep -> default dt=1e-4 gives
    threshold_out=200, comfortably over the 50 cutoff."""
    md_src = _build_nb(network_clause="")
    assert "Possibly unreachable firing threshold" in md_src


def test_warning_cell_absent_once_sane_timestep_declared() -> None:
    """timestep=0.005 -> w_scale=0.25, threshold_out=4.0, well under cutoff."""
    md_src = _build_nb(network_clause=" with timestep 0.005")
    assert "Possibly unreachable firing threshold" not in md_src
