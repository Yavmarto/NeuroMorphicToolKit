from __future__ import annotations

import time
from collections.abc import Callable
from typing import Any

from neurocnl.cnl.types import ParsedSentence
from neurocnl.training_registry import (
    AdapterCapability,
    BaseTrainingAdapter,
    ProgressCallback,
    TrainingAvailability,
    TrainingCategory,
    TrainingRequest,
    TrainingResult,
    UnavailableReason,
    UnavailableReasonCode,
)


class SleepPesAdapter(BaseTrainingAdapter):
    """Sleep PES training adapter — the first concrete training adapter."""

    capability = AdapterCapability(
        backend_name="sleep_pes",
        supported_training_modes=("offline_sleep",),
        default_training_mode="offline_sleep",
        output_format="weights",
        category=TrainingCategory.ON_DEVICE_LEARNING,
        description=(
            "Sleep-replay learning. The deployed device records sensory data "
            "during waking use; this offline phase replays it to update decoders."
        ),
    )

    def is_available(self) -> TrainingAvailability:
        try:
            import neurodreamhand  # noqa: F401

            return TrainingAvailability(available=True)
        except ImportError:
            return TrainingAvailability(
                available=False,
                unavailable_reason=UnavailableReason(
                    code=UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING,
                    message="neurodreamhand package is not installed. Install with: pip install neurodreamhand",
                    dependency_name="neurodreamhand",
                ),
            )

    def run(
        self,
        request: TrainingRequest,
        progress: ProgressCallback | None = None,
    ) -> TrainingResult:
        start = time.monotonic()
        payload = request.payload or {}
        training_mode = request.training_mode or self.capability.default_training_mode

        try:
            return self._run_with_runtime(
                payload,
                training_mode,
                start,
                progress,
            )
        except Exception as exc:
            return TrainingResult(
                adapter_name="sleep_pes",
                training_mode=training_mode,
                status="failed",
                error=str(exc),
                duration_seconds=time.monotonic() - start,
            )

    def _run_with_runtime(
        self,
        payload: dict[str, Any],
        training_mode: str,
        start: float,
        progress: ProgressCallback | None = None,
    ) -> TrainingResult:
        try:
            from neurodreamhand.learning.memory_buffer import MemoryBuffer
            from neurodreamhand.learning.sleep_pes import SleepOptimizer

            return self._run_real(
                SleepOptimizer,
                MemoryBuffer,
                payload,
                training_mode,
                start,
                progress,
            )
        except ImportError:
            return self._run_fallback(payload, training_mode, start)

    def _run_real(
        self,
        SleepOptimizer: type,
        MemoryBuffer: type,
        payload: dict[str, Any],
        training_mode: str,
        start: float,
        progress: ProgressCallback | None = None,
    ) -> TrainingResult:
        # Late import — pipeline may not exist in all environments
        parse_spec_text: Callable[[str], list[Any]] | None
        default_params_from_specs: (
            Callable[[list[ParsedSentence]], dict[str, Any]] | None
        )
        try:
            from neurocnl.pipeline import default_params_from_specs, parse_spec_text
        except ImportError:
            # Pipeline functions not available; use minimal defaults
            parse_spec_text = None
            default_params_from_specs = None

        spec = payload.get("spec", "")
        n_epochs = int(payload.get("n_epochs", 10))
        homeostasis_factor = float(payload.get("homeostasis_factor", 0.01))
        memory_buffer_data = payload.get("memory_buffer", [])

        n_neurons = 100
        if (
            parse_spec_text is not None
            and default_params_from_specs is not None
            and spec
        ):
            try:
                parsed: list[ParsedSentence] = [
                    r["parsed"]
                    for r in parse_spec_text(spec)
                    if r["valid"] and r["parsed"]
                ]
                params = default_params_from_specs(parsed) if parsed else {}
                n_neurons = int(params.get("population_n_neurons", 100))
            except Exception:
                pass  # Use default n_neurons

        optimizer = SleepOptimizer(
            homeostasis_factor=homeostasis_factor,
            n_neurons=n_neurons,
        )

        buffer = MemoryBuffer(capacity=max(len(memory_buffer_data), 1))
        for sample in memory_buffer_data:
            buffer.record(
                slip_vz=float(sample.get("slip_vz", 0.0)),
                grip=float(sample.get("grip", 0.0)),
                error=float(sample.get("error", 0.0)),
                mass=float(sample.get("mass", 0.0)),
            )

        if progress is not None:
            progress(
                {
                    "type": "phase",
                    "phase": "sleep_replay_started",
                    "n_epochs": n_epochs,
                    "elapsed_seconds": time.monotonic() - start,
                }
            )

        result = optimizer.train(buffer, n_epochs=n_epochs)

        loss_curve = getattr(result, "loss_curve", [])
        learned_weights = getattr(result, "learned_weights", [])
        n_epochs_actual = int(getattr(result, "n_epochs", n_epochs))
        final_loss = float(loss_curve[-1]) if len(loss_curve) > 0 else 0.0

        # Convert numpy arrays and ensure tuple for frozen dataclass
        loss_curve_tuple = tuple(float(v) for v in loss_curve)

        # neurodreamhand's SleepOptimizer.train() is a black box — it doesn't
        # invoke us per epoch. We replay the returned loss curve as epoch
        # events so subscribers get the same shape of stream as snntorch.
        # The timestamps are post-hoc; the UI just needs the values.
        if progress is not None and loss_curve_tuple:
            now = time.monotonic()
            for idx, loss_value in enumerate(loss_curve_tuple):
                progress(
                    {
                        "type": "epoch",
                        "epoch": idx + 1,
                        "total_epochs": len(loss_curve_tuple),
                        "loss": loss_value,
                        "elapsed_seconds": now - start,
                        "replayed": True,
                    }
                )
        if hasattr(learned_weights, "tolist"):
            learned_weights = learned_weights.tolist()

        return TrainingResult(
            adapter_name="sleep_pes",
            training_mode=training_mode,
            status="completed",
            n_epochs=n_epochs_actual,
            final_loss=final_loss,
            loss_curve=loss_curve_tuple,
            learned_weights=learned_weights,
            duration_seconds=time.monotonic() - start,
            metadata={
                "spec": spec,
                "n_epochs": n_epochs,
                "homeostasis_factor": homeostasis_factor,
            },
        )

    def _run_fallback(
        self,
        payload: dict[str, Any],
        training_mode: str,
        start: float,
        progress: ProgressCallback | None = None,
    ) -> TrainingResult:
        """Fail honestly when the neurodreamhand runtime is unavailable.

        Previously this returned a hardcoded "completed" result with a synthetic
        loss curve, which silently misled the UI into showing a successful run
        even though no training had occurred. We now surface the failure with
        the OPTIONAL_DEPENDENCY_MISSING reason so the UI can present a clear
        "install the runtime" message instead of a fake success.
        """
        payload = payload or {}
        n_epochs = int(payload.get("n_epochs", 10) or 10)
        error_message = (
            "neurodreamhand runtime is not importable. Sleep-PES training cannot "
            "proceed without the SleepOptimizer/MemoryBuffer submodules. "
            "Install with: pip install neurodreamhand"
        )

        return TrainingResult(
            adapter_name="sleep_pes",
            training_mode=training_mode,
            status="failed",
            error=error_message,
            duration_seconds=time.monotonic() - start,
            metadata={
                "n_epochs": n_epochs,
                "unavailable_reason_code": UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING.value,
                "dependency_name": "neurodreamhand",
            },
        )
