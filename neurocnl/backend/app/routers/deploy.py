"""Deploy endpoints for Teensy and PYNQ Z2 targets.

- POST /api/deploy/teensy/network — validate a CNL spec and produce a
  Neurochip-compatible NetworkInput payload for Teensy firmware generation.

- POST /api/deploy/pynq/network — validate a CNL spec against PYNQ Z2
  hardware constraints and return an exportability verdict with warnings,
  rejection reasons, and network summary.

These are the bridge endpoints between the NeuroCNL Studio / NMTK frontends
and the Neurochip backend.
"""

from __future__ import annotations

import base64
import binascii
import json
import math
import shutil
from typing import Any

import structlog
from fastapi import APIRouter, HTTPException, Request, Response
from prometheus_client import Counter
from pydantic import BaseModel, Field

from backend.app.middleware.rate_limit import limiter
from backend.app.services.lava_deploy_service import (
    build_lava_deploy_payload,
    lava_network_summary,
    lava_support_payload,
)
from backend.app.services.neurocnl_bridge import build_deploy_ir_from_spec_text
from backend.app.services.pynq_trained_weights import (
    TrainedWeightError,
    apply_trained_weights,
    load_trained_nir_graph,
)
from backend.app.utils.cnl_errors import (
    build_backend_failure_detail,
    build_lowering_failure_detail,
    build_parse_failure_detail,
)
from neurocnl.contracts.teensy_deployment_contract import (
    REJECTION_MESSAGES,
    TeensyDeployabilityVerdict,
)
from neurocnl.handoff.neurochip_teensy_mapper import (
    TeensyHandoffRejectedError,
    map_network_ir_to_teensy_payload,
)
from neurocnl.ir import LoweringError
from neurocnl.pipeline import (
    apply_user_params,
    default_params_with_provenance,
    parse_spec_text,
)

router = APIRouter()
logger = structlog.get_logger(__name__)

DEPLOY_VERDICTS = Counter(
    "neurocnl_deploy_verdicts_total",
    "Deploy endpoint verdicts",
    ["target", "verdict"],
)


def _assert_json_safe_numbers(value: object, *, path: str = "$") -> None:
    if isinstance(value, float) and not math.isfinite(value):
        raise ValueError(f"{path} contains non-finite float {value!r}")
    if isinstance(value, dict):
        for key, nested in value.items():
            _assert_json_safe_numbers(nested, path=f"{path}.{key}")
    elif isinstance(value, list):
        for index, nested in enumerate(value):
            _assert_json_safe_numbers(nested, path=f"{path}[{index}]")


# ---------------------------------------------------------------------------
# Request / response schemas
# ---------------------------------------------------------------------------


class TeensyNetworkRequest(BaseModel):
    spec: str = Field(..., description="Raw CNL spec text")
    weight_bit_width: int = Field(
        default=8,
        ge=8,
        le=32,
        description="Weight quantisation bit-width (8, 16, or 32)",
    )


class TeensyNetworkResponse(BaseModel):
    verdict: str = Field(description="faithful | approximate | not_deployable")
    warnings: list[str] = Field(default_factory=list)
    rejection_reasons: list[str] = Field(default_factory=list)
    payload: dict[str, Any] | None = Field(
        default=None,
        description="Neurochip NetworkInput-compatible dict; null when not_deployable",
    )


# ---------------------------------------------------------------------------
# Endpoint
# ---------------------------------------------------------------------------


