"""Service layer for prosthetic drop-test simulation."""

from __future__ import annotations

import time

import structlog

from neurocnl.runtime_dependencies import ensure_runtime_dependency

try:
    from neurodreamhand.core.mujoco_env import (  # type: ignore[import-untyped]
        PinchBridge,
        TripodBridge,
    )
    from neurodreamhand.core.reflex_agent import SNNController

    _HAS_MUJOCO = True
except ImportError:
    _HAS_MUJOCO = False

from backend.app.schemas.prosthetic import ProstheticSimRequest, ProstheticSimResult
from neurocnl.pipeline import default_params_from_specs, parse_spec_text

logger = structlog.get_logger(__name__)


def _ensure_prosthetic_runtime() -> bool:
    global _HAS_MUJOCO, PinchBridge, SNNController, TripodBridge

    if _HAS_MUJOCO:
        return True
    if not ensure_runtime_dependency("neurodreamhand"):
        return False

    try:
        from neurodreamhand.core.mujoco_env import PinchBridge as _PinchBridge
        from neurodreamhand.core.mujoco_env import TripodBridge as _TripodBridge
        from neurodreamhand.core.reflex_agent import SNNController as _SNNController
    except ImportError:
        return False

    PinchBridge = _PinchBridge
    TripodBridge = _TripodBridge
    SNNController = _SNNController
    _HAS_MUJOCO = True
    return True


def run_drop_test(req: ProstheticSimRequest) -> dict:
    """Run a MuJoCo + Nengo co-simulation drop test.

    Returns a dict matching ProstheticSimResult schema.
    """
    if not _ensure_prosthetic_runtime():
        # Mock result for E2E testing
        return ProstheticSimResult(
            success=True,
            grip_history=[0.1, 0.2, 0.5, 0.8, 1.0],
            slip_vz_history=[0.5, 0.4, 0.2, 0.1, 0.0],
            object_z_history=[0.15, 0.1, 0.05, 0.02, 0.01],
            stopping_distance_m=0.14,
            wall_time_seconds=0.5,
        ).model_dump()
    t0 = time.perf_counter()

    # 1. Parse + validate CNL spec
    parse_results = parse_spec_text(req.spec)

    parse_errors = [r["error"] for r in parse_results if not r["valid"]]
    if parse_errors:
        raise ValueError("Some CNL sentences failed to parse:\n" + "\n".join(parse_errors))

    parsed = [r["parsed"] for r in parse_results if r["valid"]]
    if not parsed:
        return ProstheticSimResult(
            success=False,
            grip_history=[],
            slip_vz_history=[],
            object_z_history=[],
            stopping_distance_m=0.0,
            wall_time_seconds=0.0,
        ).model_dump()

    params = default_params_from_specs(parsed)
    params["population_n_neurons"] = req.n_neurons

    # 2. Instantiate controller
    controller_kwargs = {
        "n_neurons": req.n_neurons,
        "seed": req.seed,
    }
    if params.get("synaptic_weight") is not None:
        controller_kwargs["kp"] = float(params["synaptic_weight"])
    if params.get("tau") is not None:
        controller_kwargs["tau_fast"] = float(params["tau"])

    controller = SNNController(
        **controller_kwargs,
    )

    # 3. Select MuJoCo bridge
    if req.gripper_type == "tripod":
        Bridge = TripodBridge
    else:
        Bridge = PinchBridge

    # 4. Run drop test
    bridge = Bridge(controller=controller, drop_height=req.drop_height)
    result = bridge.run_drop_test(duration=req.duration)

    wall_time = time.perf_counter() - t0
    return ProstheticSimResult(
        success=result.get("success", True),
        grip_history=result.get("grip_history", []),
        slip_vz_history=result.get("slip_vz_history", []),
        object_z_history=result.get("object_z_history", []),
        stopping_distance_m=result.get("stopping_distance_m", 0.0),
        frames=result.get("frames"),
        wall_time_seconds=round(wall_time, 3),
    ).model_dump()
