"""Behavioural golden tests for notebook code generation.

Every other test module for `backend.app.routers.notebook` asserts on the
*text* of the generated code — `assert "snn.Synaptic(" in code`. Those tests
are worth keeping (they pin syntax and kwarg spelling cheaply), but they are
structurally blind to the failure mode that has actually reached users, over
and over: the emitted code is syntactically perfect, contains every expected
substring, runs without raising — and computes nothing.

Concretely, string assertions cannot see any of these:

- A network whose weight matrices never arrive, so it runs on zeros or on
  random initialisation and reports chance accuracy.
- A threshold or time constant that was dropped in transit, so the population
  either never fires or fires every step.
- A batch/time axis swap, which produces a near-zero loss and a plausible
  training curve rather than an error.

The existing `exec()`-based tests get closer, but 10 of their 14 forward
passes feed `torch.zeros`, so "output is all zeros" is the *expected* result
and a genuinely dead network is indistinguishable from a healthy one. Every
occurrence of the word "accuracy" in those modules is a substring check
against generated source; none of them is a number computed by running the
generated network.

So this module runs the generated code on non-zero input with known weights
and asserts on numbers. The task is hand-solved rather than trained: two
linearly separable classes and a weight matrix written by hand, so the
expected accuracy is 100% by construction, deterministically, with no
training loop and no checked-in binary fixture.

Two assertions here are `xfail(strict=True)` because they describe behaviour
the generator does not have yet, not bugs in the test: one target's cell does
not execute at all, and a freshly generated cell does not disclose that its
weights are untrained. Each marker cites the source fact it rests on. Strict
xfail means the marker itself fails the suite the moment the gap is closed, so
neither can rot into a permanently ignored test.

Note what the second one is *not* claiming. Falling back to random
initialisation for an all-zero matrix is correct — a CNL spec carries tensor
shape only, so an untrained network arrives as zeros, and this generator emits
the architecture cell that the notebook then trains. Training already done
through a generated notebook was trained normally, on normally initialised
weights. The gap is that nothing at run time distinguishes that fresh state
from a trained one.
"""

from __future__ import annotations

import contextlib
import io
import warnings

import numpy as np
import nir
import pytest

from backend.app.routers.notebook import (
    _generate_sc_neurocore_code,
    _generate_snntorch_code,
)
from neurocnl._nir_compat import make_nir_graph
from neurocnl.runtime.cnl_nodes import RSynaptic as CnlRSynaptic
from neurocnl.runtime.cnl_nodes import Synaptic as CnlSynaptic

# Number of rate-coding timesteps the generated forward() repeats a static
# (B, F) feature batch over. Real notebooks define `num_steps` in an earlier
# cell; the generated forward() reads it via `globals().get('num_steps', 1)`,
# so it has to be seeded into the exec namespace here too.
NUM_STEPS = 20

# Two linearly separable classes over 4 features: class 0 activates the first
# feature pair, class 1 the second.
CLASS_PATTERNS = (
    np.array([1.0, 1.0, 0.0, 0.0], dtype=np.float32),
    np.array([0.0, 0.0, 1.0, 1.0], dtype=np.float32),
)

# The hand-solved readout: row i is +1 on class i's features and -1 on the
# other class's, so the correct unit receives +2 per timestep and the wrong
# one -2. No training involved; this matrix is the answer.
SOLVED_WEIGHT = np.array([[1.0, 1.0, -1.0, -1.0], [-1.0, -1.0, 1.0, 1.0]], dtype=np.float32)


def _feedforward_graph(
    weight: np.ndarray, *, tau: float = 0.01, v_threshold: float = 0.005
) -> nir.NIRGraph:
    """Input -> Linear -> LIF -> Output over `weight`.

    `tau`/`v_threshold` are the two parameters that have historically been
    lost in transit, so they are arguments rather than constants: the tests
    below vary them and assert the running network changes accordingly.
    """
    n_out, n_in = weight.shape
    return make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([n_in])}),
            "fc1": nir.Linear(weight=weight),
            "lif1": nir.LIF(
                tau=np.full(n_out, tau),
                r=np.ones(n_out),
                v_leak=np.zeros(n_out),
                v_threshold=np.full(n_out, v_threshold),
            ),
            "output": nir.Output(output_type={"output": np.array([n_out])}),
        },
        edges=[("input", "fc1"), ("fc1", "lif1"), ("lif1", "output")],
    )