@router.post("/deploy/teensy/network", response_model=TeensyNetworkResponse)
@limiter.limit("20/minute")
def deploy_teensy_network(
    request: Request,
    response: Response,
    body: TeensyNetworkRequest,
) -> TeensyNetworkResponse:
    """Parse, lower, and Teensy-gate a CNL spec.

    Returns the Neurochip NetworkInput payload when the network is deployable
    (DEPLOYABLE or DEPLOYABLE_WITH_WARNINGS).  Raises HTTP 422 with a
    structured detail when it is not.

    The ``weight_bit_width`` parameter must be 8, 16, or 32 — the only values
    accepted by the Teensy hardware invariants.
    """
    if body.weight_bit_width not in (8, 16, 32):
        raise HTTPException(
            status_code=422,
            detail="weight_bit_width must be 8, 16, or 32 for Teensy targets.",
        )

    # -- 1. Parse ------------------------------------------------------------
    parse_results = parse_spec_text(body.spec)
    if any(not r["valid"] for r in parse_results):
        raise HTTPException(
            status_code=422, detail=build_parse_failure_detail(parse_results)
        )

    parsed_specs = [
        r["parsed"] for r in parse_results if r["valid"] and r["parsed"] is not None
    ]

    # -- 2. Lower ------------------------------------------------------------
    params, param_provenance = default_params_with_provenance(parsed_specs)
    apply_user_params(params, param_provenance, {})

    try:
        ir = build_deploy_ir_from_spec_text(body.spec, parsed_specs)
    except LoweringError as exc:
        raise HTTPException(
            status_code=422, detail=build_lowering_failure_detail(exc)
        ) from exc

    # -- 3. Handoff (fail-closed Teensy gate) --------------------------------
    try:
        result = map_network_ir_to_teensy_payload(ir, body.weight_bit_width)
    except TeensyHandoffRejectedError as exc:
        dr = exc.deployment_result
        reasons = [REJECTION_MESSAGES.get(r, r.value) for r in dr.rejections]
        DEPLOY_VERDICTS.labels(target="teensy", verdict="not_deployable").inc()
        logger.info(
            "teensy_deploy_rejected",
            reasons=reasons,
            spec_length=len(body.spec),
        )
        raise HTTPException(
            status_code=422,
            detail=build_backend_failure_detail(
                "not_deployable",
                "The network does not satisfy the selected hardware target's deployability constraints.",
                source="deploy",
                rejection_reasons=reasons,
                warnings=list(dr.warnings),
            ),
        ) from exc

    dr = result.deployment_result
    verdict = (
        "approximate"
        if dr.verdict == TeensyDeployabilityVerdict.DEPLOYABLE_WITH_WARNINGS
        else "faithful"
    )

    DEPLOY_VERDICTS.labels(target="teensy", verdict=verdict).inc()
    logger.info(
        "teensy_deploy_payload_built",
        verdict=verdict,
        num_neurons=result.payload.get("num_neurons"),
        num_synapses=result.payload.get("num_synapses"),
    )

    return TeensyNetworkResponse(
        verdict=verdict,
        warnings=list(dr.warnings),
        rejection_reasons=[],
        payload=result.payload,
    )


# ---------------------------------------------------------------------------
# PYNQ Z2 exportability check
# ---------------------------------------------------------------------------


class PynqNetworkRequest(BaseModel):
    spec: str = Field(..., description="Raw CNL spec text")
    weight_bit_width: int = Field(
        default=8,
        description="Weight quantisation bit-width for the fixed PYNQ overlay-v1 contract",
    )
    trained_nir_base64: str | None = Field(
        default=None,
        description=(
            "Optional base64 `.nir` graph carrying trained weights, from "
            "GET /notebook/artifacts/latest-trained-nir. Without it the payload's "
            "weights come from the CNL spec, which stores tensor shape only — so "
            "they are all zeros and the board will fire nothing."
        ),
    )


class PynqNetworkResponse(BaseModel):
    support_state: str = Field(
        description=("exportable | exportable_with_warnings | not_exportable")
    )
    warnings: list[str] = Field(default_factory=list)
    rejections: list[str] = Field(default_factory=list)
    network_summary: dict[str, Any] | None = Field(
        default=None,
        description="Neuron/synapse counts and memory estimate; null when not_exportable",
    )
    deploy_payload: dict[str, Any] | None = Field(
        default=None,
        description=(
            "Neurochip /hardware/pynq/deploy-compatible payload built from the validated "
            "runtime artifact; null when not_exportable"
        ),
    )
    trained_weights: dict[str, Any] | None = Field(
        default=None,
        description=(
            "Where the payload's weights came from: `applied` false means they are "
            "the spec's zeros, so the board would run but produce nothing. Null "
            "when no trained NIR was supplied."
        ),
    )


