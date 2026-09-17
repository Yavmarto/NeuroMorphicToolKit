"""Tests for ``backend.app.services.notebook_target_codegen`` (the snnTorch /
target code emitter). Exercises ``_generate_snntorch_code`` and its supporting
NIR graph fixtures, which are re-exported from ``backend.app.routers.notebook``.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

import nir
import numpy as np
import pytest

from backend.app.routers.notebook import (
    DagNodePayload,
    PhaseDAGPayload,
    PipelineConfigPayload,
    PipelinePhasesPayload,
    _build_v2_notebook,
    _generate_snntorch_code,
)
from backend.tests.notebook_test_fixtures import (
    VALID_SPEC,
    _braille_nir_graph,
    _cell_after_md,
    _code_sources,
)
from neurocnl._nir_compat import make_nir_graph
from neurocnl.runtime.cnl_nodes import BatchNorm1d as CnlBatchNorm1d
from neurocnl.runtime.cnl_nodes import Dropout as CnlDropout
from neurocnl.runtime.cnl_nodes import Leaky as CnlLeaky
from neurocnl.runtime.cnl_nodes import RLeaky as CnlRLeaky


def test_time_major_lif_batch_is_ce_count_loss_compatible(
    tmp_path, monkeypatch
) -> None:
    """A tonic-shaped (T,B,N) batch must reach snnTorch losses unchanged."""
    torch = pytest.importorskip("torch")
    SF = pytest.importorskip("snntorch.functional")

    code, weights = _generate_snntorch_code(
        _lif_norse_graph(), weights_filename="weights.npz", time_major_input=True
    )
    np.savez(tmp_path / "weights.npz", **weights)
    monkeypatch.chdir(tmp_path)
    namespace: dict[str, object] = {}
    exec(compile(code, "<generated-time-major-net>", "exec"), namespace)

    net = namespace["net"]
    spikes, _ = net(torch.zeros(5, 2, 1, dtype=torch.float32))
    assert spikes.shape == (5, 2, 1)

    loss = SF.ce_count_loss()(spikes, torch.zeros(2, dtype=torch.long))
    assert loss.shape == ()
    assert loss.requires_grad
    loss.backward()


def test_rsynaptic_codegen_init() -> None:
    code, _ = _generate_snntorch_code(_braille_nir_graph())
    assert "snn.RSynaptic(" in code
    assert "snn.Synaptic(" in code


def test_rsynaptic_codegen_reset_delay() -> None:
    """Regression: snn.RSynaptic/snn.Synaptic default reset_delay=True, but
    both Braille reference notebooks (Braille_training_snntorch.ipynb,
    snntorch_apply_subtract.ipynb) hardcode reset_delay=False locally, and
    snntorch.import_nir._nir_to_snntorch_module's nir.NIRGraph/CubaLIF-in-
    subgraph branch also hardcodes reset_delay=False. Leaving it unset
    diverges from the weights' training-time convention.
    """
    code, _ = _generate_snntorch_code(_braille_nir_graph())
    assert "snn.RSynaptic(" in code
    assert "snn.Synaptic(" in code
    assert code.count("reset_delay=False") == 2


def test_rsynaptic_codegen_threshold_passthrough() -> None:
    """Regression: the CnlRSynaptic/CnlSynaptic dataclasses carry a threshold
    field that nir_graph_serializer.py round-trips, but codegen previously
    never emitted it — silently dropping any non-default threshold a user set
    in the canvas property panel."""
    code, _ = _generate_snntorch_code(_braille_nir_graph())
    assert "threshold=2.0000" in code
    assert code.count("threshold=2.0000") == 2


def test_rsynaptic_synaptic_codegen_spike_grad_passthrough() -> None:
    """Regression: `spike_grad_expr` (sourced from a pipeline DAG's
    `surrogateBackward` node) must reach both `snn.RSynaptic(` and
    `snn.Synaptic(` constructors, not just `nir.LIF`/`snn.Leaky`. Without
    this, a network built from RSynaptic/Synaptic populations trains with the
    library-default surrogate gradient regardless of the user's chosen
    `surrogateBackward` function/slope — or, if the neuron layer somehow ends
    up disconnected from autograd, reproduces the
    "does not require grad and does not have a grad_fn" backward() error."""
    code, _ = _generate_snntorch_code(
        _braille_nir_graph(), spike_grad_expr="surrogate.fast_sigmoid(slope=5.0)"
    )
    assert "spike_grad = surrogate.fast_sigmoid(slope=5.0)" in code
    for line in code.splitlines():
        if "snn.RSynaptic(" in line or "snn.Synaptic(" in line:
            assert "spike_grad=spike_grad" in line


def test_rsynaptic_synaptic_survives_cnl_render_reparse_round_trip() -> None:
    """End-to-end regression for the actual bug: a canvas-built graph must
    keep its RSynaptic/Synaptic neurons (and every edge touching them) after
    going through the same render(graph)->CNL text->compile_to_nir(text)
    round trip the notebook-generation backend performs to make a generated
    notebook a portable, standalone artifact (embedding `cnl_spec` +
    `compile_to_nir(cnl_spec)` rather than depending on the app's canvas
    JSON). Before this fix, the renderer had no grammar entry for these
    types, silently commented them (and their edges) out as
    "# unsupported node type ...", and `compile_to_nir` rebuilt a
    disconnected 2-node graph — codegen then produced a `forward()` that
    never called any layer, training against a tensor with no `grad_fn`."""
    from neurocnl.compile import compile_to_nir
    from neurocnl.nir_cnl.renderer import NIR_Renderer

    graph_in = _braille_nir_graph()
    cnl_text = NIR_Renderer().render(graph_in)
    assert "unsupported" not in cnl_text, cnl_text

    graph_out = compile_to_nir(cnl_text)
    assert len(graph_out.nodes) == len(graph_in.nodes)
    assert len(graph_out.edges) == len(graph_in.edges)
    assert type(graph_out.nodes["rsyn"]).__name__ == "RSynaptic"
    assert type(graph_out.nodes["syn"]).__name__ == "Synaptic"

    code, _ = _generate_snntorch_code(
        graph_out, spike_grad_expr="surrogate.fast_sigmoid(slope=5.0)"
    )
    assert "snn.RSynaptic(" in code
    assert "snn.Synaptic(" in code
    # The forward() must actually call the layers it defines in __init__ —
    # this is what a disconnected/broken graph fails to do (it falls back
    # to a bare passthrough of the raw input).
    assert "self.rsyn(" in code or "rsyn(" in code
    assert "self.syn(" in code or "syn(" in code


def test_rsynaptic_synaptic_generated_net_forward_runs(tmp_path, monkeypatch) -> None:
    """The generated Net must instantiate and run a forward pass without error
    for the RSynaptic/Synaptic temporal-loop path (execution-level regression
    for the reset_delay/threshold wiring, not just a string match)."""
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")

    code, weights = _generate_snntorch_code(_braille_nir_graph())
    np.savez(tmp_path / "weights.npz", **weights)
    monkeypatch.chdir(tmp_path)

    ns: dict[str, object] = {}
    exec(compile(code, "<generated_net>", "exec"), ns)

    net = ns["net"]
    # (B=2, T=5, in=12) — forward() does x.swapaxes(0, 1) to get (T, B, in).
    x = torch.zeros(2, 5, 12, dtype=torch.float32)
    spk_out, hid_rec = net(x)
    assert spk_out.shape == (5, 2, 7)  # (T, B, out)
    assert hid_rec.shape[0] == 5  # hidden layer time dimension preserved


def test_rsynaptic_codegen_forward_temporal() -> None:
    code, _ = _generate_snntorch_code(_braille_nir_graph())
    # NOT self.rsyn.init_rsynaptic(): that returns an empty (0,)-shaped
    # placeholder, which crashes snn.RSynaptic.forward's reset_delay=False
    # branch (it uses the raw spk *parameter*, not self.spk) on the very
    # first call. Codegen must pre-shape (batch, n_neurons) zeros instead —
    # see the rsynaptic branch of mem_init_lines in notebook.py.
    assert "init_rsynaptic()" not in code
    assert "spk_rsyn = torch.zeros(x.shape[1], 16" in code
    assert "init_synaptic()" in code
    assert "for t in range(x.shape[0])" in code
    assert "swapaxes(0, 1)" in code
    # Hidden spikes tracked separately for L1/L2 reg (RSynaptic is hidden, Synaptic is output)
    assert "hid_rec" in code
    assert "spk_rec" in code
    # RSynaptic (hidden) appends to hid_rec; Synaptic (→ nir.Output) appends to spk_rec
    assert "hid_rec.append" in code
    assert "spk_rec.append" in code


def test_snntorch_codegen_uses_custom_weights_filename() -> None:
    """weights_filename must be threaded into the np.load(...) call, not
    hardcoded to 'weights.npz' — see the per-target/per-spec artifact fix."""
    code, _ = _generate_snntorch_code(
        _rleaky_graph(), weights_filename="weights_snntorch_sim_deadbeef.npz"
    )
    assert "np.load('weights_snntorch_sim_deadbeef.npz')" in code
    assert "np.load('weights.npz')" not in code


def test_snntorch_codegen_raises_actionable_error_on_mismatched_weights_file(
    tmp_path, monkeypatch
) -> None:
    """Regression: loading a weights file that does not match the current
    architecture must raise a clear, actionable RuntimeError instead of a
    bare KeyError deep inside model construction (see the KeyError bug
    report this fixes: 'n_0_weight' missing from a stale weights.npz).
    """
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")

    code, weights = _generate_snntorch_code(_rleaky_graph())
    assert weights, "fixture must produce at least one weight key to exercise the check"
    # Simulate a stale/mismatched weights file: save under different key names.
    mismatched = {f"stale_{k}": v for k, v in weights.items()}
    np.savez(tmp_path / "weights.npz", **mismatched)
    monkeypatch.chdir(tmp_path)

    ns: dict[str, object] = {}
    with pytest.raises(RuntimeError, match="(?i)regenerate the notebook"):
        exec(compile(code, "<generated_net>", "exec"), ns)


def _rleaky_graph() -> nir.NIRGraph:
    """Input → Linear → RLeaky → Output."""
    return make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([8])}),
            "fc": nir.Linear(weight=np.zeros((8, 8), dtype=np.float32)),
            "rl": CnlRLeaky(n_neurons=8, beta=0.9),
            "output": nir.Output(output_type={"output": np.array([8])}),
        },
        edges=[("input", "fc"), ("fc", "rl"), ("rl", "output")],
    )


def test_rleaky_codegen_init() -> None:
    code, _ = _generate_snntorch_code(_rleaky_graph())
    assert "snn.RLeaky(" in code
    assert "linear_features=8" in code


def test_rleaky_codegen_forward_temporal() -> None:
    code, _ = _generate_snntorch_code(_rleaky_graph())
    assert "init_rleaky()" in code
    assert "for t in range(x.shape[0])" in code
    assert "spk_rec.append" in code


def test_leaky_explicit_codegen() -> None:
    graph = make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([4])}),
            "fc": nir.Linear(weight=np.zeros((4, 4), dtype=np.float32)),
            "lk": CnlLeaky(n_neurons=4, beta=0.85),
            "output": nir.Output(output_type={"output": np.array([4])}),
        },
        edges=[("input", "fc"), ("fc", "lk"), ("lk", "output")],
    )
    code, _ = _generate_snntorch_code(graph)
    assert "snn.Leaky(" in code
    assert "init_hidden=False" in code
    assert "init_leaky()" in code
    assert "for t in range(x.shape[0])" in code  # explicit state → temporal loop


def test_batchnorm1d_codegen() -> None:
    graph = make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([8])}),
            "fc": nir.Linear(weight=np.zeros((8, 8), dtype=np.float32)),
            "bn": CnlBatchNorm1d(num_features=8),
            "lif": nir.LIF(
                tau=np.array([0.02]),
                r=np.array([1.0]),
                v_leak=np.array([0.0]),
                v_threshold=np.array([1.0]),
            ),
            "output": nir.Output(output_type={"output": np.array([8])}),
        },
        edges=[("input", "fc"), ("fc", "bn"), ("bn", "lif"), ("lif", "output")],
    )
    code, _ = _generate_snntorch_code(graph)
    assert "nn.BatchNorm1d(8)" in code
    # BatchNorm is stateless — no state init line
    assert "init_batchnorm" not in code


def test_dropout_codegen() -> None:
    graph = make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([8])}),
            "fc": nir.Linear(weight=np.zeros((8, 8), dtype=np.float32)),
            "drop": CnlDropout(p=0.3),
            "lif": nir.LIF(
                tau=np.array([0.02]),
                r=np.array([1.0]),
                v_leak=np.array([0.0]),
                v_threshold=np.array([1.0]),
            ),
            "output": nir.Output(output_type={"output": np.array([8])}),
        },
        edges=[("input", "fc"), ("fc", "drop"), ("drop", "lif"), ("lif", "output")],
    )
    code, _ = _generate_snntorch_code(graph)
    assert "nn.Dropout(p=0.3)" in code


def _conv_if_nir_graph() -> nir.NIRGraph:
    """NMNIST-like CNN using nir.IF (integrate-and-fire) neurons.

    Mirrors paper/02_cnn/snntorch_apply.ipynb structure:
    Input -> Conv2d -> IF -> Flatten -> Linear -> IF -> Output.
    Numeric node names render as n_0, n_1, ... via _python_identifier.
    """
    conv_w = np.zeros((4, 2, 3, 3), dtype=np.float32)
    lin_w = np.zeros((3, 144), dtype=np.float32)  # 4 * 6 * 6 = 144
    return make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2, 6, 6])}),
            "0": nir.Conv2d(
                input_shape=(6, 6),
                weight=conv_w,
                stride=np.array([1, 1]),
                padding=np.array([1, 1]),
                dilation=np.array([1, 1]),
                groups=1,
                bias=np.zeros(4, dtype=np.float32),
            ),
            "1": nir.IF(
                r=np.ones(4, dtype=np.float32),
                v_threshold=np.ones(4, dtype=np.float32),
            ),
            "2": nir.Flatten(
                input_type={"input": np.array([4, 6, 6])},
                start_dim=1,
                end_dim=-1,
            ),
            "3": nir.Linear(weight=lin_w),
            "4": nir.IF(
                r=np.ones(3, dtype=np.float32),
                v_threshold=np.ones(3, dtype=np.float32),
            ),
            "output": nir.Output(output_type={"output": np.array([3])}),
        },
        edges=[
            ("input", "0"),
            ("0", "1"),
            ("1", "2"),
            ("2", "3"),
            ("3", "4"),
            ("4", "output"),
        ],
    )


def test_if_neuron_forward_uses_init_hidden_call() -> None:
    """Regression: nir.IF neurons must use the init_hidden=True single-return
    call form in forward(). The previous ``spk, mem = self.n(x, mem)`` form
    referenced an uninitialised local and raised UnboundLocalError at runtime.
    """
    code, _ = _generate_snntorch_code(_conv_if_nir_graph())
    # IF mirrors snntorch.import_nir: Leaky(beta=0.9, reset_delay=False).
    assert (
        "self.n_1 = snn.Leaky(beta=0.900000, threshold=1.0000, "
        "init_hidden=True, reset_delay=False)" in code
    )
    # Forward must call IF with a single return and no explicit membrane arg.
    assert "spk_n_1 = self.n_1(x)" in code
    assert "spk_n_4 = self.n_4(x)" in code
    # The broken explicit-membrane form must be gone.
    assert "mem_n_1" not in code
    assert "self.n_1(x, mem_n_1)" not in code


def test_if_neuron_generated_net_forward_runs(tmp_path, monkeypatch) -> None:
    """The generated Net must instantiate and run a forward pass without raising
    UnboundLocalError for a Conv2d -> IF network (executes the emitted code).
    """
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")

    code, weights = _generate_snntorch_code(_conv_if_nir_graph(), time_major_input=True)
    np.savez(tmp_path / "weights.npz", **weights)
    monkeypatch.chdir(tmp_path)

    ns: dict[str, object] = {}
    exec(compile(code, "<generated_net>", "exec"), ns)

    net = ns["net"]
    # (T, B, C, H, W) time-first frames, as produced by tonic ToFrame.
    x = torch.zeros(3, 2, 2, 6, 6, dtype=torch.float32)
    spk_out, _mem_out = net(x)
    assert spk_out.shape[0] == 3  # time dimension preserved
    assert spk_out.shape[1] == 2  # batch preserved
    assert spk_out.shape[2] == 3  # output neurons


def _lif_norse_graph() -> nir.NIRGraph:
    """Mirrors paper/01_lif/lif_norse.nir: Input -> Affine -> LIF -> Output,
    using that file's real values (tau=0.0025, r=1.0, v_leak=0.0,
    v_threshold=0.1)."""
    return make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([1])}),
            "0": nir.Affine(
                weight=np.array([[1.0]], dtype=np.float32),
                bias=np.array([0.0], dtype=np.float32),
            ),
            "1": nir.LIF(
                tau=np.array([0.0025]),
                r=np.array([1.0]),
                v_leak=np.array([0.0]),
                v_threshold=np.array([0.1]),
            ),
            "output": nir.Output(output_type={"output": np.array([1])}),
        },
        edges=[("input", "0"), ("0", "1"), ("1", "output")],
    )


def test_lif_codegen_matches_oracle_formula() -> None:
    """Regression: nir.LIF must match snntorch.import_nir._nir_to_snntorch_module's
    nir.LIF branch exactly — a local dt=1e-4 (not the module's dt=1e-3),
    beta=1-dt/tau, reset_mechanism="zero", reset_delay=False, and the
    hack_w_scale threshold rescale (r*dt/tau != 1). For tau=0.0025, r=1.0,
    v_threshold=0.1: beta=0.96, w_scale=0.04 -> threshold rescaled to 2.5.
    Before this fix, codegen used exp(-1e-3/tau) (a different dt AND a
    different formula) and never rescaled the threshold.
    """
    code, _ = _generate_snntorch_code(_lif_norse_graph())
    assert (
        "self.n_1 = snn.Leaky(beta=0.960000, threshold=2.5000, "
        "reset_mechanism='zero', init_hidden=True, reset_delay=False)" in code
    )


def test_forward_default_keeps_ambiguous_3d_heuristic() -> None:
    """Regression: time_major_input defaults to False, so existing callers
    (nothing threaded a dataset format through before this fix) see byte-
    identical forward() bodies — this is a pure opt-in addition."""
    code, _ = _generate_snntorch_code(_lif_norse_graph())
    assert "elif x.dim() == 3 and x.shape[0] <= x.shape[1]:" in code
    assert "x = x.swapaxes(0, 1)  # (B,T,N) → (T,B,N) synthetic spike batches" in code


def test_forward_time_major_input_skips_ambiguous_3d_swap() -> None:
    """Regression: a tonic_* dataset (e.g. tonic_shd) delivers batches via
    tonic.collation.PadTensors(batch_first=False) — genuinely (T,B,N)
    already. The old heuristic (`x.shape[0] <= x.shape[1]`) wrongly re-swapped
    that whenever the real per-batch timestep count was <= batch_size (routine
    for SHD with a small time_window), scrambling batch/time and producing a
    near-zero training loss plus an eventual shape-mismatch crash. With
    time_major_input=True, the dim()==3 case must never swap."""
    code, _ = _generate_snntorch_code(_lif_norse_graph(), time_major_input=True)
    assert "elif x.dim() == 3 and x.shape[0] <= x.shape[1]:" not in code
    assert "x.swapaxes(0, 1)  # (B,T,N)" not in code
    assert "Preserve image axes for Conv2d" in code
    # A tonic image batch can be (T,B,C,H,W). Preserve those image axes so a
    # generated Conv2d receives (B,C,H,W), rather than flattening them into a
    # rank-2 feature tensor before the first convolution.
    assert "            x = x.flatten(start_dim=2)" not in code
    assert "x = x.unsqueeze(0)  # (B,C,H,W) → (1,B,C,H,W)" not in code
    assert "if x.dim() == 2:" in code


def test_recurrent_forward_time_major_input_skips_unconditional_swap() -> None:
    """Same fix, recurrent (RSynaptic/Synaptic/RLeaky) forward(): that path
    unconditionally swapaxes(0,1) assuming batch-first input, which is just
    as wrong for a tonic_* loader's genuinely time-first batches."""
    code, _ = _generate_snntorch_code(_braille_nir_graph())
    assert "x = x.swapaxes(0, 1)  # (B,T,...) → (T,B,...)" in code

    code_tm, _ = _generate_snntorch_code(_braille_nir_graph(), time_major_input=True)
    assert "x = x.swapaxes(0, 1)  # (B,T,...) → (T,B,...)" not in code_tm
    assert "already (T,B,...)" in code_tm


def test_recurrent_time_major_tonic_frame_batch_is_ce_count_loss_compatible(
    tmp_path, monkeypatch
) -> None:
    """SHD-style tonic frames can be (T,B,1,F); recurrent forward must flatten
    per-step features so ce_count_loss sees (T,B,C), not (T,B,1,C)."""
    torch = pytest.importorskip("torch")
    SF = pytest.importorskip("snntorch.functional")

    code, weights = _generate_snntorch_code(
        _braille_nir_graph(), weights_filename="weights.npz", time_major_input=True
    )
    assert "xt.flatten(start_dim=1)" in code
    np.savez(tmp_path / "weights.npz", **weights)
    monkeypatch.chdir(tmp_path)
    namespace: dict[str, object] = {}
    exec(compile(code, "<generated-recurrent-shd-frame>", "exec"), namespace)

    net = namespace["net"]
    spikes, _ = net(torch.zeros(5, 2, 1, 12, dtype=torch.float32))
    assert spikes.shape == (5, 2, 7)

    loss = SF.ce_count_loss()(spikes, torch.zeros(2, dtype=torch.long))
    assert loss.shape == ()
    loss.backward()


def test_lif_codegen_no_rescale_when_w_scale_near_one() -> None:
    """When r*dt/tau ~= 1 (here: r=10.0, tau=1e-3, dt=1e-4 -> w_scale=1.0),
    the oracle's hack_w_scale rescale must not fire — threshold is emitted
    unscaled."""
    graph = make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([1])}),
            "1": nir.LIF(
                tau=np.array([1e-3]),
                r=np.array([10.0]),
                v_leak=np.array([0.0]),
                v_threshold=np.array([0.3]),
            ),
            "output": nir.Output(output_type={"output": np.array([1])}),
        },
        edges=[("input", "1"), ("1", "output")],
    )
    code, _ = _generate_snntorch_code(graph)
    assert (
        "self.n_1 = snn.Leaky(beta=0.900000, threshold=0.3000, "
        "reset_mechanism='zero', init_hidden=True, reset_delay=False)" in code
    )


