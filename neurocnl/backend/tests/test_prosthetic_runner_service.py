from unittest.mock import MagicMock, patch

import pytest

from backend.app.schemas.prosthetic import ProstheticSimRequest
from backend.app.services.prosthetic_runner import run_drop_test


@pytest.mark.anyio
@patch(
    "backend.app.services.prosthetic_runner._ensure_prosthetic_runtime",
    return_value=False,
)
async def test_run_drop_test_no_mujoco(_mock_runtime):
    """Patch _ensure_prosthetic_runtime directly so the test is independent of
    whether neurodreamhand / MuJoCo is installed in the current environment."""
    req = ProstheticSimRequest(spec="test spec")
    result = run_drop_test(req)
    assert result["success"] is True
    assert result["grip_history"] == [0.1, 0.2, 0.5, 0.8, 1.0]
    assert result["slip_vz_history"] == [0.5, 0.4, 0.2, 0.1, 0.0]
    assert result["object_z_history"] == [0.15, 0.1, 0.05, 0.02, 0.01]
    assert result["stopping_distance_m"] == 0.14
    assert result["wall_time_seconds"] == 0.5


@pytest.mark.anyio
@patch("backend.app.services.prosthetic_runner._HAS_MUJOCO", True)
@patch("backend.app.services.prosthetic_runner.parse_spec_text")
async def test_run_drop_test_parse_failure(mock_parse):
    mock_parse.return_value = [{"valid": False, "error": "Parsing failed"}]
    req = ProstheticSimRequest(spec="invalid spec")
    with pytest.raises(ValueError, match="Some CNL sentences failed to parse:\nParsing failed"):
        run_drop_test(req)


@pytest.mark.anyio
@patch("backend.app.services.prosthetic_runner._HAS_MUJOCO", True)
@patch("backend.app.services.prosthetic_runner.parse_spec_text")
async def test_run_drop_test_empty_parsed(mock_parse):
    mock_parse.return_value = []
    req = ProstheticSimRequest(spec="empty spec")
    result = run_drop_test(req)
    assert result["success"] is False
    assert result["grip_history"] == []
    assert result["wall_time_seconds"] == 0.0


@pytest.mark.anyio
@patch("backend.app.services.prosthetic_runner._HAS_MUJOCO", True)
@patch("backend.app.services.prosthetic_runner.parse_spec_text")
@patch("backend.app.services.prosthetic_runner.default_params_from_specs")
@patch("backend.app.services.prosthetic_runner.SNNController", create=True)
@patch("backend.app.services.prosthetic_runner.PinchBridge", create=True)
async def test_run_drop_test_pinch_success(
    mock_pinch, mock_controller_cls, mock_default_params, mock_parse
):
    mock_parse.return_value = [{"valid": True, "parsed": {"concept": "test"}}]
    mock_default_params.return_value = {"synaptic_weight": 1.5, "tau": 0.03}

    mock_controller = MagicMock()
    mock_controller_cls.return_value = mock_controller

    mock_bridge = MagicMock()
    mock_bridge.run_drop_test.return_value = {
        "success": True,
        "grip_history": [0.1],
        "stopping_distance_m": 0.05,
    }
    mock_pinch.return_value = mock_bridge

    req = ProstheticSimRequest(
        spec="valid spec",
        gripper_type="pinch",
        n_neurons=100,
        seed=42,
        drop_height=0.2,
        duration=1.5,
    )

    result = run_drop_test(req)

    assert result["success"] is True
    assert result["grip_history"] == [0.1]
    assert result["stopping_distance_m"] == 0.05

    mock_controller_cls.assert_called_once_with(n_neurons=100, seed=42, kp=1.5, tau_fast=0.03)
    mock_pinch.assert_called_once_with(controller=mock_controller, drop_height=0.2)
    mock_bridge.run_drop_test.assert_called_once_with(duration=1.5)


@pytest.mark.anyio
@patch("backend.app.services.prosthetic_runner._HAS_MUJOCO", True)
@patch("backend.app.services.prosthetic_runner.parse_spec_text")
@patch("backend.app.services.prosthetic_runner.default_params_from_specs")
@patch("backend.app.services.prosthetic_runner.SNNController", create=True)
@patch("backend.app.services.prosthetic_runner.TripodBridge", create=True)
async def test_run_drop_test_tripod_success(
    mock_tripod, mock_controller_cls, mock_default_params, mock_parse
):
    mock_parse.return_value = [{"valid": True, "parsed": {"concept": "test"}}]
    mock_default_params.return_value = {"base": "params"}

    mock_bridge = MagicMock()
    mock_bridge.run_drop_test.return_value = {"success": True}
    mock_tripod.return_value = mock_bridge

    req = ProstheticSimRequest(spec="valid spec", gripper_type="tripod")
    run_drop_test(req)

    assert mock_tripod.called


@pytest.mark.anyio
@patch("backend.app.services.prosthetic_runner._HAS_MUJOCO", True)
@patch("backend.app.services.prosthetic_runner.parse_spec_text")
@patch("backend.app.services.prosthetic_runner.default_params_from_specs")
@patch("backend.app.services.prosthetic_runner.SNNController", create=True)
@patch("backend.app.services.prosthetic_runner.PinchBridge", create=True)
async def test_run_drop_test_controller_uses_default_params(
    mock_pinch, mock_controller_cls, mock_default_params, mock_parse
):
    mock_parse.return_value = [{"valid": True, "parsed": {"concept": "test"}}]
    params = {"synaptic_weight": 2.0, "tau": 0.04}
    mock_default_params.return_value = params

    mock_bridge = MagicMock()
    mock_bridge.run_drop_test.return_value = {"success": True}
    mock_pinch.return_value = mock_bridge

    req = ProstheticSimRequest(spec="valid spec", n_neurons=100)
    run_drop_test(req)

    mock_controller_cls.assert_called_once_with(n_neurons=100, seed=req.seed, kp=2.0, tau_fast=0.04)
