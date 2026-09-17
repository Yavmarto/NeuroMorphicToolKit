"""Business logic backing the PYNQ router: error mapping, overlay-contract
validation, and preflight-readiness assembly.

Kept out of ``routers/pynq.py`` so the route functions stay transport-only —
validate request, call service, map response.
"""

from __future__ import annotations

import time
from typing import Any, Protocol, cast

from fastapi import HTTPException

from ...contracts.pynq_runtime_artifact_contract import PynqOverlayManifestContract
from .pynq_compiler import PynqCompileError
from .pynq_errors import (
    ConfigurationError,
    DmaTransferError,
    MmioWriteError,
    OverlayLoadError,
    PynqRuntimeError,
)
from .pynq_install_status import read_install_status
from .pynq_overlay_assets import DEFAULT_PYNQ_BITSTREAM_NAME, inspect_overlay_assets
from .pynq_overlay_manifest import load_runtime_overlay_manifest

_DEVICE_NOT_FOUND_CODES = {
    "PYNQ_DEVICE_NOT_FOUND",
    "PYNQ_RUNTIME_UNAVAILABLE",
}
_CONFIGURATION_ERROR_CODES = {
    "OVERLAY_ID_MISMATCH",
    "OVERLAY_VERSION_MISMATCH",
    "OVERLAY_REGISTER_MAP_MISMATCH",
    "OVERLAY_WEIGHT_BIT_WIDTH_MISMATCH",
    "OVERLAY_NEURON_LIMIT_MISMATCH",
    "OVERLAY_SYNAPSE_LIMIT_MISMATCH",
    "OVERLAY_DMA_IP_MISMATCH",
    "OVERLAY_SNN_IP_MISMATCH",
    # Not a hardware fault and not a server error: the runtime is installed in a
    # way that cannot program the PL, and reinstalling it from the app fixes it.
    "PYNQ_ROOT_REQUIRED",
}
_OVERFLOW_ERROR_CODES = {"MMIO_WEIGHT_OVERFLOW"}

# A successful device probe spawns an interpreter that imports `pynq` on a
# Zynq-7020, which measures ~20s — the whole cost of a preflight. The app asks
# for readiness whenever the Deploy step is opened, so back-to-back calls used
# to charge the user 20s each for an answer that cannot have changed in between.
# Only successes are cached: a failing probe is the case where the user is
# actively fixing something and retrying, and it is cheap anyway.
HARDWARE_PROBE_CACHE_TTL_SECONDS = 30.0


class OverlayRequest(Protocol):
    """Shape shared by ``DeployRequest`` and ``PynqVerifyRequest``."""

    overlay_id: str | None
    overlay_version: str | None
    weight_bit_width: int | None
    max_supported_neurons: int | None
    max_supported_synapses: int | None
    dma_ip_name: str | None
    snn_ip_name: str | None
    register_map: dict[str, Any] | None


class HardwareProbeCache:
    """Caches a successful real-device probe for a short TTL."""

    def __init__(self, ttl_seconds: float = HARDWARE_PROBE_CACHE_TTL_SECONDS) -> None:
        self._ttl_seconds = ttl_seconds
        self._ok_until: float = 0.0

    def invalidate(self) -> None:
        self._ok_until = 0.0

    def probe(self) -> None:
        """Run (or skip, if still fresh) a real-device probe.

        Raises ``PynqRuntimeError`` if the probe fails.
        """
        now = time.monotonic()
        if self._ok_until > now:
            return

        from .pynq_backend import probe_real_pynq_device_access

        probe_real_pynq_device_access()
        self._ok_until = now + self._ttl_seconds


def pynq_error_to_http(exc: PynqRuntimeError, *, probe_cache: HardwareProbeCache) -> HTTPException:
    """Map a structured PYNQ error to the appropriate HTTP status."""
    code = getattr(exc, "error_code", "")
    if code in _DEVICE_NOT_FOUND_CODES:
        status = 503
        # A real operation just failed to reach the device, which outranks a
        # cached "the probe passed" from moments ago. Re-probe next time rather
        # than reporting ready for the rest of the window.
        probe_cache.invalidate()
    elif code in _CONFIGURATION_ERROR_CODES:
        status = 422
    elif code in _OVERFLOW_ERROR_CODES:
        status = 413
    elif isinstance(exc, ConfigurationError):
        status = 422
    elif isinstance(exc, DmaTransferError):
        status = 502
    elif isinstance(exc, MmioWriteError | OverlayLoadError):
        status = 500
    else:
        status = 500
    return HTTPException(
        status_code=status,
        detail={"detail": str(exc), "error_code": exc.error_code},
    )