def test_lif_codegen_dt_metadata_override() -> None:
    """A `dt` metadata override on nir.LIF changes both the beta computation
    and the w_scale threshold rescale, since both derive from lif_dt. With
    tau=0.0025, r=1.0, v_threshold=0.1, dt=0.001 (metadata-overridden):
    beta = 1 - 0.001/0.0025 = 0.6, w_scale = 1.0*0.001/0.0025 = 0.4 ->
    threshold rescaled to 0.1/0.4 = 0.25.
    """
    graph = _lif_norse_graph()
    graph.nodes["1"].metadata = {"dt": 0.001}
    code, _ = _generate_snntorch_code(graph)
    assert (
        "self.n_1 = snn.Leaky(beta=0.600000, threshold=0.2500, "
        "reset_mechanism='zero', init_hidden=True, reset_delay=False)" in code
    )


def test_lif_codegen_beta_metadata_override_takes_precedence() -> None:
    """A `beta` metadata override on nir.LIF is used directly, bypassing the
    `beta = 1 - dt/tau` derivation entirely (threshold rescale still uses
    lif_dt, which stays at the default 1e-4 since no `dt` override is set
    here)."""
    graph = _lif_norse_graph()
    graph.nodes["1"].metadata = {"beta": 0.42}
    code, _ = _generate_snntorch_code(graph)
    assert "self.n_1 = snn.Leaky(beta=0.420000, threshold=" in code


