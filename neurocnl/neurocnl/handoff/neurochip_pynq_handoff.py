"""NeuroCNL → Neurochip PYNQ handoff connector.

Maps a validated ``PynqRuntimeArtifact`` to the exact payload that
Neurochip's ``/hardware/pynq/deploy`` endpoint expects, submits the
request over HTTP, and verifies deployment status.

Fail-closed: raises ``PynqHandoffRejectedError`` when:
- The export result is NOT_EXPORTABLE (no HTTP call is made).
- The remote Neurochip endpoint returns an HTTP error.
- The board is unreachable (connection refused / timeout).
- The backend status check reports a non-configured state.

Deterministic: weight ordering follows connection list order from the
``PynqOverlayConfigContract`` so repeated calls on the same artifact
always produce identical payloads.
"""

from __future__ import annotations

import json
import math
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Protocol, cast, runtime_checkable

from neurocnl.contracts.pynq_deployment_contract import (
    PynqExportResult,
    PynqRejectionReason,
    PynqSupportState,
)
from neurocnl.contracts.pynq_runtime_artifact_contract import PynqRuntimeArtifact

# ---------------------------------------------------------------------------
# Endpoint configuration
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class NeurochipEndpointConfig:
    """Configuration for a remote Neurochip PYNQ endpoint.

    Attributes
    ----------
    base_url:
        Base URL of the Neurochip service, e.g. ``"http://pynq-z2:8000"``.
    bitstream_path:
        Path to the ``.bit`` overlay file on the Neurochip host.
        Defaults to ``"snn_overlay.bit"`` (relative to Neurochip's overlay dir).
    api_key:
        Optional API key sent in the ``X-API-Key`` header.
    timeout:
        HTTP request timeout in seconds (default 30.0).
    """

    base_url: str
    bitstream_path: str = "snn_overlay.bit"
    api_key: str | None = None
    timeout: float = 30.0


# ---------------------------------------------------------------------------
# HTTP client protocol (injectable for testing)
# ---------------------------------------------------------------------------


@runtime_checkable
class NeurochipPynqClientProtocol(Protocol):
    """Structural interface for the Neurochip PYNQ HTTP client."""

    def post_deploy(
        self,
        deploy_url: str,
        payload: dict[str, Any],
        headers: dict[str, str],
        timeout: float,
    ) -> dict[str, Any]:
        """POST the deploy payload and return the parsed JSON response."""
        ...

    def get_status(
        self,
        status_url: str,
        headers: dict[str, str],
        timeout: float,
    ) -> dict[str, Any]:
        """GET the status endpoint and return the parsed JSON response."""
        ...