def pynq_compile_error_to_http(exc: PynqCompileError) -> HTTPException:
    return HTTPException(
        status_code=exc.status_code,
        detail={"detail": exc.detail, "error_code": exc.error_code},
    )


def current_overlay_assets(backend_instance: Any | None) -> dict[str, Any]:
    if backend_instance is not None:
        return cast(dict[str, Any], backend_instance.overlay_asset_status.to_dict())
    return inspect_overlay_assets(DEFAULT_PYNQ_BITSTREAM_NAME).to_dict()


def installed_overlay_manifest(backend_instance: Any | None) -> PynqOverlayManifestContract | None:
    if backend_instance is not None and backend_instance.overlay_manifest is not None:
        return cast(PynqOverlayManifestContract, backend_instance.overlay_manifest)
    try:
        return load_runtime_overlay_manifest()
    except Exception:  # noqa: BLE001
        return None


def resolved_register_map(
    request: OverlayRequest,
    manifest: PynqOverlayManifestContract | None,
) -> dict[str, Any] | None:
    if request.register_map is not None:
        return request.register_map
    if manifest is None:
        return None
    return manifest.register_map.model_dump()


def validate_overlay_request(
    request: OverlayRequest,
    backend_instance: Any | None,
) -> dict[str, Any] | None:
    """Check the request's overlay-contract fields against the installed
    overlay manifest, raising ``ConfigurationError`` on any mismatch.

    Returns the resolved register map to deploy/verify with.
    """
    manifest = installed_overlay_manifest(backend_instance)
    if manifest is None:
        return resolved_register_map(request, manifest)

    if request.overlay_id is not None and request.overlay_id != manifest.overlay_id:
        raise ConfigurationError(
            f"overlay_id '{request.overlay_id}' does not match installed overlay '{manifest.overlay_id}'",
            error_code="OVERLAY_ID_MISMATCH",
        )
    if request.overlay_version is not None and request.overlay_version != manifest.overlay_version:
        raise ConfigurationError(
            "overlay_version does not match the installed overlay version",
            error_code="OVERLAY_VERSION_MISMATCH",
        )
    if (
        request.weight_bit_width is not None
        and request.weight_bit_width not in manifest.supported_weight_bit_widths
    ):
        raise ConfigurationError(
            f"weight_bit_width {request.weight_bit_width} is not supported by the installed overlay",
            error_code="OVERLAY_WEIGHT_BIT_WIDTH_MISMATCH",
        )
    if (
        request.max_supported_neurons is not None
        and request.max_supported_neurons != manifest.max_neurons
    ):
        raise ConfigurationError(
            "max_supported_neurons does not match the installed overlay contract",
            error_code="OVERLAY_NEURON_LIMIT_MISMATCH",
        )
    if (
        request.max_supported_synapses is not None
        and request.max_supported_synapses != manifest.max_synapses
    ):
        raise ConfigurationError(
            "max_supported_synapses does not match the installed overlay contract",
            error_code="OVERLAY_SYNAPSE_LIMIT_MISMATCH",
        )
    if request.dma_ip_name is not None and request.dma_ip_name != manifest.dma_ip_name:
        raise ConfigurationError(
            f"dma_ip_name '{request.dma_ip_name}' does not match installed overlay '{manifest.dma_ip_name}'",
            error_code="OVERLAY_DMA_IP_MISMATCH",
        )
    if request.snn_ip_name is not None and request.snn_ip_name != manifest.snn_ip_name:
        raise ConfigurationError(
            f"snn_ip_name '{request.snn_ip_name}' does not match installed overlay '{manifest.snn_ip_name}'",
            error_code="OVERLAY_SNN_IP_MISMATCH",
        )

    resolved = resolved_register_map(request, manifest)
    if resolved is not None and resolved != manifest.register_map.model_dump():
        raise ConfigurationError(
            "register_map does not match the installed overlay contract",
            error_code="OVERLAY_REGISTER_MAP_MISMATCH",
        )
    return resolved


def resolved_paths_from_overlay_assets(overlay_assets: dict[str, Any]) -> dict[str, str]:
    return {
        key: str(overlay_assets.get(key) or "")
        for key in (
            "requested_bitstream_path",
            "bitstream_path",
            "hwh_path",
            "manifest_path",
        )
        if str(overlay_assets.get(key) or "").strip()
    }


