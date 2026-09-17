"""AkidaModelBundleV1 validation, security, and retry-safety tests."""

from __future__ import annotations

import base64
import hashlib
import io
import json
import zipfile
from pathlib import Path
from typing import Any

import numpy as np
import pytest
from fastapi.testclient import TestClient

from neurochip.app.main import app
from neurochip.app.routers import akida as akida_router
from neurochip.app.services.akida_model_jobs import (
    AkidaModelJobError,
    AkidaModelJobService,
)
from neurochip.contracts.akida_model_bundle_contract import (
    AkidaModelInferenceRequest,
    AkidaModelJobRequest,
    AkidaModelJobStage,
    AkidaModelJobStatus,
)


class _FakeAkidaModel:
    statistics = "fps=123"

    def save(self, path: str) -> None:
        Path(path).write_bytes(b"fake-fbz")

    def evaluate(self, _inputs: np.ndarray[Any, Any], _labels: np.ndarray[Any, Any]) -> float:
        return 0.97

    def predict(self, _inputs: np.ndarray[Any, Any]) -> np.ndarray[Any, Any]:
        return np.asarray([[0.0, 1.0] + [0.0] * 8], dtype=np.float32)


_WEDGED_BOARD_MESSAGE = "Error reading at 0xfcc20024 len: 4 errno(110): Connection timed out"


class _WedgedPredictAkidaModel(_FakeAkidaModel):
    """predict() raises the wedged-PCIe-card RuntimeError signature."""

    def predict(self, _inputs: np.ndarray[Any, Any]) -> np.ndarray[Any, Any]:
        raise RuntimeError(_WEDGED_BOARD_MESSAGE)


class _WedgedEvaluateAkidaModel(_FakeAkidaModel):
    """evaluate() raises the wedged-PCIe-card RuntimeError signature."""

    def evaluate(self, _inputs: np.ndarray[Any, Any], _labels: np.ndarray[Any, Any]) -> float:
        raise RuntimeError(_WEDGED_BOARD_MESSAGE)


class _GenericRuntimeErrorAkidaModel(_FakeAkidaModel):
    """evaluate() raises an unrelated RuntimeError, not the wedge signature."""

    def evaluate(self, _inputs: np.ndarray[Any, Any], _labels: np.ndarray[Any, Any]) -> float:
        raise RuntimeError("unexpected internal SDK state")


def _bundle_bytes(*, unsafe_name: str | None = None, bad_checksum: bool = False) -> bytes:
    model = b"fake-onnx"
    calibration_buffer = io.BytesIO()
    np.save(calibration_buffer, np.zeros((128, 1, 28, 28), dtype=np.float32))
    evaluation_buffer = io.BytesIO()
    np.savez_compressed(
        evaluation_buffer,
        inputs=np.zeros((4, 1, 28, 28), dtype=np.uint8),
        labels=np.zeros(4, dtype=np.int32),
    )
    payloads = {
        "model.onnx": model,
        "calibration.npy": calibration_buffer.getvalue(),
        "evaluation.npz": evaluation_buffer.getvalue(),
    }
    manifest = {
        "schemaVersion": 1,
        "bundleType": "nmtk.akida.model",
        "modelName": "MNIST CNN",
        "sourceFramework": "pytorch",
        "target": "akida2",
        "input": {"shape": [1, 1, 28, 28], "layout": "NCHW", "dtype": "float32"},
        "preprocessing": {"scale": 0.00784313725490196, "offset": -1.0},
        "labels": [str(index) for index in range(10)],
        "sourceMetrics": {"pytorch_accuracy": 0.99, "onnx_accuracy": 0.99},
        "dependencyVersions": {"torch": "2.7.0"},
        "files": {
            name: (
                "0" * 64
                if bad_checksum and name == "model.onnx"
                else hashlib.sha256(data).hexdigest()
            )
            for name, data in payloads.items()
        },
    }
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("manifest.json", json.dumps(manifest))
        for name, data in payloads.items():
            archive.writestr(name, data)
        if unsafe_name is not None:
            archive.writestr(unsafe_name, b"unsafe")
    return output.getvalue()


def _request(bundle: bytes) -> AkidaModelJobRequest:
    return AkidaModelJobRequest(
        filename="mnist.akida-bundle.zip",
        bundleBase64=base64.b64encode(bundle).decode("ascii"),
        sha256=hashlib.sha256(bundle).hexdigest(),
        requirePhysicalHardware=True,
    )


def test_bundle_validation_accepts_versioned_arrays(tmp_path: Path) -> None:
    service = AkidaModelJobService(tmp_path)

    validated = service._validate_bundle(_bundle_bytes())

    assert validated.manifest.schema_version == 1
    assert validated.calibration is not None
    assert validated.calibration.shape == (128, 1, 28, 28)
    assert validated.evaluation_inputs.dtype == np.uint8


def test_bundle_rejects_zip_traversal(tmp_path: Path) -> None:
    service = AkidaModelJobService(tmp_path)

    with pytest.raises(AkidaModelJobError, match="unsafe file path") as error:
        service._validate_bundle(_bundle_bytes(unsafe_name="../escape"))

    assert error.value.error_code == "BUNDLE_PATH_UNSAFE"


