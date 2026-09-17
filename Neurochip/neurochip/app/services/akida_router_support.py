"""Business logic backing the Akida router: legacy-schema conversion, error
mapping, remote-dispatch SSRF guarding, and package-deployment-mode handling.

Kept out of ``routers/akida.py`` so the route functions stay transport-only —
validate request, call service, map response.
"""

from __future__ import annotations

import ipaddress
import logging
import os
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable
from typing import Any

from fastapi import HTTPException, Response
from pydantic import ValidationError

from ..schemas.estimation import NetworkInput
from ..utils.provenance import now_utc_iso, provenance_headers
from .akida_backend import AkidaBackend, build_akida_runtime_status
from .akida_errors import (
    AkidaConfigurationError,
    AkidaDeviceMappingError,
    AkidaInferenceError,
    AkidaModelConstructionError,
    AkidaRuntimeError,
    AkidaSdkNotAvailableError,
)

logger = logging.getLogger(__name__)

_BLOCKED_AKIDA_NETWORKS = [
    ipaddress.ip_network("0.0.0.0/8"),
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("169.254.0.0/16"),
    ipaddress.ip_network("::1/128"),
    ipaddress.ip_network("fc00::/7"),
]


def network_input_to_mapped_network(network: NetworkInput) -> dict[str, Any]:
    """Convert Neurochip's NetworkInput to an AkidaMappedNetwork-shaped dict.

    Builds ordered populations and connections from the legacy schema.
    """
    populations: list[dict[str, Any]] = []
    for idx, pop in enumerate(network.populations):
        role = None
        if idx == 0:
            role = "sensory"
        elif idx == len(network.populations) - 1:
            role = "motor"
        populations.append(
            {
                "id": pop["name"],
                "size": pop["size"],
                "role": role,
                "population_type": network.neuron_model.lower(),
                "provenance": [],
                "attributes": {},
            }
        )

    connections: list[dict[str, Any]] = []
    for conn in network.connections:
        target_pop = next(
            (p for p in network.populations if p["name"] == conn["post"]),
            None,
        )
        target_size = target_pop["size"] if target_pop else 1
        connections.append(
            {
                "source": conn["pre"],
                "target": conn["post"],
                "units": target_size,
                "weight": conn.get("weight"),
                "block_type": None,
                "provenance": [],
                "property_provenance": [],
                "attributes": {},
            }
        )

    total_neurons = sum(p["size"] for p in populations)
    total_synapses = sum(c.get("weight_count", 0) for c in network.connections)

    return {
        "akida_version": "akida1",
        "input_population": populations[0]["id"] if populations else None,
        "populations": populations,
        "connections": connections,
        "topology_verdict": "faithful",
        "warnings": [],
        "network_summary": {
            "n_neurons": total_neurons,
            "n_synapses": total_synapses,
            "n_populations": len(populations),
            "n_connections": len(connections),
            "quantization_bits": network.weight_bit_width,
        },
        "metadata_provenance": [],
    }


def akida_error_to_http(exc: AkidaRuntimeError) -> HTTPException:
    """Map structured Akida errors to HTTP status codes."""
    if isinstance(exc, AkidaSdkNotAvailableError):
        return HTTPException(status_code=501, detail=str(exc))
    if isinstance(exc, AkidaConfigurationError):
        return HTTPException(status_code=422, detail=str(exc))
    if isinstance(exc, AkidaDeviceMappingError):
        return HTTPException(status_code=502, detail=str(exc))
    if isinstance(exc, AkidaModelConstructionError | AkidaInferenceError):
        return HTTPException(status_code=500, detail=str(exc))
    return HTTPException(status_code=500, detail=str(exc))


