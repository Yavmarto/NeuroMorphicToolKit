import asyncio
import logging
from typing import Any

from fastapi import (
    APIRouter,
    Body,
    HTTPException,
    Query,
    Request,
    Response,
    WebSocket,
    WebSocketDisconnect,
)
from pydantic import ValidationError

from ...contracts.pynq_runtime_artifact_contract import (
    PynqNetworkPayloadContract,
    validate_pynq_compile_artifact,
)
from ...contracts.teensy_deployment_contract import TeensyNetworkPayloadContract
from ..limiter import limiter
from ..schemas.estimation import NetworkInput
from ..services import (
    akida_generator,
    brainscales_generator,
    lava_generator,
    loihi_generator,
    neuroml_generator,
    pynq_generator,
    spinnaker_generator,
    teensy_generator,
)
from ..utils.provenance import provenance_headers

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/neurochip/export", tags=["export"])


@router.post("/lava")
def export_lava(
    network: NetworkInput = Body(..., embed=True),
    bit_width: int = Query(8),
) -> Response:
    """Export a Lava simulation scaffold without requiring the Lava SDK."""
    try:
        zip_bytes = lava_generator.generate_lava_package(network, bit_width=bit_width)
        return Response(
            content=zip_bytes,
            media_type="application/zip",
            headers={
                "Content-Disposition": "attachment; filename=lava_deploy.zip",
                **provenance_headers("scaffold_export"),
            },
        )
    except ValidationError as error:
        logger.warning("Validation error during export: %s", error)
        raise HTTPException(status_code=422, detail="Invalid network configuration.") from error


@router.post("/akida")
@limiter.limit("10/minute")
def export_akida(
    request: Request,
    response: Response,
    network_payload: dict[str, Any] = Body(
        ...,
        description="Accepts either raw NetworkInput JSON or a wrapped payload {'network': NetworkInput}.",
    ),
    bit_width: int = Query(4),
) -> Response:
    try:
        if "network" in network_payload and network_payload["network"] is not None:
            network_data = network_payload["network"]
        else:
            network_data = network_payload
        network = NetworkInput.model_validate(network_data)
        zip_bytes = akida_generator.generate_akida_package(
            network=network,
            bit_width=bit_width,
        )
        return Response(
            content=zip_bytes,
            media_type="application/zip",
            headers={
                "Content-Disposition": "attachment; filename=akida_deploy.zip",
                **provenance_headers("scaffold_export"),
            },
        )
    except ValidationError as e:
        logger.warning("Validation error during export: %s", e)
        raise HTTPException(status_code=422, detail="Invalid network configuration.")
    except Exception as exc:
        logger.exception("Unexpected error during package generation")
        raise HTTPException(
            status_code=500,
            detail="An internal server error occurred while generating the package.",
        ) from exc


