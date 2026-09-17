"""Structured PYNQ runtime errors for the Neurochip PYNQ backend.

Each error carries a machine-readable ``error_code`` (e.g. ``"OVERLAY_NOT_FOUND"``)
alongside the human-readable message, so API callers can switch on the code
without parsing free-text strings.
"""

from __future__ import annotations


class PynqRuntimeError(RuntimeError):
    """Base class for all PYNQ runtime errors."""

    error_code: str = "PYNQ_RUNTIME_ERROR"

    def __init__(self, message: str, *, error_code: str | None = None) -> None:
        if error_code is not None:
            self.error_code = error_code
        super().__init__(message)


class OverlayLoadError(PynqRuntimeError):
    """Raised when the FPGA overlay/bitstream cannot be loaded."""

    error_code: str = "OVERLAY_LOAD_FAILED"


class MmioWriteError(PynqRuntimeError):
    """Raised when an MMIO register write fails."""

    error_code: str = "MMIO_WRITE_FAILED"


class ConfigurationError(PynqRuntimeError):
    """Raised when backend configuration is invalid."""

    error_code: str = "CONFIGURATION_ERROR"


class DmaTransferError(PynqRuntimeError):
    """Raised when a DMA transfer fails or times out."""

    error_code: str = "DMA_TRANSFER_FAILED"