def test_lif_codegen_no_metadata_matches_pre_metadata_baseline() -> None:
    """Critical backward-compat guarantee: with no `dt`/`beta` metadata on
    the node (the pre-existing default), generated output is byte-identical
    to before metadata overrides were introduced — same literal
    `beta=0.960000, threshold=2.5000` as `test_lif_codegen_matches_oracle_formula`."""
    graph = _lif_norse_graph()
    assert graph.nodes["1"].metadata == {}
    code, _ = _generate_snntorch_code(graph)
    assert (
        "self.n_1 = snn.Leaky(beta=0.960000, threshold=2.5000, "
        "reset_mechanism='zero', init_hidden=True, reset_delay=False)" in code
    )


def test_if_codegen_beta_metadata_override() -> None:
    """A `beta` metadata override on nir.IF changes the emitted literal."""
    graph = _conv_if_nir_graph()
    graph.nodes["1"].metadata = {"beta": 0.5}
    code, _ = _generate_snntorch_code(graph)
    assert (
        "self.n_1 = snn.Leaky(beta=0.500000, threshold=1.0000, "
        "init_hidden=True, reset_delay=False)" in code
    )
    # The other IF node ("4"), with no override, keeps the 0.9 default.
    assert (
        "self.n_4 = snn.Leaky(beta=0.900000, threshold=1.0000, "
        "init_hidden=True, reset_delay=False)" in code
    )