def _recurrent_graph(w1: np.ndarray, w2: np.ndarray) -> nir.NIRGraph:
    """Input -> Linear -> RSynaptic -> Linear -> Synaptic -> Output.

    The recurrent path emits a different forward() body from the feedforward
    one (explicit hidden-state threading, an unconditional `(B,T,F) ->
    (T,B,F)` swap, no input-width guard), so it needs its own behavioural
    coverage rather than inheriting the LIF tests' confidence.
    """
    return make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([w1.shape[1]])}),
            "fc1": nir.Linear(weight=w1),
            "rsyn": CnlRSynaptic(
                n_neurons=w1.shape[0],
                alpha=0.9,
                beta=0.8,
                threshold=0.5,
                reset_mechanism="subtract",
            ),
            "fc2": nir.Linear(weight=w2),
            "syn": CnlSynaptic(
                n_neurons=w2.shape[0],
                alpha=0.9,
                beta=0.8,
                threshold=0.5,
                reset_mechanism="subtract",
            ),
            "output": nir.Output(output_type={"output": np.array([w2.shape[0]])}),
        },
        edges=[
            ("input", "fc1"),
            ("fc1", "rsyn"),
            ("rsyn", "fc2"),
            ("fc2", "syn"),
            ("syn", "output"),
        ],
    )


def _run_snntorch(graph: nir.NIRGraph, x, tmp_path, monkeypatch) -> tuple:
    """Generate, write `weights.npz`, exec, and run one forward pass.

    Returns `(net, spk, aux, weights)` where `weights` is the npz payload the
    generator produced — the tests compare the *running* module's parameters
    against it, which is the contract that matters: what is written next to
    the notebook is what the notebook computes with.
    """
    code, weights = _generate_snntorch_code(graph)
    np.savez(tmp_path / "weights.npz", **weights)
    monkeypatch.chdir(tmp_path)
    namespace: dict[str, object] = {"num_steps": NUM_STEPS}
    exec(compile(code, "<generated-net>", "exec"), namespace)
    net = namespace["net"]
    spk, aux = net(x)
    return net, spk, aux, weights


def _labelled_batch(torch, *, per_class: int = 10, noise: float = 0.05):
    """A deterministic (B, F) batch of both class patterns plus fixed noise."""
    rng = np.random.default_rng(0)
    features = np.concatenate(
        [np.tile(pattern, (per_class, 1)) for pattern in CLASS_PATTERNS]
    ).astype(np.float32)
    features += rng.normal(0.0, noise, features.shape).astype(np.float32)
    labels = np.repeat(np.arange(len(CLASS_PATTERNS)), per_class)
    return torch.from_numpy(features), labels


def test_npz_weights_are_the_weights_the_network_runs_on(tmp_path, monkeypatch) -> None:
    """The trained matrix must arrive in the running module, bit for bit.

    This is the assertion that "the simulator ran a network of zeros" would
    have failed. A substring check for `torch.from_numpy(_w['fc1_weight']...)`
    passes whether or not that line is reached, whether or not the npz holds
    the trained values, and whether or not something later overwrites them.
    """
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")

    x, _ = _labelled_batch(torch)
    net, _, _, weights = _run_snntorch(_feedforward_graph(SOLVED_WEIGHT), x, tmp_path, monkeypatch)

    assert np.array_equal(weights["fc1_weight"], SOLVED_WEIGHT)
    np.testing.assert_array_equal(net.fc1.weight.detach().cpu().numpy(), weights["fc1_weight"])


def test_generated_network_emits_spikes_on_real_input(tmp_path, monkeypatch) -> None:
    """A healthy network must fire. Silence is the bug, not the baseline.

    Deployments have shipped a network that returned nothing at all while
    every generated-source assertion stayed green. Feeding `torch.zeros` — as
    the sibling exec tests do — cannot distinguish that from correct
    behaviour, because zero output is the right answer for zero input.
    """
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")

    x, _ = _labelled_batch(torch)
    _, spk, _, _ = _run_snntorch(_feedforward_graph(SOLVED_WEIGHT), x, tmp_path, monkeypatch)

    assert spk.shape == (NUM_STEPS, x.shape[0], SOLVED_WEIGHT.shape[0])
    assert int(spk.sum()) > 0, "generated network produced no spikes on non-zero input"


