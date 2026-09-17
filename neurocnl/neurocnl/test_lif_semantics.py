"""Tests for the shared LIF discretization helper.

The parity tests against ``snntorch.import_nir`` are the important ones: they
pin this module to the upstream library a user reaches when they load an
exported ``.nir`` outside CNLStudio.
"""

from __future__ import annotations

import math
from typing import Any

import nir
import numpy as np
import pytest

from neurocnl.lif_semantics import (
    DEFAULT_LIF_DT_SECONDS,
    DiscretizationScheme,
    decay_from_tau,
    discretize_lif,
    resolve_dt,
    tau_seconds_from_decay,
    unreachable_threshold_warnings,
)


def _lif(
    tau: float = 0.02,
    *,
    size: int = 4,
    r: float = 1.0,
    v_leak: float = 0.0,
    v_threshold: float = 1.0,
    metadata: dict[str, Any] | None = None,
) -> nir.LIF:
    return nir.LIF(
        tau=np.full(size, tau),
        r=np.full(size, r),
        v_leak=np.full(size, v_leak),
        v_threshold=np.full(size, v_threshold),
        metadata=metadata or {},
    )


def _cubalif(
    tau_mem: float = 0.02, tau_syn: float = 0.01, size: int = 4
) -> nir.CubaLIF:
    return nir.CubaLIF(
        tau_mem=np.full(size, tau_mem),
        tau_syn=np.full(size, tau_syn),
        r=np.ones(size),
        v_leak=np.zeros(size),
        v_threshold=np.ones(size),
    )


# ---------------------------------------------------------------------------
# decay_from_tau / tau_seconds_from_decay
# ---------------------------------------------------------------------------


def test_euler_decay_matches_formula() -> None:
    assert decay_from_tau(0.02, 1e-4) == pytest.approx(1 - 1e-4 / 0.02)
    assert decay_from_tau(0.002, 1e-4) == pytest.approx(0.95)


def test_exact_scheme_available_but_distinct() -> None:
    euler = decay_from_tau(0.002, 1e-4)
    exact = decay_from_tau(0.002, 1e-4, DiscretizationScheme.EXACT)
    assert exact == pytest.approx(math.exp(-0.05))
    # Immaterial at the target regime, which is why EULER stays canonical.
    assert abs(exact - euler) < 2e-3


def test_euler_rejects_dt_at_or_above_tau() -> None:
    """The condition the old [0.01, 0.99] clamp was accidentally masking."""
    with pytest.raises(ValueError, match="unstable"):
        decay_from_tau(0.002, 1.0)
    with pytest.raises(ValueError, match="unstable"):
        decay_from_tau(0.002, 0.002)


def test_exact_scheme_tolerates_large_dt() -> None:
    """exp() never goes negative, so EXACT has no stability bound."""
    assert 0.0 < decay_from_tau(0.002, 1.0, DiscretizationScheme.EXACT) < 1.0


@pytest.mark.parametrize("bad", [0.0, -1.0, float("nan"), float("inf")])
def test_decay_rejects_bad_tau(bad: float) -> None:
    with pytest.raises(ValueError):
        decay_from_tau(bad, 1e-4)


def test_tau_round_trips_through_decay() -> None:
    for tau in (0.002, 0.02, 0.5):
        beta = decay_from_tau(tau, 1e-4)
        assert tau_seconds_from_decay(beta, 1e-4) == pytest.approx(tau)


@pytest.mark.parametrize("bad", [0.0, 1.0, -0.5, 1.5])
def test_tau_from_decay_rejects_out_of_range_beta(bad: float) -> None:
    with pytest.raises(ValueError):
        tau_seconds_from_decay(bad, 1e-4)


# ---------------------------------------------------------------------------
# resolve_dt precedence
# ---------------------------------------------------------------------------


def test_resolve_dt_defaults_when_nothing_declared() -> None:
    assert resolve_dt(_lif()) == (DEFAULT_LIF_DT_SECONDS, "default")