def validate_remote_url(url: str) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise HTTPException(
            status_code=422,
            detail={"error": "invalid_url", "message": "URL must be http or https."},
        )

    hostname = parsed.hostname
    if hostname is None:
        raise HTTPException(
            status_code=422,
            detail={"error": "invalid_url", "message": "URL must include a hostname."},
        )

    allowed_hosts = [
        host.strip()
        for host in os.getenv("NEUROCHIP_AKIDA_ALLOWED_HOSTS", "").split(",")
        if host.strip()
    ]

    # Require an explicit allowlist — remote dispatch is disabled by default.
    if not allowed_hosts:
        raise HTTPException(
            status_code=403,
            detail={
                "error": "remote_dispatch_not_configured",
                "message": (
                    "Akida remote_server dispatch is disabled until an explicit allowlist "
                    "is configured. Set NEUROCHIP_AKIDA_ALLOWED_HOSTS to a comma-separated "
                    "list of permitted hostnames."
                ),
                "hint": (
                    "Example: NEUROCHIP_AKIDA_ALLOWED_HOSTS=akida-server.internal,192.168.1.10"
                ),
            },
        )

    if hostname not in allowed_hosts:
        raise HTTPException(
            status_code=403,
            detail={
                "error": "host_not_allowed",
                "message": f"{hostname!r} is not in NEUROCHIP_AKIDA_ALLOWED_HOSTS.",
            },
        )

    try:
        address = ipaddress.ip_address(hostname)
    except ValueError:
        return  # hostname is DNS — allowlist check above already validated it

    if any(address in network for network in _BLOCKED_AKIDA_NETWORKS):
        raise HTTPException(
            status_code=403,
            detail={
                "error": "ssrf_blocked",
                "message": "Private or local addresses are blocked for remote dispatch.",
            },
        )


def dispatch_package(
    backend: AkidaBackend,
    zip_bytes: bytes,
    deployment_mode: str,
    target_url: str | None,
) -> Response:
    """Apply the requested deployment mode and return an appropriate HTTP response.

    - ``scaffold``      — Return the ZIP for download (default, no extra requirements).
    - ``on_device``     — Require that SDK mapping succeeded; return ZIP on success.
    - ``remote_server`` — POST the ZIP to ``target_url`` and return the remote response
                          as JSON, so the caller can see what the remote host replied.
    """
    if deployment_mode == "on_device":
        # on_device requires the model to have been successfully mapped to hardware
        # or the AKD1000 simulator (software_fallback counts only when SDK is present).
        if backend.current_state not in ("mapped", "running"):
            raise HTTPException(
                status_code=502,
                detail=(
                    "on_device deployment requires a successful SDK mapping. "
                    "The Akida SDK is not available or device mapping failed. "
                    "Check GET /api/neurochip/akida/status for environment details."
                ),
            )
        return Response(
            content=zip_bytes,
            media_type="application/zip",
            headers={
                "Content-Disposition": "attachment; filename=akida_deploy.zip",
                "X-Akida-Deployment-Mode": "on_device",
                "X-Akida-Runtime-Target": backend._runtime_target or "unknown",
                **provenance_headers("artifact_validated"),
            },
        )

    if deployment_mode == "remote_server":
        if not target_url:
            raise HTTPException(
                status_code=422,
                detail="deployment_mode=remote_server requires a target_url query parameter.",
            )
        validate_remote_url(target_url)
        try:
            req = urllib.request.Request(
                url=target_url,
                data=zip_bytes,
                method="POST",
                headers={"Content-Type": "application/zip"},
            )
            with urllib.request.urlopen(req, timeout=30) as resp:  # noqa: S310
                remote_body = resp.read().decode("utf-8", errors="replace")
                remote_status = resp.status
        except urllib.error.HTTPError as exc:
            remote_body = exc.read().decode("utf-8", errors="replace")
            raise HTTPException(
                status_code=502,
                detail={
                    "error": "Remote Akida server returned an error.",
                    "remote_status": exc.code,
                    "remote_body": remote_body,
                },
            ) from exc
        except urllib.error.URLError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"Could not reach remote Akida server at {target_url}: {exc.reason}",
            ) from exc
        except Exception as exc:
            logger.exception("Unexpected error during remote Akida dispatch")
            raise HTTPException(
                status_code=502,
                detail=f"Unexpected error dispatching to remote server: {exc}",
            ) from exc

        from fastapi.responses import JSONResponse

        return JSONResponse(
            status_code=200,
            content={
                "deployment_mode": "remote_server",
                "target_url": target_url,
                "remote_status": remote_status,
                "remote_body": remote_body,
                "generated_at": now_utc_iso(),
            },
        )

    # Default: scaffold — return the ZIP for download
    return Response(
        content=zip_bytes,
        media_type="application/zip",
        headers={
            "Content-Disposition": "attachment; filename=akida_deploy.zip",
            "X-Akida-Deployment-Mode": "scaffold",
            **provenance_headers("scaffold_export"),
        },
    )