@router.post("/deploy/pynq/network", response_model=PynqNetworkResponse)
@limiter.limit("20/minute")
def deploy_pynq_network(
    request: Request,
    response: Response,
    body: PynqNetworkRequest,
) -> PynqNetworkResponse:
    """Parse, lower, and PYNQ-gate a CNL spec.

    Runs the full NeuroCNL pipeline (parse → lower → plan_pynq_exportability)
    and returns a two-tier exportability verdict.

    - ``exportable`` / ``exportable_with_warnings``: overlay artifacts can be
      generated offline without a real board.
    - ``not_exportable``: one or more hardware constraints are violated; the
      ``rejections`` list explains why.

    The ``weight_bit_width`` must match the fixed overlay-v1 contract.
    """
    from neurocnl.contracts.pynq_deployment_contract import PYNQ_LIMITS
    from neurocnl.contracts.pynq_deployment_contract import (
        REJECTION_MESSAGES as PYNQ_REJECTION_MESSAGES,
    )
    from neurocnl.contracts.pynq_deployment_contract import PynqSupportState
    from neurocnl.export.pynq_exporter import export_pynq_artifact_from_ir
    from neurocnl.handoff.neurochip_pynq_handoff import build_pynq_deploy_payload
    from neurocnl.planner import plan_pynq_exportability

    supported_widths = PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS
    if body.weight_bit_width not in supported_widths:
        raise HTTPException(
            status_code=422,
            detail=f"weight_bit_width must be one of {supported_widths} for PYNQ Z2.",
        )

    # -- 1. Parse ------------------------------------------------------------
    parse_results = parse_spec_text(body.spec)
    if any(not r["valid"] for r in parse_results):
        raise HTTPException(
            status_code=422, detail=build_parse_failure_detail(parse_results)
        )

    parsed_specs = [
        r["parsed"] for r in parse_results if r["valid"] and r["parsed"] is not None
    ]

    # -- 2. Lower ------------------------------------------------------------
    params, param_provenance = default_params_with_provenance(parsed_specs)
    apply_user_params(params, param_provenance, {})

    try:
        ir = build_deploy_ir_from_spec_text(body.spec, parsed_specs)
    except LoweringError as exc:
        raise HTTPException(
            status_code=422, detail=build_lowering_failure_detail(exc)
        ) from exc

    # -- 2b. Overlay trained weights, if the caller supplied them ------------
    # Must happen before the gate: the quantizability check reads the actual
    # weight values, so gating the spec's zeros and then swapping in trained
    # values would verify a network nobody deploys.
    trained_weights: dict[str, Any] | None = None
    if body.trained_nir_base64:
        try:
            graph = load_trained_nir_graph(
                base64.b64decode(body.trained_nir_base64, validate=True)
            )
            trained_weights = apply_trained_weights(ir, graph).to_dict()
        except (binascii.Error, ValueError) as exc:
            raise HTTPException(
                status_code=422,
                detail=f"trained_nir_base64 is not valid base64: {exc}",
            ) from exc
        except TrainedWeightError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

    # -- 3. PYNQ exportability gate -----------------------------------------
    export_result = plan_pynq_exportability(ir, bit_width=body.weight_bit_width)

    # -- 4. Build the deploy payload from the IR (Nengo-free) ----------------
    deploy_payload: dict[str, Any] | None = None
    if export_result.support_state != PynqSupportState.NOT_EXPORTABLE:
        try:
            _, artifact = export_pynq_artifact_from_ir(
                ir, bit_width=body.weight_bit_width
            )
            deploy_payload = build_pynq_deploy_payload(artifact)
        except Exception as exc:
            logger.exception(
                "pynq_deploy_payload_failed",
                weight_bit_width=body.weight_bit_width,
                spec_length=len(body.spec),
            )
            raise HTTPException(
                status_code=500,
                detail=build_backend_failure_detail(
                    "pynq_deploy_payload_failed",
                    str(exc),
                    source="deploy",
                ),
            ) from exc

    rejection_messages = [
        PYNQ_REJECTION_MESSAGES.get(r, r.value) for r in export_result.rejections
    ]

    DEPLOY_VERDICTS.labels(
        target="pynq", verdict=str(export_result.support_state)
    ).inc()
    logger.info(
        "pynq_exportability_checked",
        support_state=export_result.support_state,
        warnings=len(export_result.warnings),
        rejections=len(export_result.rejections),
        spec_length=len(body.spec),
        trained_weights_applied=bool(trained_weights and trained_weights["applied"]),
    )

    response_payload = PynqNetworkResponse(
        support_state=export_result.support_state,
        warnings=list(export_result.warnings),
        rejections=rejection_messages,
        network_summary=export_result.network_summary or None,
        deploy_payload=deploy_payload,
        trained_weights=trained_weights,
    )
    try:
        _assert_json_safe_numbers(response_payload.model_dump(mode="python"))
        json.dumps(response_payload.model_dump(mode="json"), allow_nan=False)
    except (TypeError, ValueError) as exc:
        logger.exception(
            "pynq_exportability_response_failed",
            weight_bit_width=body.weight_bit_width,
            spec_length=len(body.spec),
        )
        raise HTTPException(
            status_code=500,
            detail=build_backend_failure_detail(
                "pynq_exportability_response_failed",
                str(exc),
                source="deploy",
            ),
        ) from exc
    return response_payload


