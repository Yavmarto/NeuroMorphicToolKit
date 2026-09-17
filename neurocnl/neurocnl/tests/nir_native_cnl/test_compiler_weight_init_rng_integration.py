"""RNG-isolation and end-to-end integration tests for weight initialisation.

Split from ``test_compiler_weight_init.py``: covers per-call RNG isolation
across repeated/concurrent compiles, and full CNL-to-simulator integration
checks that Xavier-initialised weights actually drive downstream spiking
activity while zero weights do not.
"""

from __future__ import annotations

import threading
from typing import Any

import numpy as np
import pytest

from ._weight_init_helpers import compile_linear, legacy_rng_state, make_linear_record

# ---------------------------------------------------------------------------
# TestRNGIsolation
# ---------------------------------------------------------------------------


class TestRNGIsolation:
    """Tests for Requirements 1.3, 7.2, 7.3, 7.4: RNG isolation and side-effect freedom.

    The compiler SHALL use an isolated ``numpy.random.default_rng`` per call
    and SHALL NOT mutate the legacy ``numpy.random`` module-level state.
    Concurrent compilations with the same seed SHALL produce identical results.
    """

    def test_global_numpy_state_unchanged_xavier(self) -> None:
        """Compiling a xavier-initialised weight does not mutate global numpy RNG state.

        Snapshots ``np.random.get_state()`` before and after compilation and
        asserts both the algorithm name string and the state array are identical.

        _Validates: Requirement 7.3_
        """
        record = make_linear_record(8, 8, weight_init="xavier", seed=42)

        state_before = legacy_rng_state()
        compile_linear(record)
        state_after = legacy_rng_state()

        # Compare algorithm name (state_before[0] is the PRNG name string)
        assert state_before[0] == state_after[0], (
            f"Global numpy RNG algorithm name changed after xavier compile: "
            f"{state_before[0]!r} → {state_after[0]!r}"
        )
        # Compare state array (state_before[1] is the uint32 state vector)
        assert np.array_equal(
            state_before[1], state_after[1]
        ), "Global numpy RNG state array was mutated after xavier compile"

    def test_global_numpy_state_unchanged_kaiming(self) -> None:
        """Compiling a kaiming-initialised weight does not mutate global numpy RNG state.

        Snapshots ``np.random.get_state()`` before and after compilation and
        asserts both the algorithm name string and the state array are identical.

        _Validates: Requirement 7.3_
        """
        record = make_linear_record(8, 8, weight_init="kaiming", seed=99)

        state_before = legacy_rng_state()
        compile_linear(record)
        state_after = legacy_rng_state()

        # Compare algorithm name
        assert state_before[0] == state_after[0], (
            f"Global numpy RNG algorithm name changed after kaiming compile: "
            f"{state_before[0]!r} → {state_after[0]!r}"
        )
        # Compare state array
        assert np.array_equal(
            state_before[1], state_after[1]
        ), "Global numpy RNG state array was mutated after kaiming compile"

    def test_concurrent_same_seed(self) -> None:
        """Two threads compiling the same record concurrently produce identical arrays.

        Spawns two threads, each compiling the same ``NIRNodeRecord`` with the
        same seed. After both threads complete, asserts
        ``numpy.array_equal(results[0], results[1])``.

        _Validates: Requirement 7.4_
        """
        results: list[np.ndarray[Any, Any] | None] = [None, None]

        def _compile_thread(index: int) -> None:
            # Each thread builds its own record (same parameters, same seed)
            record = make_linear_record(16, 16, weight_init="xavier", seed=7)
            results[index] = compile_linear(record)

        t0 = threading.Thread(target=_compile_thread, args=(0,))
        t1 = threading.Thread(target=_compile_thread, args=(1,))

        t0.start()
        t1.start()

        t0.join()
        t1.join()

        assert results[0] is not None, "Thread 0 did not produce a result"
        assert results[1] is not None, "Thread 1 did not produce a result"

        assert np.array_equal(results[0], results[1]), (
            "Concurrent compilations with the same seed produced different arrays.\n"
            f"  results[0][:2, :2] = {results[0][:2, :2]}\n"
            f"  results[1][:2, :2] = {results[1][:2, :2]}"
        )


# ---------------------------------------------------------------------------
# TestKaimingInitialisation
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# TestIntegrationSnnTorchActivity
# ---------------------------------------------------------------------------