def test_generated_network_classifies_above_chance(tmp_path, monkeypatch) -> None:
    """Rate-decoded output must recover the label the weights encode.

    The weight matrix is the hand-written solution to a linearly separable
    two-class problem, so this is exact rather than statistical: the correct
    unit integrates +2 per step and the wrong one -2. Any break in weight
    delivery, threshold scaling, reset semantics, or axis order collapses
    this to chance.
    """
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")

    x, labels = _labelled_batch(torch)
    _, spk, _, _ = _run_snntorch(_feedforward_graph(SOLVED_WEIGHT), x, tmp_path, monkeypatch)

    predicted = spk.sum(dim=0).argmax(dim=1).cpu().numpy()
    accuracy = float((predicted == labels).mean())
    assert accuracy >= 0.9, f"rate-decoded accuracy {accuracy:.2f} is at chance"


def test_firing_threshold_reaches_the_running_network(tmp_path, monkeypatch) -> None:
    """A threshold far above the input must silence the network.

    `v_threshold` is rescaled by `1 / w_scale` on the way into
    `snn.Leaky(threshold=...)` (`w_scale = r * dt / tau`), so a dropped or
    zeroed threshold does not raise — it changes the firing rate. Here the
    rescaled threshold is 10000 against a steady-state membrane of ~200, so
    the correct answer is exactly zero spikes.
    """
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")

    x, _ = _labelled_batch(torch)
    _, spk, _, _ = _run_snntorch(
        _feedforward_graph(SOLVED_WEIGHT, v_threshold=100.0), x, tmp_path, monkeypatch
    )

    assert int(spk.sum()) == 0, "firing threshold had no effect on the running network"


def test_time_constant_reaches_the_running_network(tmp_path, monkeypatch) -> None:
    """Raising tau must lower the firing rate.

    tau enters the generated module twice — as `beta = 1 - dt / tau` and
    through the threshold rescale — so a dropped tau still yields a running
    network with a plausible rate. Only comparing two taus catches it.
    """
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")

    x, _ = _labelled_batch(torch)
    _, fast, _, _ = _run_snntorch(
        _feedforward_graph(SOLVED_WEIGHT, tau=0.01), x, tmp_path, monkeypatch
    )
    _, slow, _, _ = _run_snntorch(
        _feedforward_graph(SOLVED_WEIGHT, tau=0.1), x, tmp_path, monkeypatch
    )

    assert int(fast.sum()) > int(slow.sum()), (
        "tau did not change the firing rate — the running network is ignoring it"
    )


def test_recurrent_weights_reach_the_running_network(tmp_path, monkeypatch) -> None:
    """Both matrices of an RSynaptic/Synaptic network must arrive intact."""
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")

    rng = np.random.default_rng(7)
    w1 = rng.normal(0.0, 1.0, (8, 6)).astype(np.float32)
    w2 = rng.normal(0.0, 1.0, (3, 8)).astype(np.float32)
    # The recurrent forward() takes (B, T, F) and swaps to time-major itself.
    x = torch.from_numpy(rng.random((4, 10, 6)).astype(np.float32))

    net, _, _, weights = _run_snntorch(_recurrent_graph(w1, w2), x, tmp_path, monkeypatch)

    np.testing.assert_array_equal(net.fc1.weight.detach().cpu().numpy(), w1)
    np.testing.assert_array_equal(net.fc2.weight.detach().cpu().numpy(), w2)
    assert sorted(weights) == ["fc1_weight", "fc2_weight"]


def test_recurrent_network_emits_spikes_at_both_layers(tmp_path, monkeypatch) -> None:
    """Hidden and output populations must both fire.

    The recurrent generator threads hidden state by hand across five explicit
    tensors. A mistake there silences one layer while the other keeps
    producing output, which reads as a healthy run.
    """
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")

    rng = np.random.default_rng(7)
    w1 = rng.normal(0.0, 1.0, (8, 6)).astype(np.float32)
    w2 = rng.normal(0.0, 1.0, (3, 8)).astype(np.float32)
    x = torch.from_numpy(rng.random((4, 10, 6)).astype(np.float32))

    _, spk, hidden, _ = _run_snntorch(_recurrent_graph(w1, w2), x, tmp_path, monkeypatch)

    assert int(hidden.sum()) > 0, "hidden RSynaptic population produced no spikes"
    assert int(spk.sum()) > 0, "output Synaptic population produced no spikes"