# ---------------------------------------------------------------------------
# Akida exportability check
# ---------------------------------------------------------------------------


class AkidaNetworkRequest(BaseModel):
    spec: str = Field(..., description="Raw CNL spec text")
    weight_bit_width: int = Field(
        default=4,
        description="Weight quantisation bit-width (1, 2, or 4 for Akida)",
    )
    akida_version: str = Field(
        default="akida1",
        description="Akida hardware variant: akida1 or akida2",
    )


class AkidaNetworkResponse(BaseModel):
    support_state: str = Field(
        description=(
            "exportable_scaffold | exportable_scaffold_with_warnings | unsupported"
        )
    )
    akida_version: str
    topology_verdict: str = Field(
        default="unknown",
        description="Topology classification: faithful | approximate | unknown",
    )
    warnings: list[str] = Field(default_factory=list)
    rejections: list[str] = Field(default_factory=list)
    network_summary: dict[str, Any] | None = Field(
        default=None,
        description="Neuron/synapse counts and memory estimate; null when unsupported",
    )
    mapped_network: dict[str, Any] | None = Field(
        default=None,
        description=(
            "Serialised AkidaMappedNetwork for Neurochip /deploy/mapped; "
            "null when unsupported or topology is not faithful. This payload is "
            "SDK-verifiable by Neurochip but is not itself proof of runtime "
            "deployability."
        ),
    )