def test_bundle_rejects_payload_checksum_mismatch(tmp_path: Path) -> None:
    service = AkidaModelJobService(tmp_path)

    with pytest.raises(AkidaModelJobError, match="Checksum validation failed") as error:
        service._validate_bundle(_bundle_bytes(bad_checksum=True))

    assert error.value.error_code == "BUNDLE_FILE_CHECKSUM_MISMATCH"


def test_submit_deduplicates_active_job_by_checksum(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service = AkidaModelJobService(tmp_path)
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    request = _request(_bundle_bytes())

    first = service.submit(request)
    second = service.submit(request)

    assert second.job_id == first.job_id
    assert len(service._jobs) == 1


def test_interrupted_persisted_job_is_retryable(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    first_service = AkidaModelJobService(tmp_path)
    monkeypatch.setattr(first_service, "_run_job", lambda *_args: None)
    first = first_service.submit(_request(_bundle_bytes()))

    restarted = AkidaModelJobService(tmp_path)
    interrupted = restarted.get(first.job_id)
    assert interrupted.stage.value == "failed"
    assert interrupted.error_code == "JOB_INTERRUPTED"
    monkeypatch.setattr(restarted, "_run_job", lambda *_args: None)
    retry = restarted.submit(_request(_bundle_bytes()))
    assert retry.job_id != first.job_id


def test_submit_rejects_outer_checksum_mismatch(tmp_path: Path) -> None:
    service = AkidaModelJobService(tmp_path)
    request = _request(_bundle_bytes()).model_copy(update={"sha256": "0" * 64})

    with pytest.raises(AkidaModelJobError, match="changed during transfer") as error:
        service.submit(request)

    assert error.value.error_code == "BUNDLE_CHECKSUM_MISMATCH"


def test_completed_hardware_job_persists_and_deduplicates(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service = AkidaModelJobService(tmp_path)
    bundle = _bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    first = service.submit(_request(bundle))
    monkeypatch.setattr(service, "_quantize", lambda _bundle: object())
    monkeypatch.setattr(service, "_convert", lambda _quantized: _FakeAkidaModel())
    monkeypatch.setattr(service, "_map_model", lambda _model, _required: ("hardware", "AKD1000"))

    AkidaModelJobService._run_job(service, first.job_id, bundle, True)

    completed = service.get(first.job_id)
    assert completed.model_id is not None
    assert completed.stage.value == "completed"
    assert completed.hardware_verified is True
    assert completed.metrics["akida_accuracy"] == 0.97
    assert (tmp_path / completed.model_id / "model.fbz").is_file()
    reloaded = AkidaModelJobService(tmp_path)
    duplicate = reloaded.submit(_request(bundle))
    assert duplicate.job_id == first.job_id
    assert duplicate.stage.value == "completed"


def test_job_fails_closed_when_physical_hardware_is_absent(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service = AkidaModelJobService(tmp_path)
    bundle = _bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    job = service.submit(_request(bundle))
    monkeypatch.setattr(service, "_quantize", lambda _bundle: object())
    monkeypatch.setattr(service, "_convert", lambda _quantized: _FakeAkidaModel())
    monkeypatch.setattr(
        service,
        "_map_model",
        lambda _model, _required: (_ for _ in ()).throw(
            AkidaModelJobError(
                "PHYSICAL_HARDWARE_REQUIRED", "No physical Akida device is available."
            )
        ),
    )

    AkidaModelJobService._run_job(service, job.job_id, bundle, True)

    failed = service.get(job.job_id)
    assert failed.stage.value == "failed"
    assert failed.error_code == "PHYSICAL_HARDWARE_REQUIRED"
    assert failed.hardware_verified is False


def test_simulator_inference_never_claims_hardware_verification(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service = AkidaModelJobService(tmp_path)
    bundle = _bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    request = _request(bundle).model_copy(update={"require_physical_hardware": False})
    job = service.submit(request)
    monkeypatch.setattr(service, "_quantize", lambda _bundle: object())
    monkeypatch.setattr(service, "_convert", lambda _quantized: _FakeAkidaModel())
    monkeypatch.setattr(
        service,
        "_map_model",
        lambda _model, _required: ("akd1000_simulator", "AKD1000 simulator"),
    )

    AkidaModelJobService._run_job(service, job.job_id, bundle, False)
    completed = service.get(job.job_id)
    assert completed.model_id is not None
    result = service.infer(
        completed.model_id,
        AkidaModelInferenceRequest(sampleIndex=0),
    )

    assert completed.runtime_target == "akd1000_simulator"
    assert completed.hardware_verified is False
    assert result.runtime_target == "akd1000_simulator"
    assert result.hardware_verified is False


def test_sdk_import_failure_has_actionable_error_code(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service = AkidaModelJobService(tmp_path)
    bundle = _bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    job = service.submit(_request(bundle))
    monkeypatch.setattr(
        service,
        "_quantize",
        lambda _bundle: (_ for _ in ()).throw(ImportError("quantizeml missing")),
    )

    AkidaModelJobService._run_job(service, job.job_id, bundle, True)

    failed = service.get(job.job_id)
    assert failed.stage.value == "failed"
    assert failed.error_code == "AKIDA_CONVERSION_DEPENDENCY_MISSING"
    assert "quantizeml missing" not in failed.message


def test_model_job_endpoints_preserve_aliases_and_actionable_errors(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client = TestClient(app)
    accepted = AkidaModelJobStatus(
        jobId="job-1",
        bundleSha256="a" * 64,
        stage=AkidaModelJobStage.VALIDATION,
        progress=0,
        message="Validating model bundle.",
    )
    monkeypatch.setattr(akida_router.akida_model_job_service, "submit", lambda _request: accepted)
    response = client.post(
        "/api/neurochip/akida/model-jobs",
        json={
            "filename": "mnist.akida-bundle.zip",
            "bundleBase64": "UEs=",
            "sha256": "a" * 64,
            "requirePhysicalHardware": True,
        },
    )
    assert response.status_code == 202
    assert response.json()["jobId"] == "job-1"
    assert response.json()["hardwareVerified"] is False

    monkeypatch.setattr(
        akida_router.akida_model_job_service,
        "get",
        lambda _job_id: (_ for _ in ()).throw(KeyError("missing")),
    )
    missing = client.get("/api/neurochip/akida/model-jobs/missing")
    assert missing.status_code == 404
    assert missing.json()["detail"]["error_code"] == "MODEL_JOB_NOT_FOUND"


def test_infer_reports_device_unresponsive_when_card_is_wedged(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service = AkidaModelJobService(tmp_path)
    bundle = _bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    job = service.submit(_request(bundle))
    monkeypatch.setattr(service, "_quantize", lambda _bundle: object())
    monkeypatch.setattr(service, "_convert", lambda _quantized: _WedgedPredictAkidaModel())
    monkeypatch.setattr(service, "_map_model", lambda _model, _required: ("hardware", "AKD1000"))

    AkidaModelJobService._run_job(service, job.job_id, bundle, True)
    completed = service.get(job.job_id)
    assert completed.model_id is not None

    with pytest.raises(AkidaModelJobError) as error:
        service.infer(completed.model_id, AkidaModelInferenceRequest(sampleIndex=0))

    assert error.value.error_code == "AKIDA_DEVICE_UNRESPONSIVE"
    assert "Switch the host fully off and on again" in str(error.value)


def test_inference_endpoint_reports_wedged_board_not_generic_500(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service = AkidaModelJobService(tmp_path)
    bundle = _bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    job = service.submit(_request(bundle))
    monkeypatch.setattr(service, "_quantize", lambda _bundle: object())
    monkeypatch.setattr(service, "_convert", lambda _quantized: _WedgedPredictAkidaModel())
    monkeypatch.setattr(service, "_map_model", lambda _model, _required: ("hardware", "AKD1000"))
    AkidaModelJobService._run_job(service, job.job_id, bundle, True)
    completed = service.get(job.job_id)

    monkeypatch.setattr(akida_router, "akida_model_job_service", service)
    client = TestClient(app)
    response = client.post(
        f"/api/neurochip/akida/models/{completed.model_id}/inference",
        json={"sampleIndex": 0},
    )

    assert response.status_code == 422
    detail = response.json()["detail"]
    assert detail["error_code"] == "AKIDA_DEVICE_UNRESPONSIVE"
    assert "Switch the host fully off and on again" in detail["message"]


def test_job_fails_with_device_unresponsive_not_conversion_failed_when_wedged(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service = AkidaModelJobService(tmp_path)
    bundle = _bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    job = service.submit(_request(bundle))
    monkeypatch.setattr(service, "_quantize", lambda _bundle: object())
    monkeypatch.setattr(service, "_convert", lambda _quantized: _WedgedEvaluateAkidaModel())
    monkeypatch.setattr(service, "_map_model", lambda _model, _required: ("hardware", "AKD1000"))

    AkidaModelJobService._run_job(service, job.job_id, bundle, True)

    failed = service.get(job.job_id)
    assert failed.stage.value == "failed"
    assert failed.error_code == "AKIDA_DEVICE_UNRESPONSIVE"
    assert "Switch the host fully off and on again" in failed.message


def test_job_keeps_conversion_failed_for_unrelated_runtime_errors(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service = AkidaModelJobService(tmp_path)
    bundle = _bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    job = service.submit(_request(bundle))
    monkeypatch.setattr(service, "_quantize", lambda _bundle: object())
    monkeypatch.setattr(service, "_convert", lambda _quantized: _GenericRuntimeErrorAkidaModel())
    monkeypatch.setattr(service, "_map_model", lambda _model, _required: ("hardware", "AKD1000"))

    AkidaModelJobService._run_job(service, job.job_id, bundle, True)

    failed = service.get(job.job_id)
    assert failed.error_code == "AKIDA_CONVERSION_FAILED"
