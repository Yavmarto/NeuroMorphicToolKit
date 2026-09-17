"""Structured Speck runtime errors for the Neurochip Speck backend."""

from __future__ import annotations


class SpeckRuntimeError(RuntimeError):
    """Base class for all Speck runtime errors."""

    error_code: str = "SPECK_RUNTIME_ERROR"

    def __init__(self, message: str, *, error_code: str | None = None) -> None:
        if error_code is not None:
            self.error_code = error_code
        super().__init__(message)


class SpeckSdkNotAvailableError(SpeckRuntimeError):
    """Raised when the SynSense Speck SDK (samna/sinabs) is not installed."""

    error_code: str = "SDK_NOT_AVAILABLE"


class SpeckModelConstructionError(SpeckRuntimeError):
    """Raised when building a Speck model from a mapped network fails."""

    error_code: str = "MODEL_CONSTRUCTION_FAILED"


class SpeckDeviceMappingError(SpeckRuntimeError):
    """Raised when mapping a model to a Speck device/simulator fails."""

    error_code: str = "DEVICE_MAPPING_FAILED"


class SpeckInferenceError(SpeckRuntimeError):
    """Raised when inference execution fails."""

    error_code: str = "INFERENCE_FAILED"


class SpeckConfigurationError(SpeckRuntimeError):
    """Raised when backend configuration is invalid or state is wrong."""

    error_code: str = "CONFIGURATION_ERROR"