@router.post("/deploy/akida/network", response_model=AkidaNetworkResponse)
@limiter.limit("20/minute")
def deploy_akida_network(
    request: Request,
    response: Response,
    body: AkidaNetworkRequest,
) -> AkidaNetworkResponse:
    """Parse, lower, and Akida-gate a CNL spec.

    Runs the full NeuroCNL pipeline (parse → lower → plan_akida_exportability)
    and returns an exportability verdict:

    - ``exportable_scaffold`` / ``exportable_scaffold_with_warnings``: toolkit
      can produce a scaffold package and mapped handoff payload offline.
    - ``unsupported``: one or more hardware constraints are violated; the
      ``rejections`` list explains why.

    Runtime SDK proof is intentionally out of scope for this endpoint. Call the
    Neurochip Akida verification endpoint after package generation to determine
    whether the mapped payload is actually deployable in the current runtime
    environment.

    Supported ``weight_bit_width`` values are 1, 2, and 4 (Akida constraint).
    """
    try:
        from neurocnl.planner import plan_akida_exportability

        supported_widths = (1, 2, 4)
        if body.weight_bit_width not in supported_widths:
            raise HTTPException(
                status_code=422,
                detail=f"weight_bit_width must be one of {supported_widths} for Akida.",
            )

        # -- 1. Parse --------------------------------------------------------
        parse_results = parse_spec_text(body.spec)
        if any(not r["valid"] for r in parse_results):
            raise HTTPException(
                status_code=422, detail=build_parse_failure_detail(parse_results)
            )

        parsed_specs = [
            r["parsed"] for r in parse_results if r["valid"] and r["parsed"] is not None
        ]

        # -- 2. Lower --------------------------------------------------------
        params, param_provenance = default_params_with_provenance(parsed_specs)
        apply_user_params(params, param_provenance, {})

        try:
            ir = build_deploy_ir_from_spec_text(body.spec, parsed_specs)
        except LoweringError as exc:
            raise HTTPException(
                status_code=422, detail=build_lowering_failure_detail(exc)
            ) from exc

        # -- 3. Akida exportability gate -------------------------------------
        export_result = plan_akida_exportability(
            ir,
            akida_version=body.akida_version,
            bit_width=body.weight_bit_width,
        )

        # Actionable sentences, not enum codes. The Flutter client renders this
        # list verbatim, so a bare code like "exceeds_np_size" reaches the user
        # with no indication of which node or field to change.
        rejection_messages = export_result.rejection_messages()

        # -- 4. Build mapped network (scaffold + SDK paths only) -------------
        from neurocnl.contracts.akida_deployment_contract import AkidaSupportState
        from neurocnl.mapping.akida_mapper import (
            AkidaMappingRejectedError,
            map_network_ir_to_akida_representation,
        )

        mapped_network_dict: dict[str, Any] | None = None
        mapping_warnings: list[str] = []
        if export_result.support_state != AkidaSupportState.UNSUPPORTED:
            try:
                mapped = map_network_ir_to_akida_representation(
                    ir, akida_version=body.akida_version
                )
                mapped_network_dict = mapped.model_dump(mode="json")
            except AkidaMappingRejectedError as exc:
                # Without this the mapper's own reasons (branching, fan-out,
                # duplicate connections) were discarded, leaving the client with
                # a passing verdict, no mapped_network, and nothing to show.
                mapped_network_dict = None
                mapping_warnings.append(str(exc))

        all_warnings = list(export_result.warnings) + mapping_warnings

        # Map the three-value Python support_state to the five-value Flutter
        # enum. Derived after mapping so a mapper-only rejection still shows as
        # exportable_scaffold_with_warnings rather than a clean pass.
        support_state_str = str(export_result.support_state)
        if support_state_str == "exportable_scaffold" and all_warnings:
            support_state_str = "exportable_scaffold_with_warnings"

        DEPLOY_VERDICTS.labels(target="akida", verdict=support_state_str).inc()
        logger.info(
            "akida_exportability_checked",
            support_state=support_state_str,
            warnings=len(all_warnings),
            rejections=len(export_result.rejections),
            akida_version=body.akida_version,
            mapped_network_available=mapped_network_dict is not None,
            spec_length=len(body.spec),
        )

        return AkidaNetworkResponse(
            support_state=support_state_str,
            akida_version=export_result.akida_version,
            topology_verdict=export_result.topology_verdict,
            warnings=all_warnings,
            rejections=rejection_messages,
            network_summary=export_result.network_summary or None,
            mapped_network=mapped_network_dict,
        )
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        logger.exception(
            "akida_exportability_failed",
            akida_version=body.akida_version,
            weight_bit_width=body.weight_bit_width,
            spec_length=len(body.spec),
        )
        raise HTTPException(
            status_code=500,
            detail=build_backend_failure_detail(
                "akida_exportability_failed",
                str(exc),
                source="deploy",
            ),
        ) from exc


# ---------------------------------------------------------------------------
# Lava simulator deployability check
# ---------------------------------------------------------------------------


class LavaNetworkRequest(BaseModel):
    spec: str = Field(..., description="Raw CNL spec text")
    weight_bit_width: int = Field(
        default=8,
        ge=1,
        le=32,
        description="Weight quantisation bit-width for the Lava simulator handoff payload",
    )


class LavaNetworkResponse(BaseModel):
    support_state: str = Field(
        description=("exportable | exportable_with_warnings | unsupported")
    )
    warnings: list[str] = Field(default_factory=list)
    rejections: list[str] = Field(default_factory=list)
    network_summary: dict[str, Any] | None = Field(
        default=None,
        description="Neuron/synapse counts and summary metrics for the Lava handoff payload",
    )
    deploy_payload: dict[str, Any] | None = Field(
        default=None,
        description=(
            "Neurochip /api/neurochip/hardware/lava/compile-compatible payload built from the "
            "validated CNL network; null when unsupported"
        ),
    )


