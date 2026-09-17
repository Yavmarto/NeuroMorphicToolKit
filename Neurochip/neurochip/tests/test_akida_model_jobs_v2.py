"""AkidaModelBundleV2 validation and job behaviour.

V2 carries an already-converted ``model.fbz`` from the canvas Akida Exporter
instead of an ONNX model. These tests pin the two things that make it a
different contract rather than a variant of V1 -- no quantization step, and a
near-chance floor in place of the 96% gate -- plus the archive-safety checks,
which must keep firing on the new branch because they are shared code that a
second validation path could easily have bypassed.
"""

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

from neurochip.app.services.akida_model_jobs import (
    AkidaModelJobError,
    AkidaModelJobService,
)
from neurochip.contracts.akida_model_bundle_contract import AkidaModelJobRequest

_FEATURES = 784
_SAMPLES = 8


class _FakeConvertedModel:
    """Stands in for a loaded ``akida.Model`` with the classifier activation off."""

    statistics: str | _FakeStatistics = "fps=456"

    def __init__(self, correct: int = _SAMPLES) -> None:
        self._correct = correct

    def predict(self, inputs: np.ndarray[Any, Any]) -> np.ndarray[Any, Any]:
        # Label i is correct for sample i; make the first `_correct` samples hit.
        count = len(inputs)
        outputs = np.zeros((count, 10), dtype=np.float32)
        for index in range(count):
            outputs[index, index % 10 if index < self._correct else 9] = 1.0
        return outputs