def test_resolve_dt_prefers_graph_over_default() -> None:
    graph = nir.NIRGraph(nodes={}, edges=[], metadata={"dt": 0.001})
    assert resolve_dt(_lif(), graph) == (0.001, "graph")


def test_resolve_dt_prefers_node_over_graph() -> None:
    graph = nir.NIRGraph(nodes={}, edges=[], metadata={"dt": 0.001})
    node = _lif(metadata={"dt": 0.0005})
    assert resolve_dt(node, graph) == (0.0005, "node")


@pytest.mark.parametrize("bad", [0.0, -1.0, "soon", None])
def test_resolve_dt_ignores_unusable_metadata(bad: object) -> None:
    assert resolve_dt(_lif(metadata={"dt": bad})) == (DEFAULT_LIF_DT_SECONDS, "default")


# ---------------------------------------------------------------------------
# discretize_lif
# ---------------------------------------------------------------------------


def test_discretize_lif_reproduces_training_values() -> None:
    """The exact numbers behind the mnist-latest2 workspace."""
    d = discretize_lif(_lif(0.002))
    assert d.beta == pytest.approx(0.95)
    assert d.input_scale == pytest.approx(0.05)
    assert d.threshold == pytest.approx(20.0)
    assert d.tau_steps == pytest.approx(20.0)

    d2 = discretize_lif(_lif(0.02))
    assert d2.beta == pytest.approx(0.995)
    assert d2.threshold == pytest.approx(200.0)


def test_discretize_lif_threshold_untouched_when_scale_is_unity() -> None:
    """r*dt/tau == 1 is reachable via resistance, not by driving dt up to tau."""
    d = discretize_lif(_lif(0.001, r=10.0, v_threshold=0.3))
    assert d.input_scale == pytest.approx(1.0)
    assert d.threshold == pytest.approx(0.3)


def test_discretize_lif_folds_resistance_into_input_scale() -> None:
    d = discretize_lif(_lif(0.002, r=2.0))
    assert d.input_scale == pytest.approx(2.0 * 1e-4 / 0.002)
    assert d.threshold == pytest.approx(1.0 / d.input_scale)
    # Resistance must not leak into the decay.
    assert d.beta == pytest.approx(0.95)


def test_discretize_cubalif_uses_tau_mem_and_tau_syn() -> None:
    """Regression: reading .tau off a CubaLIF used to yield a hardcoded 0.9."""
    d = discretize_lif(_cubalif(tau_mem=0.02, tau_syn=0.01))
    assert d.tau_seconds == pytest.approx(0.02)
    assert d.beta == pytest.approx(1 - 1e-4 / 0.02)
    assert d.alpha == pytest.approx(1 - 1e-4 / 0.01)
    assert d.beta != pytest.approx(0.9)


def test_discretize_plain_lif_has_no_synaptic_decay() -> None:
    assert discretize_lif(_lif()).alpha is None


def test_discretize_lif_honours_explicit_dt() -> None:
    d = discretize_lif(_lif(0.02), dt=0.001)
    assert d.dt_seconds == pytest.approx(0.001)
    assert d.dt_source == "explicit"
    assert d.beta == pytest.approx(0.95)


def test_discretize_lif_records_dt_provenance() -> None:
    graph = nir.NIRGraph(nodes={}, edges=[], metadata={"dt": 0.001})
    assert discretize_lif(_lif(), graph=graph).dt_source == "graph"
    assert discretize_lif(_lif()).dt_source == "default"


def test_discretize_lif_warns_on_nonzero_leak() -> None:
    d = discretize_lif(_lif(0.02, v_leak=0.3))
    assert any("Leak voltage" in w for w in d.warnings)