def test_if_codegen_no_metadata_matches_pre_metadata_baseline() -> None:
    """Critical backward-compat guarantee: with no `beta` metadata present
    (the pre-existing default), generated output is byte-identical to
    before metadata overrides were introduced — same literal
    `beta=0.900000` as `test_if_neuron_forward_uses_init_hidden_call`."""
    graph = _conv_if_nir_graph()
    assert graph.nodes["1"].metadata == {}
    assert graph.nodes["4"].metadata == {}
    code, _ = _generate_snntorch_code(graph)
    assert (
        "self.n_1 = snn.Leaky(beta=0.900000, threshold=1.0000, "
        "init_hidden=True, reset_delay=False)" in code
    )


def test_cubalif_codegen_unchanged_by_lif_branch_split() -> None:
    """Splitting the combined nir.LIF|nir.CubaLIF branch into two separate
    branches must not change nir.CubaLIF's pre-existing snn.Leaky
    approximation (a known, ponytail-flagged gap — out of scope for this
    fix)."""
    graph = make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "1": nir.CubaLIF(
                tau_syn=np.array([0.01, 0.01]),
                tau_mem=np.array([0.02, 0.02]),
                r=np.array([1.0, 1.0]),
                v_leak=np.array([0.0, 0.0]),
                v_threshold=np.array([1.0, 1.0]),
                w_in=np.array([1.0, 1.0]),
            ),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "1"), ("1", "output")],
    )
    code, _ = _generate_snntorch_code(graph)
    assert "init_hidden=True)" in code
    assert "reset_mechanism='zero'" not in code
    assert "reset_delay=False" not in code
    assert "approximates CubaLIF with snn.Leaky" in code


