# neurocnl/tests/nir_native_cnl/test_nir_validation.py
"""Tests for NIR-native validation (layer1 and layer2)."""

from neurocnl.nir_cnl.ir_types import ArrayValues, NIREdgeRecord, NIRNodeRecord

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _lif(name: str, *, tau=0.02, r=1.0, v_leak=-0.07, v_threshold=-0.05) -> NIRNodeRecord:
    return NIRNodeRecord(
        name=name,
        primitive="LIF",
        params={"tau": tau, "r": r, "v_leak": v_leak, "v_threshold": v_threshold},
        metadata={},
        line=1,
    )


def _cubalif(name: str) -> NIRNodeRecord:
    return NIRNodeRecord(
        name=name,
        primitive="CubaLIF",
        params={
            "tau_syn": 0.005,
            "tau_mem": 0.02,
            "r": 1.0,
            "v_leak": -0.07,
            "v_threshold": -0.05,
        },
        metadata={},
        line=1,
    )


def _affine(name: str) -> NIRNodeRecord:
    w = ArrayValues(shape=(2, 2), values=(1.0, 0.0, 0.0, 1.0))
    b = ArrayValues(shape=(2,), values=(0.0, 0.0))
    return NIRNodeRecord(
        name=name,
        primitive="Affine",
        params={"weight": w, "bias": b},
        metadata={},
        line=1,
    )


def _input(name: str = "inp") -> NIRNodeRecord:
    return NIRNodeRecord(
        name=name, primitive="Input", params={"input_type": (2,)}, metadata={}, line=1
    )


def _output(name: str = "out") -> NIRNodeRecord:
    return NIRNodeRecord(
        name=name, primitive="Output", params={"output_type": (2,)}, metadata={}, line=1
    )


def _edge(src: str, target: str) -> NIREdgeRecord:
    return NIREdgeRecord(src=src, target=target, line=1)


# ---------------------------------------------------------------------------
# Layer 2: neuron detection
# ---------------------------------------------------------------------------

from neurocnl.layers.layer2_validator import validate_nir_records as l2_nir


def test_l2_finds_lif_as_neuron():
    lif = _lif("n1")
    records = [_input(), lif, _output(), _edge("inp", "n1"), _edge("n1", "out")]
    result = l2_nir(records)
    assert "n1" in result["neurons_found"]


def test_l2_finds_cubalif_as_neuron():
    cb = _cubalif("cb1")
    records = [_input(), cb, _output(), _edge("inp", "cb1"), _edge("cb1", "out")]
    result = l2_nir(records)
    assert "cb1" in result["neurons_found"]


def test_l2_affine_not_counted_as_neuron():
    aff = _affine("aff1")
    lif = _lif("n1")
    records = [
        _input(),
        lif,
        aff,
        _output(),
        _edge("inp", "n1"),
        _edge("n1", "aff1"),
        _edge("aff1", "out"),
    ]
    result = l2_nir(records)
    assert "n1" in result["neurons_found"]
    assert "aff1" not in result["neurons_found"]


def test_l2_empty_network_fails():
    result = l2_nir([])
    assert result["overall"] is False
    failed_names = [f["check"] for f in result["checks_failed"]]
    assert "empty_network" in failed_names


def test_l2_self_connection_flagged():
    lif = _lif("n1")
    records = [
        _input(),
        lif,
        _output(),
        _edge("inp", "n1"),
        _edge("n1", "n1"),
        _edge("n1", "out"),
    ]
    result = l2_nir(records)
    failed_names = [f["check"] for f in result["checks_failed"]]
    assert "self_referencing_connection" in failed_names


def test_l2_orphan_neuron_flagged():
    lif1 = _lif("n1")
    lif2 = _lif("n2")  # declared but no edges connect to it
    records = [_input(), lif1, lif2, _output(), _edge("inp", "n1"), _edge("n1", "out")]
    result = l2_nir(records)
    failed_names = [f["check"] for f in result["checks_failed"]]
    assert "orphan_population" in failed_names


# ---------------------------------------------------------------------------
# Layer 1: NIR physical invariants
# ---------------------------------------------------------------------------

from neurocnl.layers.layer1_validator import validate_nir_records as l1_nir


def test_l1_lif_valid_params_passes():
    result = l1_nir([_lif("n1")])
    assert result["overall"] is True


def test_l1_lif_zero_tau_fails():
    result = l1_nir([_lif("n1", tau=0.0)])
    assert result["overall"] is False
    assert any("nir_lif_time_constant_positive" in f["invariant"] for f in result["failed"])


def test_l1_lif_negative_tau_fails():
    result = l1_nir([_lif("n1", tau=-0.001)])
    assert result["overall"] is False


def test_l1_lif_zero_r_fails():
    result = l1_nir([_lif("n1", r=0.0)])
    assert result["overall"] is False
    assert any("nir_lif_resistance_positive" in f["invariant"] for f in result["failed"])


def test_l1_lif_threshold_below_leak_fails():
    result = l1_nir([_lif("n1", v_leak=-0.05, v_threshold=-0.07)])
    assert result["overall"] is False
    assert any("nir_lif_threshold_above_leak" in f["invariant"] for f in result["failed"])


def test_l1_cubalif_zero_tau_syn_fails():
    rec = NIRNodeRecord(
        name="cb",
        primitive="CubaLIF",
        params={
            "tau_syn": 0.0,
            "tau_mem": 0.02,
            "r": 1.0,
            "v_leak": -0.07,
            "v_threshold": -0.05,
        },
        metadata={},
        line=1,
    )
    result = l1_nir([rec])
    assert result["overall"] is False
    assert any(
        "nir_cubalif_synaptic_time_constant_positive" in f["invariant"] for f in result["failed"]
    )


def test_l1_cubalif_valid_passes():
    result = l1_nir([_cubalif("cb1")])
    assert result["overall"] is True


def test_l1_affine_all_zero_weight_warns():
    w = ArrayValues(shape=(2, 2), values=(0.0, 0.0, 0.0, 0.0))
    b = ArrayValues(shape=(2,), values=(0.0, 0.0))
    rec = NIRNodeRecord(
        name="aff",
        primitive="Affine",
        params={"weight": w, "bias": b},
        metadata={},
        line=1,
    )
    result = l1_nir([rec])
    assert any(warning.get("check") == "affine_weight_all_zero" for warning in result["warnings"])


def test_l1_ignores_non_neuron_records():
    inp = _input()
    edge = _edge("inp", "n1")
    result = l1_nir([inp, edge])
    # No neurons → nothing to fail, overall True (no failures)
    assert result["overall"] is True