def test_discretize_lif_warns_on_heterogeneous_tau() -> None:
    node = nir.LIF(
        tau=np.array([0.02, 0.002, 0.02, 0.02]),
        r=np.ones(4),
        v_leak=np.zeros(4),
        v_threshold=np.ones(4),
    )
    d = discretize_lif(node)
    assert any("differ" in w for w in d.warnings)


def test_discretize_lif_warns_when_dt_is_large_relative_to_tau() -> None:
    d = discretize_lif(_lif(0.002), dt=0.001)
    assert any("large relative to tau" in w for w in d.warnings)


def test_discretize_lif_clean_node_has_no_warnings() -> None:
    assert discretize_lif(_lif(0.02)).warnings == ()


def test_discretize_lif_rejects_unstable_timestep() -> None:
    with pytest.raises(ValueError, match="unstable"):
        discretize_lif(_lif(0.002), dt=0.01)


def test_discretize_lif_rejects_non_positive_tau() -> None:
    with pytest.raises(ValueError, match="time constant"):
        discretize_lif(_lif(0.0))


def test_discretize_lif_rejects_other_node_types() -> None:
    with pytest.raises(TypeError):
        discretize_lif(nir.Linear(weight=np.eye(3)))


# ---------------------------------------------------------------------------
# Parity with upstream snntorch.import_nir
# ---------------------------------------------------------------------------


def test_matches_snntorch_import_nir_formula() -> None:
    """Pin to the library a user reaches with an exported .nir outside the app.

    Recomputes upstream's ``_nir_to_snntorch_module`` LIF branch inline rather
    than importing it, so the test states the contract in full and does not
    depend on snntorch being installed.
    """
    for tau, r, thr in ((0.0025, 1.0, 0.1), (0.02, 1.0, 1.0), (0.001, 2.0, 0.5)):
        dt = 1e-4
        upstream_beta = 1 - (dt / tau)
        upstream_w_scale = r * dt / tau
        upstream_vthr = (
            thr / upstream_w_scale if not np.isclose(upstream_w_scale, 1.0) else thr
        )

        d = discretize_lif(_lif(tau, r=r, v_threshold=thr))

        assert d.beta == pytest.approx(upstream_beta)
        assert d.input_scale == pytest.approx(upstream_w_scale)
        assert d.threshold == pytest.approx(upstream_vthr)


def test_default_dt_matches_upstream_hardcode() -> None:
    assert DEFAULT_LIF_DT_SECONDS == 1e-4


# ---------------------------------------------------------------------------
# unreachable_threshold_warnings
# ---------------------------------------------------------------------------


def _graph_with(
    node: nir.NIRNode, metadata: dict[str, Any] | None = None
) -> nir.NIRGraph:
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([4])}),
            "pop": node,
            "output": nir.Output(output_type={"output": np.array([4])}),
        },
        edges=[("input", "pop"), ("pop", "output")],
        metadata=metadata or {},
    )


def test_unreachable_threshold_flags_the_undeclared_timestep_case() -> None:
    """tau 0.02 s + threshold 1.0 + no declared timestep = effective 200."""
    messages = unreachable_threshold_warnings(_graph_with(_lif(0.02)))
    assert len(messages) == 1
    assert "'pop'" in messages[0]
    assert "200.0" in messages[0]
    assert "0.002" in messages[0]  # suggested timestep = tau/10


def test_unreachable_threshold_silent_on_a_well_scaled_network() -> None:
    graph = _graph_with(_lif(0.02), metadata={"dt": 0.002})
    assert unreachable_threshold_warnings(graph) == []


def test_unreachable_threshold_never_raises_on_an_unusable_node() -> None:
    """A node the backends will reject must not crash the advisory pass."""
    assert unreachable_threshold_warnings(_graph_with(_lif(0.0))) == []


def test_unreachable_threshold_ignores_non_lif_nodes() -> None:
    graph = nir.NIRGraph(
        nodes={"fc": nir.Linear(weight=np.eye(3))}, edges=[], type_check=False
    )
    assert unreachable_threshold_warnings(graph) == []
