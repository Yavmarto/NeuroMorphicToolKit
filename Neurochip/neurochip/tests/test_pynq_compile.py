from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from neurochip.app.main import app
from neurochip.app.routers import pynq as pynq_router
from neurochip.app.services.pynq_compiler import (
    PynqCompileError,
    PynqCompilerService,
)
from neurochip.contracts.pynq_runtime_artifact_contract import (
    DEFAULT_OVERLAY_MANIFEST,
    PYNQ_OVERLAY_ID,
    validate_pynq_compile_artifact,
)

client = TestClient(app)


def _mock_network() -> dict[str, object]:
    return {
        "num_neurons": 10,
        "num_synapses": 20,
        "neuron_model": "lif",
        "populations": [{"name": "in", "size": 10}, {"name": "out", "size": 10}],
        "connections": [{"pre": "in", "post": "out", "weight_count": 20}],
        "weight_bit_width": 8,
        "network_depth": 1,
    }


def _valid_pynq_artifact_zip() -> bytes:
    response = client.post("/api/neurochip/export/pynq", json={"network": _mock_network()})
    assert response.status_code == 200, response.text
    from typing import cast

    return cast(bytes, response.content)


def _mock_successful_run(manifest_payload=None):
    def side_effect(command, **kwargs):
        request_path = None
        for i, arg in enumerate(command):
            if arg == "--request":
                request_path = Path(command[i + 1])
        if request_path:
            request = json.loads(request_path.read_text(encoding="utf-8"))
            output_dir = Path(request["output_dir"])
            output_dir.mkdir(parents=True, exist_ok=True)
            (output_dir / "snn_overlay.bit").write_bytes(b"bitstream")
            (output_dir / "snn_overlay.hwh").write_text("<hwh/>", encoding="utf-8")
            if manifest_payload is not None:
                (output_dir / "overlay_manifest.json").write_text(
                    json.dumps(manifest_payload),
                    encoding="utf-8",
                )
        return MagicMock(returncode=0, stdout="compiled", stderr="")

    return side_effect


def _mock_failing_run(*args, **kwargs):
    return MagicMock(returncode=1, stderr="vivado failed", stdout="")


def test_validate_pynq_compile_artifact_accepts_export_zip() -> None:
    artifact = validate_pynq_compile_artifact(_valid_pynq_artifact_zip())

    assert artifact.overlay_manifest.overlay_id == PYNQ_OVERLAY_ID
    assert artifact.overlay_config.network_name == "pynq_snn_network"
    assert artifact.total_neurons == 20
    assert artifact.total_synapses == 20


def test_pynq_compiler_service_stages_overlay_bundle(tmp_path: Path) -> None:
    service = PynqCompilerService(
        compiler_command="fake-finn",
        stage_dir=tmp_path / "overlay_staging" / "pynq_z2",
    )

    artifact = validate_pynq_compile_artifact(_valid_pynq_artifact_zip())
    with patch(
        "neurochip.app.services.pynq_compiler.subprocess.run",
        side_effect=_mock_successful_run(manifest_payload=artifact.overlay_manifest.model_dump()),
    ):
        result = service.compile_artifact(_valid_pynq_artifact_zip())

    assert result.compiler == "finn"
    assert result.overlay_id == PYNQ_OVERLAY_ID
    assert result.staged_overlay["ready"] is True
    assert Path(result.staged_overlay["bitstreamPath"]).exists()
    assert Path(result.staged_overlay["hwhPath"]).exists()
    assert Path(result.staged_overlay["manifestPath"]).exists()


def test_pynq_compiler_service_rejects_manifest_drift(tmp_path: Path) -> None:
    bad_manifest = dict(DEFAULT_OVERLAY_MANIFEST)
    bad_manifest["overlay_version"] = "9.9.9"
    service = PynqCompilerService(
        compiler_command="fake-finn",
        stage_dir=tmp_path / "overlay_staging" / "pynq_z2",
    )

    try:
        with patch(
            "neurochip.app.services.pynq_compiler.subprocess.run",
            side_effect=_mock_successful_run(manifest_payload=bad_manifest),
        ):
            service.compile_artifact(_valid_pynq_artifact_zip())
    except PynqCompileError as exc:
        assert exc.error_code in {
            "PYNQ_COMPILE_OUTPUT_INVALID",
            "PYNQ_COMPILE_MANIFEST_MISMATCH",
        }
    else:
        raise AssertionError("Expected manifest drift to be rejected")


def test_pynq_compile_endpoint_returns_200_for_staged_compile(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = PynqCompilerService(
        compiler_command="fake-finn",
        stage_dir=tmp_path / "overlay_staging" / "pynq_z2",
    )
    monkeypatch.setattr(pynq_router, "compile_service", service)
    artifact = _valid_pynq_artifact_zip()
    manifest = validate_pynq_compile_artifact(artifact).overlay_manifest.model_dump()

    with patch(
        "neurochip.app.services.pynq_compiler.subprocess.run",
        side_effect=_mock_successful_run(manifest_payload=manifest),
    ):
        response = client.post(
            "/hardware/pynq/compile",
            files={"artifact": ("pynq_deploy.zip", artifact, "application/zip")},
            data={"compiler": "finn"},
            headers={"X-API-Key": "test_key"},
        )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "compiled"
    assert body["compiler"] == "finn"
    assert body["staged_overlay"]["ready"] is True


def test_pynq_compile_endpoint_returns_503_when_compiler_unconfigured(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = PynqCompilerService(
        stage_dir=tmp_path / "overlay_staging" / "pynq_z2",
    )
    monkeypatch.setattr(pynq_router, "compile_service", service)

    with patch(
        "neurochip.app.services.pynq_compiler.subprocess.run", side_effect=_mock_successful_run()
    ):
        response = client.post(
            "/hardware/pynq/compile",
            files={"artifact": ("pynq_deploy.zip", _valid_pynq_artifact_zip(), "application/zip")},
            data={"compiler": "finn"},
            headers={"X-API-Key": "test_key"},
        )

    assert response.status_code == 503
    assert response.json()["detail"]["error_code"] == "PYNQ_FINN_COMPILER_NOT_CONFIGURED"


def test_pynq_compile_endpoint_returns_422_for_invalid_artifact(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = PynqCompilerService(
        compiler_command="fake-finn",
        stage_dir=tmp_path / "overlay_staging" / "pynq_z2",
    )
    monkeypatch.setattr(pynq_router, "compile_service", service)

    with patch(
        "neurochip.app.services.pynq_compiler.subprocess.run", side_effect=_mock_failing_run
    ):
        response = client.post(
            "/hardware/pynq/compile",
            files={"artifact": ("broken.zip", b"not-a-zip", "application/zip")},
            data={"compiler": "finn"},
            headers={"X-API-Key": "test_key"},
        )

    assert response.status_code == 422
    assert response.json()["detail"]["error_code"] == "PYNQ_COMPILE_ARTIFACT_INVALID"