def test_lif_neuron_generated_net_forward_runs(tmp_path, monkeypatch) -> None:
    """The generated Net for a nir.LIF node must instantiate and run a forward
    pass without error — the execution-level check that would have caught the
    original dt/w_scale mismatch, not just a string-match."""
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")

    code, weights = _generate_snntorch_code(_lif_norse_graph())
    np.savez(tmp_path / "weights.npz", **weights)
    monkeypatch.chdir(tmp_path)

    ns: dict[str, object] = {}
    exec(compile(code, "<generated_net>", "exec"), ns)

    net = ns["net"]
    # (T=5, B=2, 1) — non-recurrent path loops over dim 0 directly (dim() != 4).
    x = torch.zeros(5, 2, 1, dtype=torch.float32)
    spk_out, _last_spk = net(x)
    assert spk_out.shape == (5, 2, 1)

    # Synthetic spike-generator DataLoaders produce (B, T, N); generated
    # notebooks must still step over the time axis.
    x_batch_first = torch.zeros(2, 5, 1, dtype=torch.float32)
    spk_out_batch_first, _mem_out_batch_first = net(x_batch_first)
    assert spk_out_batch_first.shape == (5, 2, 1)


def test_activity_capture_codegen_one_entry_per_spiking_layer() -> None:
    """Every spiking layer must get its own `_activity_acc`/`_layer_activity`
    entry (keyed the same way as `_layer_rates`), gated behind
    `self._capture_activity` so nothing is captured — or allocated — unless a
    caller explicitly opts in for one eval sample.
    """
    code, _ = _generate_snntorch_code(_braille_nir_graph())

    assert "self._capture_activity = False" in code
    assert "_activity_acc = {'rsyn': [], 'syn': []}" in code
    assert (
        "if self._capture_activity: _activity_acc['rsyn'].append("
        "spk_rsyn[0].detach().flatten().cpu().numpy())" in code
    )
    assert (
        "if self._capture_activity: _activity_acc['syn'].append("
        "spk_syn[0].detach().flatten().cpu().numpy())" in code
    )
    assert "if self._capture_activity:" in code
    assert (
        "self._layer_activity = "
        "{k: np.stack(v, axis=0) for k, v in _activity_acc.items() if v}" in code
    )


def test_activity_capture_codegen_non_recurrent_branch() -> None:
    """The non-recurrent forward() variant (plain LIF, no RSynaptic/Synaptic/
    RLeaky) gets the same capture wiring as the recurrent one."""
    code, _ = _generate_snntorch_code(_lif_norse_graph())
    assert "self._capture_activity = False" in code
    assert "_activity_acc = {'n_1': []}" in code
    assert "self._layer_activity = " in code


