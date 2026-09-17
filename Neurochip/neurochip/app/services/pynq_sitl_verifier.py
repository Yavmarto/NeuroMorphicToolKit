"""Neurochip PYNQ SITL Verification Service.

Reuses Dream-Hand's SITL co-simulation pattern to verify a deployed PYNQ
artifact using the in-process ``PYNQBackend``/``PynqSimulator``.

Feed known stimuli (as spike vectors) through a deployed backend, compare
output spikes against expected values, and surface timing/correctness signals.

Usage::

    from neurochip.app.services.pynq_sitl_verifier import (
        SITLStimulusCase,
        SITLVerificationConfig,
        run_sitl_verification,
    )
    from neurochip.app.services.pynq_backend import PYNQBackend

    backend = PYNQBackend(bitstream_path="snn_overlay.bit")
    backend.load_overlay()
    backend.configure(weights=[2.0, 0.5], config={"threshold": 1.0})

    report = run_sitl_verification(
        backend,
        SITLVerificationConfig(stimulus_cases=[
            SITLStimulusCase(label="fire", input_spikes=[0], expected_output_spikes=[0]),
        ]),
    )
    assert report.passed
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import Any

from neurochip.app.services.pynq_backend import PYNQBackend

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Default canonical stimulus cases (mirrors Dream-Hand SITL defaults)
# ---------------------------------------------------------------------------

# Default stimulus is generated from the configured network's input width.
# Overlay-v1's fixed list ([0], [0, 1], [9], ...) read as spike *indices*; under
# the v2 stream protocol an input frame is one word per input neuron, so a
# fixed list is either the wrong length or silently means something else.


# ---------------------------------------------------------------------------
# Dataclasses
# ---------------------------------------------------------------------------


@dataclass
class SITLStimulusCase:
    """A single SITL verification stimulus for Neurochip.

    Parameters
    ----------
    label:
        Human-readable name for the case.
    input_spikes:
        Spike indices to inject (maps to ``RunRequest.input_spikes``).
    expected_output_spikes:
        Optional list of expected output neuron indices.  When *None* the
        step always passes (timing signal only).
    timesteps:
        Number of simulation timesteps per step.  Defaults to ``1``.
    """

    label: str
    input_spikes: list[int]
    expected_output_spikes: list[int] | None = None
    timesteps: int = 1


@dataclass
class SITLStepResult:
    """Result of a single SITL stimulus step.

    Parameters
    ----------
    label:
        Case label.
    input_spikes:
        Input spike indices used.
    output_spikes:
        Output spike indices returned by the backend.
    expected_output_spikes:
        Expected output, or *None* if not specified.
    passed:
        ``True`` when no expected value was given *or* the actual output
        matches the expected set exactly.
    execution_time_us:
        Wall-clock time for the backend ``run()`` call in microseconds.
    """

    label: str
    input_spikes: list[int]
    output_spikes: list[int]
    expected_output_spikes: list[int] | None
    passed: bool
    execution_time_us: float


@dataclass
class SITLVerificationConfig:
    """Configuration for a Neurochip PYNQ SITL verification run.

    Parameters
    ----------
    stimulus_cases:
        Override the default canonical cases.  When *None* a built-in set of
        five cases derived from the Dream-Hand SITL pattern is used.
    """

    stimulus_cases: list[SITLStimulusCase] | None = None


@dataclass
class SITLVerificationReport:
    """Aggregated result of a Neurochip PYNQ SITL verification run.

    Parameters
    ----------
    passed:
        ``True`` when all cases with expected values passed.
    total_cases:
        Number of stimulus cases executed.
    passed_cases:
        Number of cases that passed.
    mean_exec_us:
        Mean per-step wall-clock time in microseconds.
    max_exec_us:
        Maximum per-step wall-clock time in microseconds.
    steps:
        Detailed per-step results.
    summary:
        Human-readable one-line status.
    """

    passed: bool
    total_cases: int
    passed_cases: int
    mean_exec_us: float
    max_exec_us: float
    steps: list[SITLStepResult]
    summary: str

    def to_dict(self) -> dict[str, Any]:
        """Serialise to a plain dict for JSON responses."""
        return {
            "passed": self.passed,
            "total_cases": self.total_cases,
            "passed_cases": self.passed_cases,
            "mean_exec_us": self.mean_exec_us,
            "max_exec_us": self.max_exec_us,
            "summary": self.summary,
            "steps": [
                {
                    "label": s.label,
                    "input_spikes": s.input_spikes,
                    "output_spikes": s.output_spikes,
                    "expected_output_spikes": s.expected_output_spikes,
                    "passed": s.passed,
                    "execution_time_us": s.execution_time_us,
                }
                for s in self.steps
            ],
        }


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def run_sitl_verification(
    backend: PYNQBackend,
    cfg: SITLVerificationConfig | None = None,
) -> SITLVerificationReport:
    """Run a SITL verification pass against an already-configured ``PYNQBackend``.

    The backend must be in the ``configured`` state (i.e. ``load_overlay()``
    and ``configure()`` have already been called).

    Parameters
    ----------
    backend:
        A configured ``PYNQBackend`` instance.
    cfg:
        Verification config with optional custom stimulus cases.
        When *None* the default canonical cases are used.

    Returns
    -------
    SITLVerificationReport
        Full structured result with per-step details and aggregate timing.

    Raises
    ------
    RuntimeError
        If the backend is not yet configured.
    """
    if backend.current_state not in ("configured", "running"):
        raise RuntimeError(
            f"Backend must be configured before verification; "
            f"current state: {backend.current_state!r}"
        )

    if cfg is None:
        cfg = SITLVerificationConfig()

    cases = cfg.stimulus_cases or _build_default_cases(_backend_input_size(backend))
    steps: list[SITLStepResult] = []

    for case in cases:
        t0 = time.perf_counter()
        result = backend.run(
            input_spikes=case.input_spikes,
            timesteps=case.timesteps,
        )
        exec_us = (time.perf_counter() - t0) * 1_000_000

        output_spikes: list[int] = result.get("output_spikes", [])

        if case.expected_output_spikes is None:
            passed = True
        else:
            passed = sorted(output_spikes) == sorted(case.expected_output_spikes)

        steps.append(
            SITLStepResult(
                label=case.label,
                input_spikes=case.input_spikes,
                output_spikes=output_spikes,
                expected_output_spikes=case.expected_output_spikes,
                passed=passed,
                execution_time_us=exec_us,
            )
        )
        logger.debug(
            "SITL step %s: out=%s passed=%s (%.1f µs)",
            case.label,
            output_spikes,
            passed,
            exec_us,
        )

    passed_count = sum(1 for s in steps if s.passed)
    all_passed = passed_count == len(steps)
    exec_times = [s.execution_time_us for s in steps]
    mean_us = sum(exec_times) / len(exec_times) if exec_times else 0.0
    max_us = max(exec_times) if exec_times else 0.0

    summary = (
        f"SITL {'PASS' if all_passed else 'FAIL'}: "
        f"{passed_count}/{len(steps)} cases passed, "
        f"mean={mean_us:.1f} µs, max={max_us:.1f} µs"
    )
    logger.info(summary)

    return SITLVerificationReport(
        passed=all_passed,
        total_cases=len(steps),
        passed_cases=passed_count,
        mean_exec_us=mean_us,
        max_exec_us=max_us,
        steps=steps,
        summary=summary,
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _backend_input_size(backend: Any) -> int:
    """Return the configured network's input width, or 1 if it is unknown."""
    for source in (backend, getattr(backend, "_simulator", None)):
        layers = getattr(source, "_configured_layers", None) or getattr(source, "layers", None)
        if layers:
            return max(1, int(layers[0].get("input_size", 0)))
    return 1


def _build_default_cases(input_size: int) -> list[SITLStimulusCase]:
    """Return stimulus cases shaped to the configured network.

    Each case is a whole input frame — one word per input neuron per timestep —
    because that is what the engine consumes. These probe liveness and latency,
    not accuracy: none of them carries an expected output, so a green run means
    the board answered, not that it answered correctly.
    """
    silent = [0] * input_size
    first = [1] + [0] * (input_size - 1)
    last = [0] * (input_size - 1) + [1]
    every = [1] * input_size

    return [
        SITLStimulusCase(label="silent", input_spikes=silent),
        SITLStimulusCase(label="first_neuron", input_spikes=first),
        SITLStimulusCase(label="last_neuron", input_spikes=last),
        SITLStimulusCase(label="all_neurons", input_spikes=every),
        SITLStimulusCase(label="burst", input_spikes=every + every + silent, timesteps=3),
    ]
