from __future__ import annotations

from typing import Any

import pytest

from neurocnl.training.dataset_fixtures import build_nmnist_fixture
from neurocnl.training_registry import (
    AdapterCapability,
    AdapterSelectionError,
    BaseTrainingAdapter,
    TrainingAdapterRegistry,
    TrainingAvailability,
    TrainingRequest,
    TrainingResult,
    TrainingRunSummary,
    UnavailableReason,
    UnavailableReasonCode,
)


class AdapterA(BaseTrainingAdapter):
    capability = AdapterCapability(
        backend_name=" Framework-B ",
        supported_training_modes=("surrogate",),
        default_training_mode="surrogate",
        output_format="graph",
    )

    def run(self, request: TrainingRequest, progress: Any = None) -> TrainingResult:
        return TrainingResult(
            adapter_name="framework-b",
            training_mode=request.training_mode
            or self.capability.default_training_mode,
            status="completed",
            metadata={"payload": request.payload},
        )


class AdapterB(BaseTrainingAdapter):
    capability = AdapterCapability(
        backend_name="framework-a",
        supported_training_modes=("ann_to_snn", "surrogate"),
        default_training_mode=" ANN_TO_SNN ",
        output_format="graph",
    )

    def run(self, request: TrainingRequest, progress: Any = None) -> TrainingResult:
        return TrainingResult(
            adapter_name="framework-a",
            training_mode=request.training_mode
            or self.capability.default_training_mode,
            status="completed",
            metadata={"payload": request.payload},
        )


class DuplicateAdapter(BaseTrainingAdapter):
    capability = AdapterCapability(
        backend_name=" FRAMEWORK-A ",
        supported_training_modes=("surrogate",),
        default_training_mode="surrogate",
    )

    def run(self, request: TrainingRequest, progress: Any = None) -> TrainingResult:
        return TrainingResult(
            adapter_name="framework-a",
            training_mode=request.training_mode
            or self.capability.default_training_mode,
            status="completed",
        )


def test_list_capabilities_sorts_by_normalized_backend_name() -> None:
    registry = TrainingAdapterRegistry([AdapterA(), AdapterB()])

    capabilities = registry.list_capabilities()

    assert [cap.backend_name for cap in capabilities] == [
        "framework-a",
        " Framework-B ",
    ]


def test_get_adapter_is_case_insensitive() -> None:
    registry = TrainingAdapterRegistry([AdapterA(), AdapterB()])

    adapter = registry.get_adapter("  FRAMEWORK-A ")

    assert adapter.capability.backend_name == "framework-a"


def test_dispatch_uses_normalized_default_mode() -> None:
    registry = TrainingAdapterRegistry([AdapterA(), AdapterB()])

    result = registry.dispatch(TrainingRequest(backend_name="framework-a"))

    assert isinstance(result, TrainingResult)
    assert result.adapter_name == "framework-a"
    assert result.training_mode == "ann_to_snn"
    assert result.metadata.get("payload") is None


def test_dispatch_rejects_unsupported_mode() -> None:
    registry = TrainingAdapterRegistry([AdapterA(), AdapterB()])

    with pytest.raises(AdapterSelectionError, match="does not support training mode"):
        registry.dispatch(
            TrainingRequest(
                backend_name="framework-b",
                training_mode="ann_to_snn",
            )
        )


def test_duplicate_registration_fails_closed() -> None:
    with pytest.raises(AdapterSelectionError, match="Duplicate backend registration"):
        TrainingAdapterRegistry([AdapterB(), DuplicateAdapter()])


def test_explicit_blank_mode_is_rejected() -> None:
    registry = TrainingAdapterRegistry([AdapterA(), AdapterB()])

    with pytest.raises(AdapterSelectionError, match="Training mode cannot be empty"):
        registry.dispatch(
            TrainingRequest(backend_name="framework-a", training_mode="   ")
        )


def test_unknown_backend_is_rejected() -> None:
    registry = TrainingAdapterRegistry([AdapterA(), AdapterB()])

    with pytest.raises(AdapterSelectionError, match="Unknown backend"):
        registry.get_adapter("missing-backend")