@pytest.mark.xfail(
    strict=True,
    reason=(
        "Missing warning, not a wrong computation. Falling back to PyTorch's "
        "random init here is CORRECT: a CNL spec stores tensor shape only, so "
        "a not-yet-trained network arrives with all-zero matrices, and this "
        "generator builds the architecture cell that the notebook then trains "
        "— training from all-zeros would leave every unit identical. What is "
        "missing is that the fallback never says so. notebook.py's Linear/"
        "Affine and Conv2d branches (four sites) swap the "
        "`torch.from_numpy(_w[...])` load for a source *comment*, and a "
        "comment produces no output when the cell runs: the executed cell "
        "prints only 'Net: N parameters'. The zeros are still written to "
        "weights.npz and still listed in _expected_weight_keys, so the "
        "'weights file does not match this network' guard stays quiet too. A "
        "reader therefore cannot tell a freshly initialised network from a "
        "trained one by running it. That ambiguity is the same convention "
        "behind the shipped deploy failures (deploy.py's trained_nir_base64 "
        "field documents it: without a trained .nir 'they are all zeros and "
        "the board will fire nothing'). Fix is a visible runtime notice naming "
        "the untrained layers, not a change to what the network computes."
    ),
)
def test_untrained_layers_announce_themselves_at_runtime(tmp_path, monkeypatch) -> None:
    """Running a freshly generated cell must say its weights are untrained.

    Asserts on what the *executed* cell tells the user, not on the weight
    values — random init is the right starting point for training, so the
    contract under test is disclosure, not arithmetic.
    """
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")

    zeros = np.zeros((2, 4), dtype=np.float32)
    code, weights = _generate_snntorch_code(_feedforward_graph(zeros))
    np.savez(tmp_path / "weights.npz", **weights)
    monkeypatch.chdir(tmp_path)

    output = io.StringIO()
    namespace: dict[str, object] = {"num_steps": NUM_STEPS}
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            exec(compile(code, "<generated-net>", "exec"), namespace)

    announced = output.getvalue() + " ".join(str(w.message) for w in caught)
    assert "fc1" in announced and any(
        word in announced.lower() for word in ("untrained", "random", "not trained")
    ), (
        "running the generated cell gave no indication that 'fc1' holds fresh "
        f"random weights rather than trained ones; it emitted only {announced!r}"
    )
    # The weight matrix the npz carries is all zeros while the running module
    # holds random values — pinned here so the discrepancy the notice must
    # describe stays visible alongside the assertion above.
    assert np.array_equal(weights["fc1_weight"], zeros)
    assert not np.array_equal(namespace["net"].fc1.weight.detach().cpu().numpy(), zeros)


@pytest.mark.xfail(
    strict=True,
    reason=(
        "Defect, not a test bug: the generated SC-NeuroCore cell does not run "
        "at all. It emits `scn.SpikeMonitor()` while sc_neurocore's "
        "SpikeMonitor requires the population positionally, so execution "
        "raises TypeError immediately. Even once that is fixed the cell cannot "
        "compute anything: _generate_sc_neurocore_code assigns "
        "`fc1_weights = _w['fc1_weight'].copy()` and never reads it again, and "
        "the simulation loop drives the population with "
        "`np.zeros(lif1.n)  # TODO: real stimulus`. Every existing test for "
        "this target substring-matches the source, which is why a cell that "
        "raises on line one has stayed green."
    ),
)
def test_sc_neurocore_code_runs_and_uses_its_weights(tmp_path, monkeypatch) -> None:
    """The SC-NeuroCore cell must execute and fire under a driving weight matrix."""
    pytest.importorskip("sc_neurocore")

    strong = np.full((3, 4), 5.0, dtype=np.float32)
    code, weights = _generate_sc_neurocore_code(_feedforward_graph(strong))
    np.savez(tmp_path / "weights.npz", **weights)
    monkeypatch.chdir(tmp_path)

    namespace: dict[str, object] = {}
    exec(compile(code, "<generated-sc-neurocore>", "exec"), namespace)

    spike_times = namespace["t_arr_lif1"]
    assert len(spike_times) > 0, "SC-NeuroCore population never fired"