def _v2_bundle_bytes(
    *,
    unsafe_name: str | None = None,
    bad_checksum: bool = False,
    drop_sim_accuracy: bool = False,
    labels_out_of_range: bool = False,
) -> bytes:
    model = b"fake-fbz-payload"
    labels = np.arange(_SAMPLES, dtype=np.int32) % 10
    if labels_out_of_range:
        labels = labels + 100
    evaluation_buffer = io.BytesIO()
    np.savez_compressed(
        evaluation_buffer,
        inputs=np.zeros((_SAMPLES, 1, 1, _FEATURES), dtype=np.uint8),
        labels=labels,
    )
    payloads = {"model.fbz": model, "evaluation.npz": evaluation_buffer.getvalue()}
    source_metrics: dict[str, float] = {"snntorch_accuracy": 0.93}
    if not drop_sim_accuracy:
        source_metrics["akida_sim_accuracy"] = 0.88
    manifest = {
        "schemaVersion": 2,
        "bundleType": "nmtk.akida.model",
        "modelName": "model",
        "sourceFramework": "snntorch",
        "target": "akida2",
        "input": {"shape": [1, 1, 1, _FEATURES], "layout": "NHWC", "dtype": "uint8"},
        "preprocessing": {"scale": 15.0, "offset": 0.0, "evaluation_dtype": "uint8"},
        "labels": [str(index) for index in range(10)],
        "sourceMetrics": source_metrics,
        "dependencyVersions": {"torch": "2.7.0", "akida": "2.19.2"},
        "files": {
            name: (
                "0" * 64
                if bad_checksum and name == "model.fbz"
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
        filename="model.akida-bundle.zip",
        bundleBase64=base64.b64encode(bundle).decode("ascii"),
        sha256=hashlib.sha256(bundle).hexdigest(),
        requirePhysicalHardware=True,
    )


def test_v2_bundle_validates_without_calibration(tmp_path: Path) -> None:
    service = AkidaModelJobService(tmp_path)

    validated = service._validate_bundle(_v2_bundle_bytes())

    assert validated.manifest.schema_version == 2
    assert validated.is_preconverted is True
    assert validated.calibration is None
    assert validated.evaluation_inputs.shape == (_SAMPLES, 1, 1, _FEATURES)


def test_v2_bundle_still_rejects_zip_traversal(tmp_path: Path) -> None:
    service = AkidaModelJobService(tmp_path)

    with pytest.raises(AkidaModelJobError, match="unsafe file path") as error:
        service._validate_bundle(_v2_bundle_bytes(unsafe_name="../escape"))

    assert error.value.error_code == "BUNDLE_PATH_UNSAFE"


def test_v2_bundle_still_rejects_checksum_mismatch(tmp_path: Path) -> None:
    service = AkidaModelJobService(tmp_path)

    with pytest.raises(AkidaModelJobError, match="Checksum validation failed") as error:
        service._validate_bundle(_v2_bundle_bytes(bad_checksum=True))

    assert error.value.error_code == "BUNDLE_FILE_CHECKSUM_MISMATCH"


def test_v2_bundle_still_rejects_out_of_range_labels(tmp_path: Path) -> None:
    service = AkidaModelJobService(tmp_path)

    with pytest.raises(AkidaModelJobError) as error:
        service._validate_bundle(_v2_bundle_bytes(labels_out_of_range=True))

    assert error.value.error_code == "EVALUATION_LABEL_INVALID"


def test_v2_bundle_requires_its_simulator_accuracy(tmp_path: Path) -> None:
    service = AkidaModelJobService(tmp_path)

    with pytest.raises(AkidaModelJobError) as error:
        service._validate_bundle(_v2_bundle_bytes(drop_sim_accuracy=True))

    assert error.value.error_code == "SOURCE_METRICS_INCOMPLETE"


def test_v2_job_skips_quantization_and_reports_card_accuracy(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service = AkidaModelJobService(tmp_path)
    bundle = _v2_bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    job = service.submit(_request(bundle))

    def _explode(*_args: object) -> object:
        raise AssertionError("a converted bundle must never be quantized")

    monkeypatch.setattr(service, "_quantize", _explode)
    monkeypatch.setattr(service, "_convert", _explode)
    monkeypatch.setattr(service, "_load_preconverted", lambda _bundle, _dir: _FakeConvertedModel())
    monkeypatch.setattr(service, "_map_model", lambda _model, _req: ("hardware", "AKD1000"))

    AkidaModelJobService._run_job(service, job.job_id, bundle, True)

    completed = service.get(job.job_id)
    assert completed.stage.value == "completed"
    assert completed.hardware_verified is True
    assert completed.metrics["akida_accuracy"] == 1.0
    # The bundle's own simulator numbers survive alongside the card's.
    assert completed.metrics["akida_sim_accuracy"] == 0.88
    assert completed.metrics["snntorch_accuracy"] == 0.93


def test_v2_job_accepts_accuracy_that_v1_would_reject(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A converted spiking model at 50% must reach the card, not be refused."""
    service = AkidaModelJobService(tmp_path)
    bundle = _v2_bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    job = service.submit(_request(bundle))
    monkeypatch.setattr(
        service,
        "_load_preconverted",
        lambda _bundle, _dir: _FakeConvertedModel(correct=_SAMPLES // 2),
    )
    monkeypatch.setattr(service, "_map_model", lambda _model, _req: ("hardware", "AKD1000"))

    AkidaModelJobService._run_job(service, job.job_id, bundle, True)

    completed = service.get(job.job_id)
    assert completed.stage.value == "completed"
    assert completed.metrics["akida_accuracy"] == 0.5


def test_v2_job_fails_only_near_chance(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    service = AkidaModelJobService(tmp_path)
    bundle = _v2_bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    job = service.submit(_request(bundle))
    monkeypatch.setattr(
        service, "_load_preconverted", lambda _bundle, _dir: _FakeConvertedModel(correct=1)
    )
    monkeypatch.setattr(service, "_map_model", lambda _model, _req: ("hardware", "AKD1000"))

    AkidaModelJobService._run_job(service, job.job_id, bundle, True)

    failed = service.get(job.job_id)
    assert failed.stage.value == "failed"
    assert failed.error_code == "AKIDA_ACCURACY_NEAR_CHANCE"


def test_v2_model_survives_a_host_restart(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """A restarted service must reload a V2 model, not silently lose it.

    `_reload_model` re-validates the persisted bundle, so it inherits the V2
    branch -- but only if the job actually wrote `model.fbz` into the model
    directory, which is a different code path from V1's `model.save`.
    """
    # The real `_load_preconverted` runs here -- stubbing it would skip the
    # only thing this test is about.
    monkeypatch.setitem(
        __import__("sys").modules,
        "akida",
        type("_M", (), {"Model": staticmethod(lambda _p: _FakeConvertedModel())}),
    )
    service = AkidaModelJobService(tmp_path)
    bundle = _v2_bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    job = service.submit(_request(bundle))
    monkeypatch.setattr(service, "_map_model", lambda _model, _req: ("hardware", "AKD1000"))
    AkidaModelJobService._run_job(service, job.job_id, bundle, True)
    model_id = service.get(job.job_id).model_id
    assert model_id is not None
    assert (tmp_path / model_id / "model.fbz").is_file()

    restarted = AkidaModelJobService(tmp_path)
    monkeypatch.setattr(
        restarted,
        "_map_model",
        lambda _model, require_hardware=True: ("hardware", "AKD1000"),
    )
    model, reloaded_bundle = restarted._reload_model(model_id)

    assert model is not None
    assert reloaded_bundle is not None
    assert reloaded_bundle.is_preconverted is True


def test_v2_job_writes_the_fbz_where_reload_expects_it(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """`_load_preconverted` is the only writer of model.fbz on the V2 path."""
    service = AkidaModelJobService(tmp_path)
    bundle = _v2_bundle_bytes()
    validated = service._validate_bundle(bundle)
    model_dir = tmp_path / "model-under-test"
    model_dir.mkdir()

    import neurochip.app.services.akida_model_jobs as jobs_module

    class _FakeAkidaModule:
        @staticmethod
        def Model(path: str) -> str:  # noqa: N802 - mirrors the SDK's name
            return f"loaded:{path}"

    monkeypatch.setitem(__import__("sys").modules, "akida", _FakeAkidaModule)
    loaded = jobs_module.AkidaModelJobService._load_preconverted(validated, model_dir)

    assert (model_dir / "model.fbz").read_bytes() == b"fake-fbz-payload"
    assert loaded == f"loaded:{model_dir / 'model.fbz'}"


class _FakeStatistics:
    """An SDK statistics object, unlike the plain string `_FakeConvertedModel` uses."""

    def __init__(self, fps: float | None, power: float | None) -> None:
        self.fps = fps
        self.power = power
        self.reset_calls = 0

    def reset(self) -> None:
        self.reset_calls += 1


class _TimedConvertedModel(_FakeConvertedModel):
    """A converted model that also exposes real numeric SDK telemetry."""

    def __init__(self, statistics: _FakeStatistics) -> None:
        super().__init__()
        self.statistics = statistics


def _deployed_service(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    model: object | None = None,
) -> tuple[AkidaModelJobService, str]:
    """Run a V2 job to completion and return the service plus its model id."""
    service = AkidaModelJobService(tmp_path)
    bundle = _v2_bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    job = service.submit(_request(bundle))
    monkeypatch.setattr(
        service,
        "_load_preconverted",
        lambda _bundle, _dir: model if model is not None else _FakeConvertedModel(),
    )
    monkeypatch.setattr(service, "_map_model", lambda _model, _req: ("hardware", "AKD1000"))
    AkidaModelJobService._run_job(service, job.job_id, bundle, True)
    completed = service.get(job.job_id)
    assert completed.model_id is not None
    return service, completed.model_id


def test_evaluation_reports_sample_count_latency_and_per_class(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service, _model_id = _deployed_service(tmp_path, monkeypatch)
    job = next(iter(service._jobs.values()))

    assert job.total_samples == _SAMPLES
    assert job.metrics["total_samples"] == float(_SAMPLES)
    # Timing is wall-clock so the value is machine-dependent; only its presence
    # and sign are contractual.
    assert job.metrics["latency_ms"] > 0
    assert job.metrics["fps"] > 0

    assert job.class_results is not None
    assert sum(result.support for result in job.class_results) == _SAMPLES
    assert sum(result.correct for result in job.class_results) == _SAMPLES
    # 8 samples over 10 labels, so the last two classes have no support and must
    # report None rather than a misleading 0%.
    assert [result.accuracy for result in job.class_results[8:]] == [None, None]


def test_power_is_absent_unless_the_sdk_reports_it(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A missing power reading must not become a zero: estimates are not measurements."""
    service, _model_id = _deployed_service(tmp_path, monkeypatch)
    job = next(iter(service._jobs.values()))

    # _FakeConvertedModel.statistics is the string "fps=456", which exposes no
    # numeric attributes at all.
    assert "power_mw" not in job.metrics
    assert "sdk_fps" not in job.metrics


def test_numeric_sdk_statistics_are_captured_and_reset(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    statistics = _FakeStatistics(fps=456.0, power=812.5)
    service, _model_id = _deployed_service(
        tmp_path, monkeypatch, model=_TimedConvertedModel(statistics)
    )
    job = next(iter(service._jobs.values()))

    assert job.metrics["sdk_fps"] == 456.0
    assert job.metrics["power_mw"] == 812.5
    # Without a reset the figures would cover every inference since mapping.
    assert statistics.reset_calls == 1


def test_benchmark_reruns_instead_of_returning_the_original_job(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Re-submitting a bundle dedupes; the benchmark path must not."""
    service, model_id = _deployed_service(tmp_path, monkeypatch)
    original_job_id = next(iter(service._jobs))

    monkeypatch.setattr(service, "_run_benchmark", lambda *_args: None)
    started = service.benchmark(model_id)
    assert started.job_id != original_job_id
    assert started.model_id == model_id
    assert started.stage.value == "evaluation"

    model, bundle, _target = service._resident_model(model_id)
    AkidaModelJobService._run_benchmark(service, started.job_id, model_id, model, bundle)

    finished = service.get(started.job_id)
    assert finished.stage.value == "completed"
    assert finished.total_samples == _SAMPLES
    assert finished.metrics["akida_accuracy"] == 1.0
    assert finished.metrics["latency_ms"] > 0
    # The original job is untouched, so a benchmark never rewrites deploy history.
    assert service.get(original_job_id).job_id == original_job_id


def test_benchmark_survives_a_resubmit_of_the_same_bundle(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The dedupe still applies to submit(), which is why benchmark() exists."""
    service, model_id = _deployed_service(tmp_path, monkeypatch)
    original_job_id = next(iter(service._jobs))

    resubmitted = service.submit(_request(_v2_bundle_bytes()))
    assert resubmitted.job_id == original_job_id

    monkeypatch.setattr(service, "_run_benchmark", lambda *_args: None)
    assert service.benchmark(model_id).job_id != original_job_id


def test_benchmarking_an_unloaded_model_says_how_to_recover(tmp_path: Path) -> None:
    service = AkidaModelJobService(tmp_path)

    with pytest.raises(AkidaModelJobError) as error:
        service.benchmark("not-a-model")

    assert error.value.error_code == "MODEL_NOT_LOADED"
    # The message has to name the fix; "failed" alone leaves the user stuck.
    assert "Submit the bundle again" in str(error.value)


class _WedgedConvertedModel:
    """A converted model whose predict() raises the wedged-PCIe-card signature."""

    statistics = "fps=456"

    def predict(self, _inputs: np.ndarray[Any, Any]) -> np.ndarray[Any, Any]:
        raise RuntimeError("Error reading at 0xfcc20024 len: 4 errno(110): Connection timed out")


def test_v2_job_fails_with_device_unresponsive_not_conversion_failed_when_wedged(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service = AkidaModelJobService(tmp_path)
    bundle = _v2_bundle_bytes()
    monkeypatch.setattr(service, "_run_job", lambda *_args: None)
    job = service.submit(_request(bundle))
    monkeypatch.setattr(
        service, "_load_preconverted", lambda _bundle, _dir: _WedgedConvertedModel()
    )
    monkeypatch.setattr(service, "_map_model", lambda _model, _req: ("hardware", "AKD1000"))

    AkidaModelJobService._run_job(service, job.job_id, bundle, True)

    failed = service.get(job.job_id)
    assert failed.stage.value == "failed"
    assert failed.error_code == "AKIDA_DEVICE_UNRESPONSIVE"
    assert "Switch the host fully off and on again" in failed.message


def test_benchmark_fails_with_device_unresponsive_not_benchmark_failed_when_wedged(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service, model_id = _deployed_service(tmp_path, monkeypatch)

    monkeypatch.setattr(service, "_run_benchmark", lambda *_args: None)
    started = service.benchmark(model_id)
    model, bundle, _target = service._resident_model(model_id)
    monkeypatch.setattr(model, "predict", _WedgedConvertedModel().predict)

    AkidaModelJobService._run_benchmark(service, started.job_id, model_id, model, bundle)

    finished = service.get(started.job_id)
    assert finished.stage.value == "failed"
    assert finished.error_code == "AKIDA_DEVICE_UNRESPONSIVE"
    assert "Switch the host fully off and on again" in finished.message