def test_payload_passes_through_untouched() -> None:
    registry = TrainingAdapterRegistry([AdapterA(), AdapterB()])
    payload = {"epochs": 5}

    result = registry.dispatch(
        TrainingRequest(
            backend_name=" framework-b ",
            training_mode=" SURROGATE ",
            payload=payload,
        )
    )

    assert isinstance(result, TrainingResult)
    assert result.adapter_name == "framework-b"
    assert result.training_mode == "surrogate"
    assert result.metadata.get("payload") == payload


# New tests for the training domain model


def test_training_result_is_frozen() -> None:
    result = TrainingResult(
        adapter_name="test",
        training_mode="surrogate",
        status="completed",
    )

    with pytest.raises(AttributeError):
        result.status = "failed"  # type: ignore[misc]


def test_training_result_fields() -> None:
    result = TrainingResult(
        adapter_name="test",
        training_mode="surrogate",
        status="completed",
    )

    assert result.adapter_name == "test"
    assert result.training_mode == "surrogate"
    assert result.status == "completed"
    assert result.n_epochs is None
    assert result.final_loss is None
    assert result.loss_curve == ()
    assert result.learned_weights is None
    assert result.duration_seconds is None
    assert result.error is None
    assert result.metadata == {}


def test_unavailable_reason_code_values() -> None:
    assert (
        UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING.value
        == "optional_dependency_missing"
    )
    assert UnavailableReasonCode.NOT_IMPLEMENTED.value == "not_implemented"
    assert UnavailableReasonCode.HARDWARE_UNAVAILABLE.value == "hardware_unavailable"
    assert UnavailableReasonCode.CONFIGURATION_INVALID.value == "configuration_invalid"
    assert UnavailableReasonCode.PLATFORM_INCOMPATIBLE.value == "platform_incompatible"
    assert UnavailableReasonCode.ADAPTER_ERROR.value == "adapter_error"


def test_training_available_adapter() -> None:
    class AvailableAdapter(BaseTrainingAdapter):
        capability = AdapterCapability(
            backend_name="available-adapter",
            supported_training_modes=("surrogate",),
            default_training_mode="surrogate",
        )

        def is_available(self) -> TrainingAvailability:
            return TrainingAvailability(available=True)

        def run(self, request: TrainingRequest, progress: Any = None) -> TrainingResult:
            return TrainingResult(
                adapter_name="available-adapter",
                training_mode=request.training_mode
                or self.capability.default_training_mode,
                status="completed",
            )

    registry = TrainingAdapterRegistry([AvailableAdapter()])
    result = registry.dispatch(TrainingRequest(backend_name="available-adapter"))

    assert isinstance(result, TrainingResult)
    assert result.status == "completed"


def test_training_unavailable_adapter_raises() -> None:
    class UnavailableAdapter(BaseTrainingAdapter):
        capability = AdapterCapability(
            backend_name="unavailable-adapter",
            supported_training_modes=("surrogate",),
            default_training_mode="surrogate",
        )

        def is_available(self) -> TrainingAvailability:
            return TrainingAvailability(
                available=False,
                unavailable_reason=UnavailableReason(
                    code=UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING,
                    message="Required package 'xyz' not installed",
                ),
            )

        def run(self, request: TrainingRequest, progress: Any = None) -> TrainingResult:
            return TrainingResult(
                adapter_name="unavailable-adapter",
                training_mode=request.training_mode
                or self.capability.default_training_mode,
                status="failed",
                error="Should not reach here",
            )

    registry = TrainingAdapterRegistry([UnavailableAdapter()])

    with pytest.raises(
        AdapterSelectionError, match="unavailable-adapter.*not available"
    ):
        registry.dispatch(TrainingRequest(backend_name="unavailable-adapter"))


def test_unavailable_reason_with_dependency_name() -> None:
    reason = UnavailableReason(
        code=UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING,
        message="Missing optional dependency",
        dependency_name="specialized-lib",
    )

    assert reason.code == UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING
    assert reason.message == "Missing optional dependency"
    assert reason.dependency_name == "specialized-lib"