class TestIntegrationSnnTorchActivity:
    """End-to-end integration tests for Requirement 8: non-zero downstream activity.

    These tests compile a minimal CNL topology (Input(4) → Linear(4×4) → LIF)
    via ``compile_to_nir``, then run the snnTorch simulator and assert spike
    map contents.

    The class is guarded with ``pytest.importorskip("snntorch")`` at the
    method level so that the tests are **skipped** rather than failing when
    snnTorch (and torch) are not installed in the test environment.

    Requirement references: 8.1, 8.2
    """

    # ── CNL spec helpers ─────────────────────────────────────────────────

    # The network declares its own timestep so it is well scaled. tau is in
    # seconds, and the simulator's firing threshold is divided by the input
    # gain r*dt/tau (see neurocnl.lif_semantics). Left undeclared, dt defaults
    # to 1e-4 s, which turns a nominal threshold of 1.0 into an effective 200 —
    # unreachable for a 4x4 Xavier layer, and exactly the condition
    # _implausible_lif_thresholds warns about. dt/tau = 0.1 here.
    _XAVIER_SPEC = """\
Define a network named weight_init_test with timestep 0.002.
Define an input port named input with shape (4,).
Define a linear transformation named lin1 with weight matrix shape (4, 4) \
annotated with metadata weight_init equal to "xavier" \
annotated with metadata seed equal to 1.
Define a LIF neuron named lif1 with time constant 0.02, \
resistance 1.0, leak voltage 0.0, and firing threshold 0.1.
Define an output port named output with shape (4,).
input connects to lin1.
lin1 connects to lif1.
lif1 connects to output.
"""

    _ZERO_SPEC = """\
Define a network named weight_init_test_zero.
Define an input port named input with shape (4,).
Define a linear transformation named lin1 with weight matrix shape (4, 4).
Define a LIF neuron named lif1 with time constant 0.02, \
resistance 1.0, leak voltage 0.0, and firing threshold 1.0.
Define an output port named output with shape (4,).
input connects to lin1.
lin1 connects to lif1.
lif1 connects to output.
"""

    def test_xavier_weights_produce_nonzero_spikes(self) -> None:
        """Xavier-initialised weights produce at least one spike in the LIF node.

        Compiles ``Input(4) → Linear(4×4, xavier, seed=1) → LIF`` via
        ``compile_to_nir``, then runs the snnTorch simulator with
        ``timesteps=100, firing_rate=0.3, seed=1``, and asserts the spike
        map for the LIF node (``"lif1"``) is non-empty.

        _Validates: Requirement 8.1_
        """
        pytest.importorskip("snntorch")

        from neurocnl.compile import compile_to_nir
        from neurocnl.runtime.snntorch_simulator import SnnTorchSimulatorAdapter
        from neurocnl.runtime.stimulus import generate_default_stimulus

        graph = compile_to_nir(self._XAVIER_SPEC)
        stimulus = generate_default_stimulus(
            graph, timesteps=100, firing_rate=0.3, seed=1
        )
        result = SnnTorchSimulatorAdapter().run(graph, stimulus, timesteps=100, seed=1)

        lif_spikes = result.spikes.get("lif1", {})
        assert lif_spikes, (
            "Expected at least one spike in the 'lif1' LIF node with Xavier-initialised "
            f"weights, but got an empty spike map.\n"
            f"Simulator warnings: {result.warnings}"
        )

    def test_zero_weights_produce_empty_spikes(self) -> None:
        """Zero weights (no weight_init) produce no spikes in the LIF node.

        Compiles the same ``Input(4) → Linear(4×4) → LIF`` topology without
        any ``weight_init`` annotation (weights default to all-zero matrices),
        runs with identical stimuli, and asserts the spike map for ``"lif1"``
        is empty.

        _Validates: Requirement 8.2_
        """
        pytest.importorskip("snntorch")

        from neurocnl.compile import compile_to_nir
        from neurocnl.runtime.snntorch_simulator import SnnTorchSimulatorAdapter
        from neurocnl.runtime.stimulus import generate_default_stimulus

        graph = compile_to_nir(self._ZERO_SPEC)
        stimulus = generate_default_stimulus(
            graph, timesteps=100, firing_rate=0.3, seed=1
        )
        result = SnnTorchSimulatorAdapter().run(graph, stimulus, timesteps=100, seed=1)

        lif_spikes = result.spikes.get("lif1", {})
        assert not lif_spikes, (
            "Expected an empty spike map for 'lif1' with zero weights, "
            f"but got non-empty spikes: {lif_spikes}"
        )