# ── from test_notebook_generate_v2.py (exporter/target codegen) ──


def test_nengo_target_rsynaptic_shaped_graph_not_scaffolded() -> None:
    """Regression: NengoIO.from_nir previously crashed on any real nir.CubaLIF
    node (AttributeError: no `.tau`), which _safe_io_call silently swallowed
    into a "# NengoIO scaffold" fallback comment -- exactly how the gap went
    undetected. A CnlRSynaptic-shaped graph (flat nir.CubaLIF + same-
    population nir.Linear self-loop, as the real exporter produces) must now
    produce real Nengo code, not the scaffold.
    """
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc1": nir.Linear(weight=np.eye(3, 2)),
            "lif1_lif": nir.CubaLIF(
                tau_syn=np.array([0.01, 0.01, 0.01]),
                tau_mem=np.array([0.02, 0.02, 0.02]),
                r=np.array([1.0, 1.0, 1.0]),
                v_leak=np.array([0.0, 0.0, 0.0]),
                v_threshold=np.array([1.0, 1.0, 1.0]),
                w_in=np.array([1.0, 1.0, 1.0]),
            ),
            "lif1_w_rec": nir.Linear(weight=np.zeros((3, 3))),
            "output": nir.Output(output_type={"output": np.array([3])}),
        },
        edges=[
            ("input", "fc1"),
            ("fc1", "lif1_lif"),
            ("lif1_lif", "lif1_w_rec"),
            ("lif1_w_rec", "lif1_lif"),
            ("lif1_lif", "output"),
        ],
        type_check=False,
    )
    nb, _ = _build_v2_notebook(
        "",
        graph,
        PipelineConfigPayload(framework="nengo"),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    code = _code_sources(nb)
    assert "NengoIO scaffold" not in code
    assert "nengo.Ensemble" in code
    assert "nengo.synapses.Lowpass" in code


def test_rockpool_target_rsynaptic_graph_flattens_to_approximate_cubalif() -> None:
    """Phase E: cnl.RSynaptic is flattened to nir.CubaLIF + a recurrent
    nir.Linear self-loop before classification/codegen. Rockpool's table
    marks CubaLIF 'approximate' (not exact, not unsupported) — level becomes
    'approximate', and both the backend caveat and the flatten's own
    lossy-substitution note must be visible in the warning cell.
    """
    from neurocnl.runtime.cnl_nodes import RSynaptic

    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "rsyn": RSynaptic(n_neurons=2, alpha=0.9, beta=0.8),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "rsyn"), ("rsyn", "output")],
        type_check=False,
    )
    nb, _ = _build_v2_notebook(
        "",
        graph,
        PipelineConfigPayload(framework="rockpool"),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    md_src = " ".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown"
    )
    assert "APPROXIMATE" in md_src
    assert "UNSUPPORTED" not in md_src
    assert "CubaLIF" in md_src
    assert "structural-only" in md_src

    code = _code_sources(nb)
    assert "RockpoolIO" in code
    assert "flatten_cnl_ops" in code  # embed_flatten kicked in for rockpool's codegen


def test_nir_exporter_runs_once_after_training_and_reloads_best_checkpoint() -> None:
    from neurocnl.compile import compile_to_nir

    phases = PipelinePhasesPayload(
        train=PhaseDAGPayload(
            nodes=[
                DagNodePayload(id="forward", type="forwardPass"),
                DagNodePayload(
                    id="export",
                    type="nirExporter",
                    parameters={"filename": "trained.nir"},
                ),
            ]
        )
    )
    notebook, _ = _build_v2_notebook(
        VALID_SPEC,
        compile_to_nir(VALID_SPEC),
        PipelineConfigPayload(framework="snntorch_sim", epochs=2),
        "2026-08-04 00:00 UTC",
        pipeline_phases=phases,
    )
    train_code = _cell_after_md(notebook, "## Train")

    assert train_code.count("nir.write('trained.nir', graph)") == 1
    assert train_code.index("for epoch in range(2):") < train_code.index("nir.write")
    assert "torch.load('best_model.pt'" in train_code
    assert "_nmtk_nir_module_names" in _code_sources(notebook)