@router.post("/deploy/lava/network", response_model=LavaNetworkResponse)
@limiter.limit("20/minute")
def deploy_lava_network(
    request: Request,
    response: Response,
    body: LavaNetworkRequest,
) -> LavaNetworkResponse:
    """Parse, lower, and build a Neurochip-compatible Lava simulator payload."""
    try:
        parse_results = parse_spec_text(body.spec)
        if any(not r["valid"] for r in parse_results):
            raise HTTPException(
                status_code=422, detail=build_parse_failure_detail(parse_results)
            )

        parsed_specs = [
            r["parsed"] for r in parse_results if r["valid"] and r["parsed"] is not None
        ]
        params, param_provenance = default_params_with_provenance(parsed_specs)
        apply_user_params(params, param_provenance, {})

        try:
            ir = build_deploy_ir_from_spec_text(body.spec, parsed_specs)
        except LoweringError as exc:
            raise HTTPException(
                status_code=422,
                detail=build_lowering_failure_detail(exc),
            ) from exc

        support_state, warnings, rejections = lava_support_payload(
            ir,
            weight_bit_width=body.weight_bit_width,
        )
        network_summary = lava_network_summary(ir, body.weight_bit_width)
        deploy_payload: dict[str, Any] | None = None

        if support_state != "unsupported":
            try:
                deploy_payload = build_lava_deploy_payload(ir, body.weight_bit_width)
            except Exception as exc:  # noqa: BLE001
                logger.exception(
                    "lava_deploy_payload_failed",
                    weight_bit_width=body.weight_bit_width,
                    spec_length=len(body.spec),
                )
                raise HTTPException(
                    status_code=500,
                    detail=build_backend_failure_detail(
                        "lava_deploy_payload_failed",
                        str(exc),
                        source="deploy",
                    ),
                ) from exc

        DEPLOY_VERDICTS.labels(target="lava", verdict=support_state).inc()
        response_payload = LavaNetworkResponse(
            support_state=support_state,
            warnings=warnings,
            rejections=rejections,
            network_summary=network_summary,
            deploy_payload=deploy_payload,
        )
        _assert_json_safe_numbers(response_payload.model_dump(mode="python"))
        json.dumps(response_payload.model_dump(mode="json"), allow_nan=False)
        logger.info(
            "lava_deployability_checked",
            support_state=support_state,
            warnings=len(warnings),
            rejections=len(rejections),
            spec_length=len(body.spec),
        )
        return response_payload
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        logger.exception(
            "lava_deployability_failed",
            weight_bit_width=body.weight_bit_width,
            spec_length=len(body.spec),
        )
        raise HTTPException(
            status_code=500,
            detail=build_backend_failure_detail(
                "lava_deployability_failed",
                str(exc),
                source="deploy",
            ),
        ) from exc


# ---------------------------------------------------------------------------
# SC-NeuroCore Toolchain Check
# ---------------------------------------------------------------------------


class ScNeuroCoreToolchainResponse(BaseModel):
    installed: bool = Field(
        description="True if the toolchain executable was found on the server"
    )
    resolved_path: str | None = Field(
        description="The absolute path to the executable if found"
    )


@router.get(
    "/deploy/sc_neurocore/check_toolchain", response_model=ScNeuroCoreToolchainResponse
)
def check_sc_neurocore_toolchain(
    toolchain: str,
    bin_path: str | None = None,
) -> ScNeuroCoreToolchainResponse:
    """Check if an SC-NeuroCore toolchain binary exists on the server.

    If `bin_path` is provided, verifies that exact path.
    Otherwise, checks the server's $PATH for the default executable name.
    """
    executable_name = ""
    if toolchain == "yosys_nextpnr":
        executable_name = "yosys"
    elif toolchain == "vivado":
        executable_name = "vivado"
    elif toolchain == "quartus":
        executable_name = "quartus"
    elif toolchain == "radiant":
        executable_name = "radiant"
    elif toolchain == "diamond":
        executable_name = "diamond"
    else:
        # Fallback to checking the toolchain string itself if unknown
        executable_name = toolchain

    # If the user provided a specific path, we check that exact path.
    # Otherwise we check the system PATH.
    target_path = bin_path if bin_path else executable_name

    resolved = shutil.which(target_path)

    return ScNeuroCoreToolchainResponse(
        installed=resolved is not None,
        resolved_path=resolved,
    )
