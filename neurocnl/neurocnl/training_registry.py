from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field, replace
from enum import StrEnum
from typing import Any

# A progress callback receives a free-form event dict (must be JSON-serialisable).
# By convention the dict has a ``type`` key — adapters emit ``"epoch"`` events
# during the training loop. ``None`` means "no listener attached, skip publishing".
ProgressCallback = Callable[[dict[str, Any]], None]


class AdapterSelectionError(ValueError):
    """Raised when an adapter cannot be selected or used honestly."""


class TrainingCategory(StrEnum):
    """Operational class of a training adapter.

    The two paths surface differently to users:

    * ``host_training`` runs on the developer's host (CPU/GPU). Best mental
      model: "learn from a dataset before you deploy." snnTorch goes here.
    * ``on_device_learning`` runs on (or against) the deployed target during a
      separate phase. Best mental model: "the device learns from its own
      experience while it sleeps." sleep_pes goes here.

    The UI groups capabilities by this category so a user looking at "Train"
    knows which world they are in.
    """

    HOST_TRAINING = "host_training"
    ON_DEVICE_LEARNING = "on_device_learning"


@dataclass(frozen=True, slots=True)
class AdapterCapability:
    backend_name: str
    supported_training_modes: tuple[str, ...]
    default_training_mode: str
    output_format: str | None = None
    # Operational category — `host_training` runs on the dev host before
    # deploy; `on_device_learning` runs against the deployed target. Defaults
    # to `host_training` because that is the safer assumption (no implied
    # hardware path) for any future adapter that forgets to set it.
    category: TrainingCategory = TrainingCategory.HOST_TRAINING
    # Short, user-facing one-liner explaining what this adapter does.
    # Surfaced in the capability picker so users can tell adapters apart
    # without reading source code.
    description: str = ""


@dataclass(frozen=True, slots=True)
class TrainingRequest:
    backend_name: str
    training_mode: str | None = None
    payload: dict[str, Any] | None = None
    # Serialized NIR graph (base64-encoded HDF5 bytes) produced by compiling
    # the CNL spec. When present, adapters should build the network topology
    # from this graph rather than using a hardcoded fallback.
    nir_graph: dict[str, Any] | None = None


class UnavailableReasonCode(StrEnum):
    OPTIONAL_DEPENDENCY_MISSING = "optional_dependency_missing"
    NOT_IMPLEMENTED = "not_implemented"
    HARDWARE_UNAVAILABLE = "hardware_unavailable"
    CONFIGURATION_INVALID = "configuration_invalid"
    PLATFORM_INCOMPATIBLE = "platform_incompatible"
    ADAPTER_ERROR = "adapter_error"


@dataclass(frozen=True, slots=True)
class UnavailableReason:
    code: UnavailableReasonCode
    message: str
    dependency_name: str | None = None


@dataclass(frozen=True, slots=True)
class TrainingAvailability:
    available: bool
    unavailable_reason: UnavailableReason | None = None


@dataclass(frozen=True, slots=True)
class TrainingResult:
    adapter_name: str
    training_mode: str
    status: str  # "completed" | "failed" | "partial"
    n_epochs: int | None = None
    final_loss: float | None = None
    loss_curve: tuple[float, ...] = ()
    learned_weights: object | None = None
    duration_seconds: float | None = None
    error: str | None = None
    metadata: dict[str, object] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class TrainingRunSummary:
    adapter_name: str
    training_mode: str
    status: str
    duration_seconds: float | None = None
    n_epochs: int | None = None
    final_loss: float | None = None
    message: str = ""


class BaseTrainingAdapter:
    capability: AdapterCapability

    def is_available(self) -> TrainingAvailability:
        """Return current runtime availability. Default: available."""
        return TrainingAvailability(available=True)

    def run(
        self,
        request: TrainingRequest,
        progress: ProgressCallback | None = None,
    ) -> TrainingResult:
        """Return a TrainingResult for this training run.

        ``progress`` is an optional callable adapters may invoke during the
        training loop to publish live events (epoch loss, spike samples, etc.)
        to whatever SSE subscriber is listening. It is safe to call from a
        worker thread — the bound publisher uses ``call_soon_threadsafe``
        internally. When ``None``, adapters must run silently (no streaming).
        """
        raise NotImplementedError


def _normalize_name(value: str, *, field_name: str) -> str:
    normalized = value.strip().lower()
    if not normalized:
        raise AdapterSelectionError(f"{field_name} cannot be empty after normalization.")
    return normalized


class TrainingAdapterRegistry:
    """Registry for selecting and validating training adapters by backend name."""

    def __init__(self, adapters: list[BaseTrainingAdapter]) -> None:
        self._adapters: dict[str, BaseTrainingAdapter] = {}

        for adapter in adapters:
            normalized_backend = _normalize_name(
                adapter.capability.backend_name,
                field_name="Backend name",
            )
            _normalize_name(
                adapter.capability.default_training_mode,
                field_name="Default training mode",
            )

            if normalized_backend in self._adapters:
                raise AdapterSelectionError(
                    f"Duplicate backend registration after normalization: {normalized_backend!r}."
                )

            self._adapters[normalized_backend] = adapter

    def list_capabilities(self) -> list[AdapterCapability]:
        return [
            adapter.capability
            for _, adapter in sorted(self._adapters.items(), key=lambda item: item[0])
        ]

    def get_adapter(self, backend_name: str) -> BaseTrainingAdapter:
        normalized_backend = _normalize_name(backend_name, field_name="Backend name")
        try:
            return self._adapters[normalized_backend]
        except KeyError as exc:
            raise AdapterSelectionError(f"Unknown backend: {backend_name!r}.") from exc

    def get_adapter_with_availability(
        self, backend_name: str
    ) -> tuple[BaseTrainingAdapter, TrainingAvailability]:
        adapter = self.get_adapter(backend_name)
        return adapter, adapter.is_available()

    def get_available_adapters(
        self,
    ) -> list[tuple[AdapterCapability, TrainingAvailability]]:
        return [
            (adapter.capability, adapter.is_available())
            for _, adapter in sorted(self._adapters.items(), key=lambda item: item[0])
        ]

    def resolve_mode(self, adapter: BaseTrainingAdapter, training_mode: str | None) -> str:
        default_mode = _normalize_name(
            adapter.capability.default_training_mode,
            field_name="Default training mode",
        )
        if training_mode is None:
            return default_mode

        normalized_mode = _normalize_name(training_mode, field_name="Training mode")
        supported_modes = {
            _normalize_name(mode, field_name="Supported training mode")
            for mode in adapter.capability.supported_training_modes
        }
        if normalized_mode not in supported_modes:
            raise AdapterSelectionError(
                "Backend "
                f"{adapter.capability.backend_name!r} does not support training mode "
                f"{training_mode!r}."
            )

        return normalized_mode

    def dispatch(self, request: TrainingRequest) -> TrainingResult:
        adapter = self.get_adapter(request.backend_name)
        availability = adapter.is_available()
        if not availability.available:
            reason = availability.unavailable_reason
            raise AdapterSelectionError(
                f"Backend {request.backend_name!r} is not available: "
                f"{reason.message if reason else 'unknown reason'}"
            )
        resolved_mode = self.resolve_mode(adapter, request.training_mode)
        resolved_request = replace(request, training_mode=resolved_mode)
        return adapter.run(resolved_request)