def test_get_available_adapters() -> None:
    class AvailableAdapter(BaseTrainingAdapter):
        capability = AdapterCapability(
            backend_name="available",
            supported_training_modes=("surrogate",),
            default_training_mode="surrogate",
        )

        def is_available(self) -> TrainingAvailability:
            return TrainingAvailability(available=True)

        def run(self, request: TrainingRequest, progress: Any = None) -> TrainingResult:
            raise NotImplementedError

    class UnavailableAdapter(BaseTrainingAdapter):
        capability = AdapterCapability(
            backend_name="unavailable",
            supported_training_modes=("surrogate",),
            default_training_mode="surrogate",
        )

        def is_available(self) -> TrainingAvailability:
            return TrainingAvailability(
                available=False,
                unavailable_reason=UnavailableReason(
                    code=UnavailableReasonCode.NOT_IMPLEMENTED,
                    message="Not implemented yet",
                ),
            )

        def run(self, request: TrainingRequest, progress: Any = None) -> TrainingResult:
            raise NotImplementedError

    registry = TrainingAdapterRegistry([UnavailableAdapter(), AvailableAdapter()])
    results = registry.get_available_adapters()

    assert len(results) == 2
    caps, avail = results[0]
    assert caps.backend_name == "available"
    assert avail.available is True

    caps, avail = results[1]
    assert caps.backend_name == "unavailable"
    assert avail.available is False


def test_get_adapter_with_availability() -> None:
    class TestAdapter(BaseTrainingAdapter):
        capability = AdapterCapability(
            backend_name="test-adapter",
            supported_training_modes=("surrogate",),
            default_training_mode="surrogate",
        )

        def is_available(self) -> TrainingAvailability:
            return TrainingAvailability(
                available=True,
                unavailable_reason=None,
            )

        def run(self, request: TrainingRequest, progress: Any = None) -> TrainingResult:
            raise NotImplementedError

    registry = TrainingAdapterRegistry([TestAdapter()])
    adapter, availability = registry.get_adapter_with_availability("test-adapter")

    assert adapter.capability.backend_name == "test-adapter"
    assert isinstance(availability, TrainingAvailability)
    assert availability.available is True
    assert availability.unavailable_reason is None


def test_run_summary_from_result() -> None:
    result = TrainingResult(
        adapter_name="test-adapter",
        training_mode="surrogate",
        status="completed",
        n_epochs=100,
        final_loss=0.001,
        duration_seconds=120.5,
        loss_curve=(0.5, 0.3, 0.1, 0.01, 0.001),
    )

    summary = TrainingRunSummary(
        adapter_name=result.adapter_name,
        training_mode=result.training_mode,
        status=result.status,
        duration_seconds=result.duration_seconds,
        n_epochs=result.n_epochs,
        final_loss=result.final_loss,
        message="Training completed successfully",
    )

    assert summary.adapter_name == "test-adapter"
    assert summary.training_mode == "surrogate"
    assert summary.status == "completed"
    assert summary.n_epochs == 100
    assert summary.final_loss == 0.001
    assert summary.duration_seconds == 120.5
    assert summary.message == "Training completed successfully"


def test_dispatch_returns_training_result() -> None:
    registry = TrainingAdapterRegistry([AdapterA(), AdapterB()])

    result = registry.dispatch(
        TrainingRequest(
            backend_name="framework-a",
            training_mode="surrogate",
        )
    )

    assert isinstance(result, TrainingResult)
    assert hasattr(result, "adapter_name")
    assert hasattr(result, "training_mode")
    assert hasattr(result, "status")
    assert hasattr(result, "metadata")


# --- Sleep PES adapter tests ---


def test_sleep_pes_adapter_capability() -> None:
    from neurocnl.training.sleep_pes_adapter import SleepPesAdapter

    adapter = SleepPesAdapter()
    assert adapter.capability.backend_name == "sleep_pes"
    assert adapter.capability.supported_training_modes == ("offline_sleep",)
    assert adapter.capability.default_training_mode == "offline_sleep"


def test_sleep_pes_adapter_is_available_returns_structured() -> None:
    from neurocnl.training.sleep_pes_adapter import SleepPesAdapter

    adapter = SleepPesAdapter()
    availability = adapter.is_available()
    assert isinstance(availability, TrainingAvailability)
    # Either available=True (neurodreamhand installed) or available=False with reason
    if not availability.available:
        assert availability.unavailable_reason is not None
        assert (
            availability.unavailable_reason.code
            == UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING
        )
        assert availability.unavailable_reason.dependency_name == "neurodreamhand"