def mapped_network_summary(mapped_network: dict[str, Any]) -> dict[str, Any]:
    network_summary = mapped_network.get("network_summary")
    if isinstance(network_summary, dict):
        return dict(network_summary)

    populations = mapped_network.get("populations", [])
    connections = mapped_network.get("connections", [])
    return {
        "n_populations": len(populations) if isinstance(populations, list) else 0,
        "n_connections": len(connections) if isinstance(connections, list) else 0,
    }


def map_backend(
    mapped_network: dict[str, Any],
    *,
    bit_width: int,
) -> tuple[AkidaBackend | None, dict[str, Any]]:
    """Construct and map a fresh Akida backend, returning it plus its SDK status.

    Returns ``(None, status_kwargs)`` when model construction fails — the
    caller's existing backend instance, if any, is left untouched. Raises
    ``AkidaRuntimeError`` for any other runtime failure.
    """
    try:
        backend = AkidaBackend()
        backend.construct_model(mapped_network, bit_width=bit_width)
        try:
            backend.map_to_device()
        except (AkidaSdkNotAvailableError, AkidaDeviceMappingError):
            pass
        return backend, backend.get_sdk_status()
    except AkidaModelConstructionError as exc:
        return None, build_akida_runtime_status(
            state="failed",
            model_summary=mapped_network_summary(mapped_network),
            last_sdk_issue="model_construction_failure",
            last_sdk_issue_detail=str(exc),
        )


def deploy_from_network(
    network: NetworkInput,
    *,
    bit_width: int,
    deployment_mode: str,
    target_url: str | None,
    quantized_weights: list[float] | None,
    set_backend: Callable[[AkidaBackend], None],
) -> Response:
    """Deploy from a legacy NetworkInput (scaffold/on_device/remote_server).

    Builds the mapped-network shape, constructs an Akida backend, optionally
    maps it to hardware per ``deployment_mode``, generates the deployment
    package, and registers the resulting backend as the module-level instance.

    ``set_backend`` is the router's hook for mutating its module-level
    ``backend_instance`` global, keeping router-state ownership in the router
    while the orchestration stays here in the service layer.
    """
    mapped_network = network_input_to_mapped_network(network)
    backend = AkidaBackend()
    backend.construct_model(mapped_network, bit_width=bit_width)

    if deployment_mode == "on_device":
        # on_device: mapping must succeed — raise if it fails
        backend.map_to_device()
    else:
        # scaffold / remote_server: attempt mapping but tolerate failures
        try:
            backend.map_to_device()
        except (AkidaSdkNotAvailableError, AkidaDeviceMappingError):
            logger.info("SDK not available or mapping failed — continuing in scaffold mode")

    zip_bytes = backend.generate_package(bit_width=bit_width)
    set_backend(backend)

    return dispatch_package(backend, zip_bytes, deployment_mode, target_url)


def deploy_from_mapped(
    mapped_network: dict[str, Any],
    *,
    bit_width: int,
    deployment_mode: str,
    target_url: str | None,
    set_backend: Callable[[AkidaBackend], None],
) -> Response:
    """Deploy from a pre-mapped AkidaMappedNetwork-shaped dict.

    ``on_device`` requires real SDK construction + mapping.  Every other mode
    (scaffold / remote_server) only validates the payload and generates the
    package without requiring the SDK to construct or map the model.

    ``set_backend`` is the router's hook for mutating its module-level
    ``backend_instance`` global.
    """
    backend = AkidaBackend()
    if deployment_mode == "on_device":
        backend.construct_model(mapped_network, bit_width=bit_width)
        backend.map_to_device()
    else:
        backend.prepare_mapped_network(mapped_network, bit_width=bit_width)

    zip_bytes = backend.generate_package(bit_width=bit_width)
    set_backend(backend)

    return dispatch_package(backend, zip_bytes, deployment_mode, target_url)


def _deploy_error_to_http(
    exc: Exception,
    *,
    validation_detail: str,
) -> HTTPException:
    """Map deploy-orchestration exceptions to HTTP status codes.

    ``validation_detail`` distinguishes the two deploy routes' 422 messages
    (a legacy NetworkInput versus a pre-mapped payload).
    """
    if isinstance(exc, AkidaRuntimeError):
        return akida_error_to_http(exc)
    if isinstance(exc, ValidationError):
        return HTTPException(status_code=422, detail=validation_detail)
    logger.exception("Unexpected error during Akida deploy")
    return HTTPException(
        status_code=500,
        detail="An internal server error occurred while generating the package.",
    )
