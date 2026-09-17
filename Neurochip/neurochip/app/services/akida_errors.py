"""Structured Akida runtime errors for the Neurochip Akida backend.

Each error carries a machine-readable ``error_code`` (e.g. ``"SDK_NOT_AVAILABLE"``)
alongside the human-readable message, so API callers can switch on the code
without parsing free-text strings.
"""

from __future__ import annotations


class AkidaRuntimeError(RuntimeError):
    """Base class for all Akida runtime errors."""

    error_code: str = "AKIDA_RUNTIME_ERROR"

    def __init__(self, message: str, *, error_code: str | None = None) -> None:
        if error_code is not None:
            self.error_code = error_code
        super().__init__(message)


class AkidaSdkNotAvailableError(AkidaRuntimeError):
    """Raised when the Akida Python SDK is not installed."""

    error_code: str = "SDK_NOT_AVAILABLE"


class AkidaModelConstructionError(AkidaRuntimeError):
    """Raised when building an Akida model from a mapped network fails."""

    error_code: str = "MODEL_CONSTRUCTION_FAILED"


class AkidaDeviceMappingError(AkidaRuntimeError):
    """Raised when mapping a model to an Akida device/simulator fails."""

    error_code: str = "DEVICE_MAPPING_FAILED"


class AkidaInferenceError(AkidaRuntimeError):
    """Raised when inference execution fails."""

    error_code: str = "INFERENCE_FAILED"


class AkidaConfigurationError(AkidaRuntimeError):
    """Raised when backend configuration is invalid or state is wrong."""

    error_code: str = "CONFIGURATION_ERROR"