def test_sleep_pes_adapter_fallback_run() -> None:
    """When neurodreamhand is unavailable the adapter must fail honestly.

    Previously this returned a fake completed result with a hardcoded loss curve,
    which silently misled the UI into showing 'training complete'. The contract
    now is: status='failed' with a clear error and the
    OPTIONAL_DEPENDENCY_MISSING reason surfaced through metadata.
    """
    from neurocnl.training.sleep_pes_adapter import SleepPesAdapter

    adapter = SleepPesAdapter()
    result = adapter._run_fallback(
        payload={"n_epochs": 5},
        training_mode="offline_sleep",
        start=0.0,
    )
    assert isinstance(result, TrainingResult)
    assert result.adapter_name == "sleep_pes"
    assert result.training_mode == "offline_sleep"
    assert result.status == "failed"
    assert result.error is not None and "neurodreamhand" in result.error.lower()
    # No fake numerics
    assert result.final_loss is None
    assert result.loss_curve == ()
    assert result.learned_weights is None
    # Surface the unavailability reason in metadata for UI consumption
    assert (
        result.metadata.get("unavailable_reason_code")
        == UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING.value
    )
    assert result.metadata.get("dependency_name") == "neurodreamhand"


def test_sleep_pes_adapter_in_registry() -> None:
    """SleepPesAdapter can be registered and dispatched."""
    from neurocnl.training.sleep_pes_adapter import SleepPesAdapter

    adapter = SleepPesAdapter()
    registry = TrainingAdapterRegistry([adapter])
    caps = registry.list_capabilities()
    assert len(caps) == 1
    assert caps[0].backend_name == "sleep_pes"


def test_sleep_pes_adapter_dispatch_unavailable_raises() -> None:
    """When neurodreamhand is missing, dispatch raises AdapterSelectionError."""
    from unittest.mock import patch

    from neurocnl.training.sleep_pes_adapter import SleepPesAdapter

    adapter = SleepPesAdapter()
    registry = TrainingAdapterRegistry([adapter])

    with (
        patch.object(
            adapter,
            "is_available",
            return_value=TrainingAvailability(
                available=False,
                unavailable_reason=UnavailableReason(
                    code=UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING,
                    message="neurodreamhand not installed",
                    dependency_name="neurodreamhand",
                ),
            ),
        ),
        pytest.raises(AdapterSelectionError, match="not available"),
    ):
        registry.dispatch(TrainingRequest(backend_name="sleep_pes"))


def test_sleep_pes_adapter_run_handles_none_payload() -> None:
    """Adapter handles TrainingRequest with payload=None gracefully via public run()."""
    from unittest.mock import patch

    from neurocnl.training.sleep_pes_adapter import SleepPesAdapter

    adapter = SleepPesAdapter()

    # Force fallback path (neurodreamhand unavailable) so run() uses _run_fallback
    with patch.object(
        adapter,
        "_run_with_runtime",
        side_effect=lambda *a, **kw: adapter._run_fallback(*a, **kw),
    ):
        result = adapter.run(
            TrainingRequest(
                backend_name="sleep_pes",
                training_mode="offline_sleep",
                payload=None,
            )
        )
    # The fallback now fails honestly rather than fabricating a success.
    assert result.status == "failed"
    assert result.metadata.get("dependency_name") == "neurodreamhand"


def test_nmnist_fixture_is_deterministic() -> None:
    fixture = build_nmnist_fixture(num_samples=4, timesteps=6, input_size=4)

    assert fixture.name == "n-mnist"
    assert fixture.synthetic is True
    assert len(fixture.samples) == 4
    assert len(fixture.samples[0]) == 6
    assert len(fixture.samples[0][0]) == 4
    assert fixture.labels == [0, 1, 0, 1]


def test_fit_dispatches_through_shared_registry(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from neurocnl.training_api import fit

    dispatched: dict[str, object] = {}

    class RecordingRegistry:
        def dispatch(self, request: TrainingRequest) -> TrainingResult:
            dispatched["backend_name"] = request.backend_name
            dispatched["training_mode"] = request.training_mode
            dispatched["payload"] = request.payload
            return TrainingResult(
                adapter_name="snntorch",
                training_mode="surrogate",
                status="completed",
            )

    monkeypatch.setattr(
        "neurocnl.training_api.build_training_registry",
        lambda: RecordingRegistry(),
    )

    result = fit(
        "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
        payload={"n_epochs": 2},
    )

    assert result.adapter_name == "snntorch"
    assert dispatched["backend_name"] == "snntorch"
    assert dispatched["training_mode"] is None
    assert dispatched["payload"] == {
        "spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
        "dataset": "n-mnist",
        "n_epochs": 2,
    }