def runtime_details(
    overlay_assets: dict[str, Any],
    install_status: dict[str, Any],
    backend_instance: Any | None,
) -> dict[str, Any]:
    details: dict[str, Any] = {
        key: install_status[key]
        for key in (
            "statusPath",
            "serviceName",
            "effectivePynqPython",
            "pynqRuntimeSource",
            "agentPackageVersion",
            "agentWheelName",
            "currentAgentVersion",
            "currentPackagePath",
        )
        if install_status.get(key) not in (None, "")
    }
    if backend_instance is not None:
        details["activeRequestedBitstreamPath"] = backend_instance.requested_bitstream_path
        details["activeBitstreamPath"] = backend_instance.bitstream_path
    resolved_paths = resolved_paths_from_overlay_assets(overlay_assets)
    if resolved_paths:
        details["resolvedPaths"] = resolved_paths
    return details


def build_preflight_status(
    *,
    backend_instance: Any | None,
    default_runtime_mode: str,
    probe_cache: HardwareProbeCache,
) -> dict[str, Any]:
    """Assemble the fields of ``PreflightResponse`` as a plain dict."""
    overlay_assets = current_overlay_assets(backend_instance)
    install_status = read_install_status()
    install_mode = str(install_status.get("installMode") or "unknown").strip() or "unknown"
    runtime_mode = (
        backend_instance.runtime_mode if backend_instance is not None else default_runtime_mode
    )
    resolved_paths = resolved_paths_from_overlay_assets(overlay_assets)
    details = runtime_details(overlay_assets, install_status, backend_instance)
    overlay_issues = overlay_assets.get("issues", [])
    issue_suffix = ""
    if isinstance(overlay_issues, list) and overlay_issues:
        issue_suffix = (
            f" Missing or invalid assets: {'; '.join(str(issue) for issue in overlay_issues)}."
        )
    bitstream_path = resolved_paths.get("bitstream_path", "")
    bitstream_suffix = f" Checked bitstream path: {bitstream_path}." if bitstream_path else ""

    if runtime_mode == "hardware" and overlay_assets["ready_for_hardware"]:
        try:
            probe_cache.probe()
        except PynqRuntimeError as exc:
            status = "failed"
            if exc.error_code == "PYNQ_DEVICE_PROBE_TIMEOUT":
                message = (
                    "Hardware runtime assets are present, but the board did not finish a bounded "
                    "device probe before the timeout elapsed. "
                    f"Runtime probe timed out: {exc}.{bitstream_suffix}"
                )
            else:
                message = (
                    "Hardware runtime assets are present, but the board cannot open a usable PYNQ device yet. "
                    f"Runtime probe failed: {exc}.{bitstream_suffix}"
                )
        except Exception as exc:  # noqa: BLE001
            status = "failed"
            message = (
                "Hardware runtime assets are present, but the board failed a real-device probe before deploy. "
                f"Runtime probe failed: {exc}.{bitstream_suffix}"
            )
        else:
            # The probe passed, so the board can run a network — that is what
            # "ok" means here, and the launcher gates Deploy on it. A user-space
            # install used to report "degraded" instead, which left the app
            # telling the user to restart the runtime forever: restarting works
            # and cannot change the install mode. The one real limitation is that
            # the agent does not survive a board reboot, so it belongs in the
            # message, not in a status that blocks deploying.
            status = "ok"
            if install_mode == "user-space":
                message = (
                    "Hardware runtime and canonical overlay assets are ready. The "
                    "runtime runs in user space, so it will not start again by "
                    "itself after a board reboot — reinstall the board runtime "
                    "with privileged setup to make it automatic."
                )
            else:
                message = "Hardware runtime and canonical overlay assets are ready."
    elif runtime_mode == "hardware":
        status = "failed"
        message = (
            "Runtime is installed, but real-board readiness is blocked until overlay assets are installed. "
            "Run the launcher's Install Overlay step to add snn_overlay.bit, snn_overlay.hwh, "
            "and overlay_manifest.json."
            f"{issue_suffix}{bitstream_suffix}"
        )
    else:
        status = "degraded"
        message = "Simulator fallback active; real-board PYNQ deployment is unavailable."

    return {
        "preflight_status": status,
        "preflight_message": message,
        "runtime_mode": runtime_mode,
        "install_mode": install_mode,
        "overlay_assets": overlay_assets,
        "resolved_paths": resolved_paths,
        "runtime_details": details,
    }