@router.post("/brainscales")
def export_brainscales(
    network: NetworkInput = Body(..., embed=True),
    bit_width: int = Query(4),
    quantized_weights: list[float] | None = Body(None),
) -> Response:
    try:
        zip_bytes = brainscales_generator.generate_brainscales_package(
            network=network,
            bit_width=bit_width,
            quantized_weights=quantized_weights,
        )
        return Response(
            content=zip_bytes,
            media_type="application/zip",
            headers={
                "Content-Disposition": "attachment; filename=brainscales_deploy.zip",
                **provenance_headers("scaffold_export"),
            },
        )
    except ValidationError as e:
        logger.warning("Validation error during export: %s", e)
        raise HTTPException(status_code=422, detail="Invalid network configuration.")
    except NotImplementedError as exc:
        raise HTTPException(status_code=501, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Unexpected error during package generation")
        raise HTTPException(
            status_code=500,
            detail="An internal server error occurred while generating the package.",
        ) from exc


@router.post("/spinnaker")
def export_spinnaker(
    network: NetworkInput = Body(..., embed=True),
    bit_width: int = Query(16),
    quantized_weights: list[float] | None = Body(None),
) -> Response:
    try:
        zip_bytes = spinnaker_generator.generate_spinnaker_package(
            network=network,
            bit_width=bit_width,
            quantized_weights=quantized_weights,
        )
        return Response(
            content=zip_bytes,
            media_type="application/zip",
            headers={
                "Content-Disposition": "attachment; filename=spinnaker_deploy.zip",
                **provenance_headers("scaffold_export"),
            },
        )
    except ValidationError as e:
        logger.warning("Validation error during export: %s", e)
        raise HTTPException(status_code=422, detail="Invalid network configuration.")
    except NotImplementedError as exc:
        raise HTTPException(status_code=501, detail=str(exc)) from exc
    except Exception:
        logger.exception("Unexpected error during package generation")
        raise HTTPException(
            status_code=500,
            detail="An internal server error occurred while generating the package.",
        )


@router.post("/teensy")
@limiter.limit("10/minute")
def export_teensy(
    request: Request,
    response: Response,
    network_payload: dict[str, Any] = Body(...),
    bit_width: int = Query(8),
) -> Response:
    try:
        excluded_keys = {"quantized_weights", "input_pins", "output_pins", "network"}
        network_data = network_payload.get("network", network_payload)
        if not isinstance(network_data, dict):
            network_data = network_payload
        quantized_weights = network_payload.get("quantized_weights")
        input_pins = network_payload.get("input_pins")
        output_pins = network_payload.get("output_pins")

        network_kwargs = {k: v for k, v in network_data.items() if k not in excluded_keys}
        network = NetworkInput(**network_kwargs)
        TeensyNetworkPayloadContract(
            num_neurons=network.num_neurons,
            num_synapses=network.num_synapses,
            neuron_model=network.neuron_model,
            weight_bit_width=network.weight_bit_width,
            network_depth=network.network_depth,
        )
        zip_bytes = teensy_generator.generate_teensy_project(
            network=network,
            bit_width=bit_width,
            quantized_weights=quantized_weights,
            input_pins=input_pins,
            output_pins=output_pins,
        )
        return Response(
            content=zip_bytes,
            media_type="application/zip",
            headers={
                "Content-Disposition": "attachment; filename=neurochip_firmware.zip",
                **provenance_headers("schema_validated"),
            },
        )
    except ValidationError as e:
        logger.warning("Validation error during export: %s", e)
        raise HTTPException(status_code=422, detail="Invalid network configuration.")
    except Exception:
        logger.exception("Unexpected error during package generation")
        raise HTTPException(
            status_code=500,
            detail="An internal server error occurred while generating the package.",
        )


@router.post("/loihi")
@limiter.limit("10/minute")
def export_loihi(
    request: Request,
    response: Response,
    network_payload: dict[str, Any] = Body(
        ...,
        description="Accepts either raw NetworkInput JSON or a wrapped payload {'network': NetworkInput}.",
    ),
    bit_width: int = 8,
    board_id: str = "localhost",
    num_steps: int = 1000,
) -> Response:
    try:
        if "network" in network_payload and network_payload["network"] is not None:
            network_data = network_payload["network"]
        else:
            network_data = network_payload
        network = NetworkInput.model_validate(network_data)
        zip_bytes = loihi_generator.generate_loihi_package(
            network=network,
            bit_width=bit_width,
            board_id=board_id,
            num_steps=num_steps,
        )
        return Response(
            content=zip_bytes,
            media_type="application/zip",
            headers={
                "Content-Disposition": "attachment; filename=loihi_deploy.zip",
                **provenance_headers("scaffold_export"),
            },
        )
    except ValidationError as e:
        logger.warning("Validation error during export: %s", e)
        raise HTTPException(status_code=422, detail="Invalid network configuration.")
    except Exception:
        logger.exception("Unexpected error during package generation")
        raise HTTPException(
            status_code=500,
            detail="An internal server error occurred while generating the package.",
        )


@router.post("/pynq")
@limiter.limit("10/minute")
def export_pynq(
    request: Request,
    response: Response,
    network_payload: dict[str, Any] = Body(
        ...,
        description="Accepts either raw NetworkInput JSON or a wrapped payload {'network': NetworkInput}.",
    ),
    bit_width: int = 8,
) -> Response:
    try:
        if "network" in network_payload and network_payload["network"] is not None:
            network_data = network_payload["network"]
        else:
            network_data = network_payload
        network = NetworkInput.model_validate(network_data)
        PynqNetworkPayloadContract(
            num_neurons=network.num_neurons,
            num_synapses=network.num_synapses,
            neuron_model=network.neuron_model,
            weight_bit_width=bit_width,
            network_depth=network.network_depth,
            n_populations=len(network.populations),
        )
        quantized_weights = network_payload.get("quantized_weights")
    except ValidationError as e:
        logger.warning("Validation error during export: %s", e)
        raise HTTPException(status_code=422, detail="Invalid network configuration.")

    try:
        zip_bytes = pynq_generator.generate_pynq_package(
            network=network,
            bit_width=bit_width,
            quantized_weights=quantized_weights,
        )
        try:
            validate_pynq_compile_artifact(zip_bytes)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(
                status_code=500,
                detail={
                    "error": "pynq_artifact_validation_failed",
                    "message": (
                        "Generated PYNQ artifact failed internal validation. "
                        "This is a server-side bug and the artifact was not returned."
                    ),
                    "detail": str(exc),
                    "hint": "Report this to the NeuroChip maintainers with the network spec.",
                },
            ) from exc
        return Response(
            content=zip_bytes,
            media_type="application/zip",
            headers={
                "Content-Disposition": "attachment; filename=pynq_deploy.zip",
                **provenance_headers("artifact_validated"),
            },
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Unexpected error during package generation")
        raise HTTPException(
            status_code=500,
            detail={
                "error": "pynq_artifact_validation_failed",
                "message": (
                    "Generated PYNQ artifact failed internal validation. "
                    "This is a server-side bug and the artifact was not returned."
                ),
                "detail": str(exc),
                "hint": "Report this to the NeuroChip maintainers with the network spec.",
            },
        ) from exc


@router.post("/neuroml")
@limiter.limit("10/minute")
def export_neuroml(
    request: Request,
    response: Response,
    network: NetworkInput = Body(..., embed=True),
    bit_width: int = Query(16),
) -> Response:
    try:
        zip_bytes = neuroml_generator.generate_neuroml_package(
            network=network,
            bit_width=bit_width,
        )
        return Response(
            content=zip_bytes,
            media_type="application/zip",
            headers={
                "Content-Disposition": "attachment; filename=network_export.zip",
                **provenance_headers("scaffold_export"),
            },
        )
    except ValidationError as e:
        logger.warning("Validation error during export: %s", e)
        raise HTTPException(status_code=422, detail="Invalid network configuration.")
    except Exception:
        logger.exception("Unexpected error during package generation")
        raise HTTPException(
            status_code=500,
            detail="An internal server error occurred while generating the package.",
        )


@router.websocket("/ws/compile")
async def websocket_compile(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_json()
            target = data.get("target")
            network_data = data.get("network")

            if not target or not network_data:
                await websocket.send_json({"error": "Missing target or network data"})
                continue

            network = NetworkInput(**network_data)

            loop = asyncio.get_running_loop()

            def progress_callback_sync(progress: float, message: str) -> None:
                loop.create_task(websocket.send_json({"progress": progress, "message": message}))  # noqa: RUF006

            # Offload synchronous generators to a thread pool to avoid blocking the event loop
            if target == "teensy":
                try:
                    TeensyNetworkPayloadContract(
                        num_neurons=network.num_neurons,
                        num_synapses=network.num_synapses,
                        neuron_model=network.neuron_model,
                        weight_bit_width=network.weight_bit_width,
                        network_depth=network.network_depth,
                    )
                except ValidationError as e:
                    await websocket.send_json({"error": f"contract_violation: {e.errors()}"})
                    continue
                bit_width = data.get("bit_width", 8)
                await asyncio.to_thread(
                    teensy_generator.generate_teensy_project,
                    network=network,
                    bit_width=bit_width,
                    progress_callback=progress_callback_sync,
                )
            elif target == "loihi":
                bit_width = data.get("bit_width", 8)
                await asyncio.to_thread(
                    loihi_generator.generate_loihi_package,
                    network=network,
                    bit_width=bit_width,
                    progress_callback=progress_callback_sync,
                )
            elif target == "neuroml":
                bit_width = data.get("bit_width", 8)
                await asyncio.to_thread(
                    neuroml_generator.generate_neuroml_package,
                    network=network,
                    bit_width=bit_width,
                    progress_callback=progress_callback_sync,
                )
            elif target == "pynq":
                try:
                    PynqNetworkPayloadContract(
                        num_neurons=network.num_neurons,
                        num_synapses=network.num_synapses,
                        neuron_model=network.neuron_model,
                        weight_bit_width=data.get("bit_width", 8),
                        network_depth=network.network_depth,
                        n_populations=len(network.populations),
                    )
                except ValidationError as e:
                    await websocket.send_json({"error": f"contract_violation: {e.errors()}"})
                    continue
                bit_width = data.get("bit_width", 8)
                await asyncio.to_thread(
                    pynq_generator.generate_pynq_package,
                    network=network,
                    bit_width=bit_width,
                    progress_callback=progress_callback_sync,
                )
            else:
                await websocket.send_json({"error": f"Unsupported target: {target}"})

    except WebSocketDisconnect:
        pass