class NeurochipPynqClient:
    """Default HTTP client using ``urllib.request`` (no extra dependencies).

    All HTTP errors are propagated as ``urllib.error.HTTPError`` or
    ``urllib.error.URLError`` — callers are responsible for translating
    these into ``PynqRejectionReason`` values.
    """

    def post_deploy(
        self,
        deploy_url: str,
        payload: dict[str, Any],
        headers: dict[str, str],
        timeout: float,
    ) -> dict[str, Any]:
        """Submit a deploy request to Neurochip and return the response dict."""
        body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            deploy_url,
            data=body,
            headers={"Content-Type": "application/json", **headers},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return cast(dict[str, Any], json.loads(resp.read().decode("utf-8")))

    def get_status(
        self,
        status_url: str,
        headers: dict[str, str],
        timeout: float,
    ) -> dict[str, Any]:
        """Fetch the Neurochip PYNQ status and return the response dict."""
        req = urllib.request.Request(
            status_url,
            headers=headers,
            method="GET",
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return cast(dict[str, Any], json.loads(resp.read().decode("utf-8")))


# ---------------------------------------------------------------------------
# Handoff result and error
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class PynqHandoffResult:
    """Outcome of a NeuroCNL → Neurochip PYNQ handoff attempt.

    Attributes
    ----------
    support_state:
        Final verdict: ``DEPLOYABLE``, ``NOT_DEPLOYABLE``, or one of the
        export-time states if no HTTP call was attempted.
    export_result:
        The full ``PynqExportResult`` from the planning stage.
    deploy_payload:
        The payload dict sent to ``/hardware/pynq/deploy``, or ``None`` if
        the handoff was rejected before making an HTTP call.
    deploy_response:
        The JSON response body from ``/hardware/pynq/deploy``, or ``None``.
    status_response:
        The JSON response body from ``/hardware/pynq/status``, or ``None``.
    runtime_rejections:
        Deploy-time rejection reasons (e.g. ``BOARD_UNREACHABLE``).
    endpoint_url:
        The base URL that was targeted, or ``None`` if no call was made.
    """

    support_state: PynqSupportState
    export_result: PynqExportResult
    deploy_payload: dict[str, Any] | None = field(default=None)
    deploy_response: dict[str, Any] | None = field(default=None)
    status_response: dict[str, Any] | None = field(default=None)
    runtime_rejections: list[PynqRejectionReason] = field(default_factory=list)
    endpoint_url: str | None = field(default=None)


class PynqHandoffRejectedError(Exception):
    """Raised when the PYNQ handoff fails at any stage.

    Attributes
    ----------
    handoff_result:
        Full result including support state, rejections, and any partial
        response data received before failure.
    """

    def __init__(self, handoff_result: PynqHandoffResult) -> None:
        self.handoff_result = handoff_result
        reasons = ", ".join(
            r.value for r in handoff_result.export_result.rejections
        ) or ", ".join(r.value for r in handoff_result.runtime_rejections)
        super().__init__(
            f"PYNQ handoff rejected ({handoff_result.support_state}): {reasons}"
        )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _build_deploy_headers(config: NeurochipEndpointConfig) -> dict[str, str]:
    headers: dict[str, str] = {}
    if config.api_key:
        headers["X-API-Key"] = config.api_key
    return headers


#: Timestep the overlay runs at, in seconds. Mirrors the manifest's
#: ``register_map.timestep_us``.
_DEFAULT_TIMESTEP_SECONDS = 0.001

#: The timestep a NIR ``LIF`` is *trained* under, in seconds.
#:
#: ``snntorch.import_nir`` hardcodes 1e-4 for this node type, so the notebook
#: this project generates builds ``snn.Leaky(beta = 1 - dt/tau)`` from it — and
#: that is the network whose weights end up on the board. The overlay's own
#: 1 ms timestep is wall-clock, not semantics: what has to be reproduced is the
#: per-step decay the model learned, not the physical time a step takes. Reading
#: the leak from the overlay's timestep gave `beta` 0.5 where the model learned
#: 0.95, an eight-fold error in the steady-state membrane.
LIF_TRAINING_DT_SECONDS = 1e-4


def leak_shift_for_tau(
    tau_seconds: float | None, timestep_seconds: float = _DEFAULT_TIMESTEP_SECONDS
) -> int:
    """Map a membrane time constant onto the engine's shift-based leak.

    The overlay decays the membrane by ``v >> shift`` each timestep — a
    fraction of ``1 / 2**shift`` — because a shift is free in fabric where a
    multiply is not. The closest shift to a time constant of ``tau`` is
    ``log2(tau / dt)``. A shift of 0 means no leak at all, which is what a
    missing or non-positive tau gets.
    """
    if not tau_seconds or tau_seconds <= 0 or timestep_seconds <= 0:
        return 0
    ratio = tau_seconds / timestep_seconds
    if ratio <= 1:
        return 0
    return max(0, min(31, round(math.log2(ratio))))


def hardware_threshold(
    quantised_threshold: float,
    *,
    leak_shift: int,
    resistance: float = 1.0,
) -> int:
    """Retune a threshold for the leak the fabric can actually apply.

    The engine's leak is a shift, so its decay can only be one of
    ``1 - 2**-s``: 0.5, 0.75, 0.875, 0.9375, … A model trained at ``beta =
    1 - dt/tau`` almost never lands on one of those, and under a static input
    presented every timestep the membrane settles at ``drive / (1 - beta)`` —
    so a beta that is off by a fifth moves the firing point by a fifth. A
    trained network has no such margin: measured on the MNIST network in this
    repo, the strongest hidden neuron settles at 20.45 against a threshold of
    20.0, and the nearest available beta (0.9375 against 0.95) drops it to
    16.4, which fires nothing at all.

    So the threshold moves instead of the decay. Firing under a static input is
    ``drive >= threshold * (1 - beta)``, and holding that condition fixed while
    beta changes gives, after substituting ``beta = 1 - dt/tau`` and the
    engine's ``1 - 2**-shift``::

        threshold_hardware = threshold_model * 2**shift / r

    NIR's ``r`` scales the input current, which the engine has no term for —
    the same asymmetry ``snntorch.import_nir`` handles by dividing the
    threshold by ``r*dt/tau``. Both corrections are folded in above.

    A shift of 0 is a pure integrator with no steady state, so there is nothing
    to match and the threshold is passed through.
    """
    if leak_shift <= 0:
        return int(round(quantised_threshold))
    scale = (2**leak_shift) / (resistance if resistance else 1.0)
    return max(1, int(round(quantised_threshold * scale)))


def _population_index(artifact: PynqRuntimeArtifact) -> dict[str, Any]:
    return {
        population.id: population for population in artifact.overlay_config.populations
    }


def _chain_order(pairs: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """Order weight matrices the way the engine will walk them.

    The engine runs layer 0, then 1, then 2, handing each layer's spikes to the
    next, so the descriptors must be in chain order regardless of the order the
    connections happened to be exported in.
    """
    if not pairs:
        return []
    successor = dict(pairs)
    targets = {post for _, post in pairs}
    starts = [pre for pre, _ in pairs if pre not in targets]
    if len(starts) != 1:
        raise ValueError(
            "The PYNQ overlay runs one feedforward chain of layers; this "
            "network's connections do not form one."
        )

    ordered: list[tuple[str, str]] = []
    node: str | None = starts[0]
    while node is not None and node in successor:
        ordered.append((node, successor[node]))
        node = successor[node]
    if len(ordered) != len(pairs):
        raise ValueError(
            "The PYNQ overlay's layers must form a single unbranched chain."
        )
    return ordered


def build_pynq_deploy_payload(
    artifact: PynqRuntimeArtifact,
    *,
    bitstream_path: str = "snn_overlay.bit",
) -> dict[str, Any]:
    """Construct the ``DeployRequest`` payload for Neurochip.

    Emits the flat weight buffer the engine caches on-chip, plus one descriptor
    per layer telling it where that layer's matrix starts and how its neurons
    behave. Overlay-v1 carried a single flat weight list and one global
    threshold, which is all a one-matrix engine could use.

    Weights are grouped per layer and emitted in chain order, so a layer's
    ``weight_offset`` always addresses a contiguous block.
    """
    overlay_manifest = artifact.overlay_manifest
    populations = _population_index(artifact)
    scale_factor = float(artifact.overlay_config.quantisation.scale_factor)

    # Group the dense weights by the matrix they belong to, keeping the
    # exporter's within-matrix ordering (row-major, post x pre).
    grouped: dict[tuple[str, str], list[float]] = {}
    for connection in artifact.overlay_config.connections:
        grouped.setdefault((connection.pre, connection.post), []).append(
            float(connection.weight)
        )

    weights: list[float] = []
    layers: list[dict[str, Any]] = []
    for pre, post in _chain_order(list(grouped)):
        pre_population = populations.get(pre)
        post_population = populations.get(post)
        if pre_population is None or post_population is None:
            raise ValueError(
                f"Connection {pre} -> {post} references a population that is not "
                "in the overlay configuration."
            )

        params = post_population.params
        # Already in the engine's units. `quantise_network_dict` scales every
        # population threshold by the same factor it scaled the weights with, so
        # the artifact's `v_threshold` is the quantised one. Multiplying by the
        # scale a second time here squared it: a 784-input layer of int8 weights
        # can reach at most 784 x 127 = 99,568, against a threshold of 4,129,161
        # for this MNIST network. No input could ever fire a neuron, on any
        # board, and the run came back as a legitimate-looking wall of zeros.
        quantised_threshold = float(params.get("v_threshold", 1.0))
        # `tau_rc` is what the exporter writes (`pynq_exporter.py`); the other
        # two names are what other IR sources use. Reading only `tau_m`/`tau`
        # meant every network reached the board with no leak at all, so its
        # membranes integrated forever and its dynamics were not the trained
        # model's.
        tau = params.get("tau_rc", params.get("tau_m", params.get("tau")))
        leak_shift = leak_shift_for_tau(
            float(tau) if tau is not None else None, LIF_TRAINING_DT_SECONDS
        )

        layers.append(
            {
                "input_size": pre_population.n_neurons,
                "output_size": post_population.n_neurons,
                "weight_offset": len(weights),
                "threshold": hardware_threshold(
                    quantised_threshold,
                    leak_shift=leak_shift,
                    resistance=float(params.get("r", 1.0) or 1.0),
                ),
                "leak_shift": leak_shift,
                "refractory": int(params.get("refractory_steps", 0)),
                "source": pre,
                "target": post,
            }
        )
        weights.extend(grouped[(pre, post)])

    config: dict[str, Any] = {
        # Retained for the single-layer case and for display; per-layer values
        # in `layers` are what the engine is actually programmed with.
        "threshold": layers[0]["threshold"] if layers else 1,
        "bit_width": artifact.weight_bit_width,
        "scale_factor": scale_factor,
        "timestep_us": overlay_manifest.register_map.timestep_us,
    }

    return {
        "weights": weights,
        "layers": layers,
        "config": config,
        "bitstream_path": bitstream_path,
        "overlay_id": overlay_manifest.overlay_id,
        "overlay_version": overlay_manifest.overlay_version,
        "weight_bit_width": artifact.weight_bit_width,
        "max_supported_neurons": overlay_manifest.max_neurons,
        "max_supported_synapses": overlay_manifest.max_synapses,
        "dma_ip_name": overlay_manifest.dma_ip_name,
        "snn_ip_name": overlay_manifest.snn_ip_name,
        "register_map": overlay_manifest.register_map.model_dump(),
    }


def _build_deploy_payload(
    artifact: PynqRuntimeArtifact,
    endpoint_config: NeurochipEndpointConfig,
) -> dict[str, Any]:
    return build_pynq_deploy_payload(
        artifact,
        bitstream_path=endpoint_config.bitstream_path,
    )


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def map_pynq_artifact_to_deploy_request(
    artifact: PynqRuntimeArtifact,
    export_result: PynqExportResult,
    endpoint_config: NeurochipEndpointConfig,
    client: NeurochipPynqClientProtocol | None = None,
) -> PynqHandoffResult:
    """Submit a PYNQ runtime artifact to a Neurochip backend for deployment.

    Parameters
    ----------
    artifact:
        Validated ``PynqRuntimeArtifact`` produced by
        ``export_pynq_artifact()`` or ``validate_pynq_artifact_completeness()``.
    export_result:
        The ``PynqExportResult`` from ``plan_pynq_exportability()``.
        Must have a non-NOT_EXPORTABLE support state.
    endpoint_config:
        Remote Neurochip endpoint URL and authentication settings.
    client:
        Optional HTTP client; defaults to ``NeurochipPynqClient``.
        Inject a mock in tests.

    Returns
    -------
    PynqHandoffResult
        Result with ``support_state = DEPLOYABLE`` on success.

    Raises
    ------
    PynqHandoffRejectedError
        If the export result is NOT_EXPORTABLE, the board is unreachable,
        the deploy endpoint returns an error, or the status check fails.
    """
    if client is None:
        client = NeurochipPynqClient()

    # -- 1. Export-time gate (fail-closed) -----------------------------------
    if export_result.support_state == PynqSupportState.NOT_EXPORTABLE:
        result = PynqHandoffResult(
            support_state=PynqSupportState.NOT_EXPORTABLE,
            export_result=export_result,
        )
        raise PynqHandoffRejectedError(result)

    # -- 2. Build deploy payload ---------------------------------------------
    deploy_payload = _build_deploy_payload(artifact, endpoint_config)
    headers = _build_deploy_headers(endpoint_config)

    deploy_url = f"{endpoint_config.base_url.rstrip('/')}/hardware/pynq/deploy"
    status_url = f"{endpoint_config.base_url.rstrip('/')}/hardware/pynq/status"

    # -- 3. Submit deploy request --------------------------------------------
    deploy_response: dict[str, Any] | None = None
    try:
        deploy_response = client.post_deploy(
            deploy_url=deploy_url,
            payload=deploy_payload,
            headers=headers,
            timeout=endpoint_config.timeout,
        )
    except urllib.error.HTTPError as exc:
        result = PynqHandoffResult(
            support_state=PynqSupportState.NOT_DEPLOYABLE,
            export_result=export_result,
            deploy_payload=deploy_payload,
            runtime_rejections=[PynqRejectionReason.OVERLAY_LOAD_FAILURE],
            endpoint_url=endpoint_config.base_url,
        )
        raise PynqHandoffRejectedError(result) from exc
    except (urllib.error.URLError, OSError) as exc:
        result = PynqHandoffResult(
            support_state=PynqSupportState.NOT_DEPLOYABLE,
            export_result=export_result,
            deploy_payload=deploy_payload,
            runtime_rejections=[PynqRejectionReason.BOARD_UNREACHABLE],
            endpoint_url=endpoint_config.base_url,
        )
        raise PynqHandoffRejectedError(result) from exc

    # -- 4. Check deployment status ------------------------------------------
    status_response: dict[str, Any] | None = None
    try:
        status_response = client.get_status(
            status_url=status_url,
            headers=headers,
            timeout=endpoint_config.timeout,
        )
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as exc:
        result = PynqHandoffResult(
            support_state=PynqSupportState.NOT_DEPLOYABLE,
            export_result=export_result,
            deploy_payload=deploy_payload,
            deploy_response=deploy_response,
            runtime_rejections=[PynqRejectionReason.BOARD_UNREACHABLE],
            endpoint_url=endpoint_config.base_url,
        )
        raise PynqHandoffRejectedError(result) from exc

    backend_state = (status_response or {}).get("state", "")
    if backend_state != "configured":
        result = PynqHandoffResult(
            support_state=PynqSupportState.NOT_DEPLOYABLE,
            export_result=export_result,
            deploy_payload=deploy_payload,
            deploy_response=deploy_response,
            status_response=status_response,
            runtime_rejections=[PynqRejectionReason.OVERLAY_LOAD_FAILURE],
            endpoint_url=endpoint_config.base_url,
        )
        raise PynqHandoffRejectedError(result) from None

    return PynqHandoffResult(
        support_state=PynqSupportState.DEPLOYABLE,
        export_result=export_result,
        deploy_payload=deploy_payload,
        deploy_response=deploy_response,
        status_response=status_response,
        endpoint_url=endpoint_config.base_url,
    )