def test_nir_exporter_copies_exact_best_checkpoint_affine_weights(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    torch = pytest.importorskip("torch", exc_type=ImportError)
    from backend.app.routers.notebook import _dag_node_code

    class TinyNet(torch.nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.fc = torch.nn.Linear(3, 2)

    checkpoint = TinyNet()
    with torch.no_grad():
        checkpoint.fc.weight.copy_(torch.tensor([[1.0, 2.0, 3.0], [-1.0, -2.0, -3.0]]))
        checkpoint.fc.bias.copy_(torch.tensor([0.25, -0.5]))
    monkeypatch.chdir(tmp_path)
    torch.save(checkpoint.state_dict(), "best_model.pt")
    net = TinyNet()
    graph = nir.NIRGraph(
        nodes={
            "fc": nir.Affine(
                weight=np.zeros((2, 3), dtype=np.float32),
                bias=np.zeros(2, dtype=np.float32),
            )
        },
        edges=[],
        type_check=False,
    )
    saved: list[nir.NIRGraph] = []
    monkeypatch.setattr(nir, "write", lambda _path, exported: saved.append(exported))
    code = _dag_node_code(
        DagNodePayload(
            id="export",
            type="nirExporter",
            parameters={"filename": "trained.nir"},
        ),
        PipelineConfigPayload(),
        "MNIST",
    )

    exec(
        compile(code or "", "<nir-exporter>", "exec"),
        {
            "torch": torch,
            "net": net,
            "graph": graph,
            "_nmtk_nir_module_names": {"fc": "fc"},
        },
    )

    assert len(saved) == 1
    np.testing.assert_array_equal(
        saved[0].nodes["fc"].weight,
        checkpoint.fc.weight.detach().numpy(),
    )
    np.testing.assert_array_equal(
        saved[0].nodes["fc"].bias,
        checkpoint.fc.bias.detach().numpy(),
    )


def test_sinabs_target_is_inference_only_and_has_studio_wrapper() -> None:
    from neurocnl.compile import compile_to_nir

    phases = PipelinePhasesPayload(
        train=PhaseDAGPayload(nodes=[DagNodePayload(id="forward", type="forwardPass")])
    )
    notebook, _ = _build_v2_notebook(
        VALID_SPEC,
        compile_to_nir(VALID_SPEC),
        PipelineConfigPayload(framework="sinabs"),
        "2026-08-04 00:00 UTC",
        pipeline_phases=phases,
    )
    markdown = "\n".join(
        "".join(cell["source"])
        for cell in notebook["cells"]
        if cell["cell_type"] == "markdown"
    )
    code = _code_sources(notebook)

    assert "Inference / code generation only" in markdown
    assert "for epoch in range" not in code
    assert "StudioSinabsInference" in code
    assert "net = build_model()" in code


def test_akida_exporter_runs_once_after_training_and_compares_accuracy() -> None:
    from neurocnl.compile import compile_to_nir

    phases = PipelinePhasesPayload(
        train=PhaseDAGPayload(
            nodes=[
                DagNodePayload(id="forward", type="forwardPass"),
                DagNodePayload(
                    id="akida",
                    type="akidaExporter",
                    parameters={"filename": "trained.fbz", "weight_bits": 2},
                ),
            ]
        )
    )
    notebook, _ = _build_v2_notebook(
        VALID_SPEC,
        compile_to_nir(VALID_SPEC),
        PipelineConfigPayload(framework="snntorch_sim", epochs=2),
        "2026-08-06 00:00 UTC",
        pipeline_phases=phases,
    )
    train_code = _cell_after_md(notebook, "## Train")

    # Once, and after the epoch loop -- not once per batch.
    assert train_code.count("_ak_model.save('trained.fbz')") == 1
    assert train_code.index("for epoch in range(2):") < train_code.index("_ak_model")
    assert "torch.load('best_model.pt'" in train_code
    # The comparison is the point of the node; both numbers must be printed.
    assert "snnTorch accuracy" in train_code
    assert "Akida accuracy" in train_code
    assert "Conversion delta" in train_code
    # The chosen bit width must reach the converter, not silently default.
    assert "weight_bits=2" in train_code


def test_every_generated_net_call_unpacks_the_forward_tuple() -> None:
    """`forward()` always returns `(spikes, membrane)`.

    The Akida Exporter cell used to bind a single name and then call `.sum(0)`
    on it, which raised `AttributeError: 'tuple' object has no attribute 'sum'`
    at runtime -- invisible to a test that only compiles the cell. This guards
    every call site at once so a new exporter cannot reintroduce it.
    """
    from neurocnl.compile import compile_to_nir

    phases = PipelinePhasesPayload(
        train=PhaseDAGPayload(
            nodes=[
                DagNodePayload(id="forward", type="forwardPass"),
                DagNodePayload(id="akida", type="akidaExporter", parameters={}),
            ]
        )
    )
    notebook, _ = _build_v2_notebook(
        VALID_SPEC,
        compile_to_nir(VALID_SPEC),
        PipelineConfigPayload(framework="snntorch_sim", epochs=1),
        "2026-08-06 00:00 UTC",
        pipeline_phases=phases,
    )
    source = "\n".join("".join(cell.get("source", "")) for cell in notebook["cells"])

    # `<name> = net(...)` with a single bound name, excluding `def`/`self.`
    # attribute assignment inside the model class.
    offenders = re.findall(r"^\s*([A-Za-z_]\w*)\s*=\s*net\(", source, re.MULTILINE)
    assert (
        offenders == []
    ), f"these generated call sites treat net(...) as a single tensor: {offenders}"
    # And the exporter's own line is the destructuring form.
    assert "_spk, _ = net(_data)" in source


def test_akida_exporter_rejects_an_unsupported_weight_bit_width() -> None:
    """An out-of-range width falls back to 4 rather than emitting a broken cell.

    Akida accepts 1, 2, 4 or 8 only; anything else raises inside the converter,
    which would surface as a failed training run long after the mistake.
    """
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    code = _dag_node_code(
        DagNodePayload(id="akida", type="akidaExporter", parameters={"weight_bits": 5}),
        PipelineConfigPayload(),
        "MNIST",
    )
    assert code is not None
    assert "weight_bits=4" in code
    assert "weight_bits=5" not in code


def test_akida_exporter_requires_an_eval_loader_and_a_checkpoint() -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    code = _dag_node_code(
        DagNodePayload(id="akida", type="akidaExporter", parameters={}),
        PipelineConfigPayload(),
        "MNIST",
    )
    assert code is not None
    # Guarded the same way forward() guards num_steps.
    assert "'test_loader' not in globals()" in code
    assert "best_model.pt" in code
    compile(code, "<akida-exporter>", "exec")


def test_akida_exporter_writes_a_deploy_bundle_by_default() -> None:
    """Without the bundle the converted model cannot reach the card.

    `/notebook/artifacts/latest-akida-bundle` globs `*.akida-bundle.zip` and the
    launcher's filename validator rejects anything else, so a bare `model.fbz`
    is invisible to every deploy control in the app.
    """
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    code = _dag_node_code(
        DagNodePayload(
            id="akida", type="akidaExporter", parameters={"filename": "trained.fbz"}
        ),
        PipelineConfigPayload(),
        "MNIST",
    )
    assert code is not None
    compile(code, "<akida-exporter>", "exec")
    assert "Path('trained.akida-bundle.zip')" in code
    assert "'schemaVersion': 2" in code
    assert "'sourceFramework': 'snntorch'" in code
    assert "'model.fbz': Path('trained.fbz').read_bytes()" in code
    assert "'akida_sim_accuracy': _akd_acc" in code
    # The default sample cap keeps the archive under the host's 32 MB limit.
    assert "min(_ak_total, 2000)" in code


def test_akida_exporter_saves_the_form_the_host_can_serve() -> None:
    """The classifier's activation must be off, and scoring must use predict().

    The Akida host runs `model.predict` when it serves a sample and that call
    requires the final layer's activation disabled, so a model saved the other
    way fails on arrival rather than at export time.
    """
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    code = _dag_node_code(
        DagNodePayload(id="akida", type="akidaExporter", parameters={}),
        PipelineConfigPayload(),
        "MNIST",
    )
    assert code is not None
    assert "activation_on_last=False" in code
    assert "_ak_model.predict(_ak_inputs)" in code
    assert "_ak_model.forward(" not in code


def test_akida_exporter_bundle_can_be_switched_off() -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    code = _dag_node_code(
        DagNodePayload(
            id="akida", type="akidaExporter", parameters={"deploy_bundle": False}
        ),
        PipelineConfigPayload(),
        "MNIST",
    )
    assert code is not None
    compile(code, "<akida-exporter>", "exec")
    assert "akida-bundle.zip" not in code
    # The conversion itself is unaffected.
    assert "_ak_model.save('model.fbz')" in code


@pytest.mark.parametrize("test_loader_first", [False, True])
def test_explicit_test_loader_wins_over_the_pt_fallback(
    test_loader_first: bool,
) -> None:
    """An explicit Test Loader must bind `test_loader`, whatever the node order.

    A `.pt` Data Loader binds `test_loader` too, as a fallback. Emitted after a
    Test Loader it silently replaces the test set with the training split --
    invisible in the notebook, and it inflates every number downstream,
    including the Akida Exporter's accuracy and the evaluation samples it ships
    to the card.
    """
    from neurocnl.compile import compile_to_nir

    train_dl = DagNodePayload(
        id="train_dl",
        type="dataLoader",
        parameters={
            "format": "pt",
            "dataset_path": "mnist_train.pt",
            "batch_size": 128,
        },
    )
    test_dl = DagNodePayload(
        id="test_dl",
        type="testLoader",
        parameters={"format": "pt", "dataset_path": "mnist_test.pt", "batch_size": 128},
    )
    nodes = [test_dl, train_dl] if test_loader_first else [train_dl, test_dl]
    nodes = [*nodes, DagNodePayload(id="fwd", type="forwardPass")]

    notebook, _ = _build_v2_notebook(
        VALID_SPEC,
        compile_to_nir(VALID_SPEC),
        PipelineConfigPayload(framework="snntorch_sim", epochs=1),
        "2026-08-06 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(train=PhaseDAGPayload(nodes=nodes)),
    )
    train_code = _cell_after_md(notebook, "## Train")

    fallback = train_code.index("test_loader  = DataLoader(_ds")
    explicit = train_code.index("test_loader = DataLoader(_test_ds")
    assert (
        explicit > fallback
    ), "the .pt fallback must not overwrite the explicit test set"


def test_generated_bundle_validates_against_the_host_contract(tmp_path: Path) -> None:
    """Run the emitted bundle code for real and hand the zip to the host validator.

    The two sides live in different repos -- the exporter writes the manifest
    here, the Akida host parses it in Neurochip -- so nothing but an actual
    round trip catches a renamed key or a changed dtype. Skipped when the
    Neurochip checkout is absent, e.g. a standalone neurocnl CI run.
    """
    import sys

    neurochip_root = Path(__file__).resolve().parents[3] / "Neurochip"
    if not neurochip_root.is_dir():
        pytest.skip("Neurochip checkout is not present")
    sys.path.insert(0, str(neurochip_root))
    try:
        jobs = pytest.importorskip("neurochip.app.services.akida_model_jobs")
    finally:
        sys.path.remove(str(neurochip_root))

    from backend.app.routers.notebook import _akida_bundle_code

    samples, features, classes = 6, 12, 3
    model_file = tmp_path / "trained.fbz"
    model_file.write_bytes(b"fake-fbz")
    namespace: dict[str, object] = {
        "Path": Path,
        "np": np,
        "_ak_total": samples,
        "_ak_inputs": np.zeros((samples, 1, 1, features), dtype=np.uint8),
        "_ak_y": np.arange(samples, dtype=np.int64) % classes,
        "_ak_out": np.zeros((samples, classes), dtype=np.float32),
        "_ak_scale": 15.0,
        "_snn_acc": 0.93,
        "_akd_acc": 0.88,
    }
    code = _akida_bundle_code("trained", "trained.fbz", 2000)
    cwd = os.getcwd()
    os.chdir(tmp_path)
    try:
        exec(compile(code, "<akida-bundle>", "exec"), namespace)  # noqa: S102
    finally:
        os.chdir(cwd)

    bundle_bytes = (tmp_path / "trained.akida-bundle.zip").read_bytes()
    service = jobs.AkidaModelJobService(tmp_path / "store")
    validated = service._validate_bundle(bundle_bytes)

    assert validated.is_preconverted is True
    assert validated.manifest.source_framework == "snntorch"
    assert validated.manifest.source_metrics["akida_sim_accuracy"] == 0.88
    assert validated.evaluation_inputs.shape == (samples, 1, 1, features)
    assert validated.evaluation_labels.dtype == np.int32
    assert validated.files["model.fbz"] == b"fake-fbz"


def test_akida_exporter_bundle_is_emitted_once_after_training() -> None:
    from neurocnl.compile import compile_to_nir

    phases = PipelinePhasesPayload(
        train=PhaseDAGPayload(
            nodes=[
                DagNodePayload(id="forward", type="forwardPass"),
                DagNodePayload(id="akida", type="akidaExporter"),
            ]
        )
    )
    notebook, _ = _build_v2_notebook(
        VALID_SPEC,
        compile_to_nir(VALID_SPEC),
        PipelineConfigPayload(framework="snntorch_sim", epochs=2),
        "2026-08-06 00:00 UTC",
        pipeline_phases=phases,
    )
    train_code = _cell_after_md(notebook, "## Train")

    assert train_code.count("_ak_bundle_path = Path(") == 1
    assert train_code.index("for epoch in range(2):") < train_code.index(
        "_ak_bundle_path"
    )
