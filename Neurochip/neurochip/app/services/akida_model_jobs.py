"""Akida bundle conversion job lifecycle: submit, track, benchmark, replay.

Bundle validation, conversion, and evaluation scoring live in
``akida_model_bundle.py`` (``AkidaBundleArtifactsMixin``, mixed into
``AkidaModelJobService`` below) so this module can stay focused on the job
state machine: the ``_jobs``/``_models``/``_bundles`` registries, their
locking, background-thread dispatch, and persistence to disk.
"""

from __future__ import annotations

import base64
import collections
import hashlib
import logging
import os
import re
import threading
import uuid
from pathlib import Path
from typing import Any

try:
    import numpy as np
except ImportError:  # Optional at startup; conversion jobs report their own requirements.
    np = None  # type: ignore[assignment]
from pydantic import ValidationError

from ...contracts.akida_model_bundle_contract import (
    AKIDA_MODEL_BUNDLE_MAX_BYTES,
    AkidaModelInferenceRequest,
    AkidaModelInferenceResult,
    AkidaModelJobRequest,
    AkidaModelJobStage,
    AkidaModelJobStatus,
    AkidaModelVisualizationRequest,
    AkidaModelVisualizationResult,
    AkidaVisualizationMode,
)
from .akida_model_bundle import (
    AkidaBundleArtifactsMixin,
    _ValidatedBundle,
)
from .akida_model_bundle import (
    AkidaModelJobError as AkidaModelJobError,
)

logger = logging.getLogger(__name__)

_VISUALIZATION_CACHE_SIZE = 32

# Signature of a wedged AKD1000 PCIe card surfacing through the Akida SDK: a
# bare errno wrapper as the SDK/driver writes it ("err(110)", "errno(110)") or
# a hex register address from a raw device read/write, e.g. "Error reading at
# 0xfcc20024 len: 4 errno(110): Connection timed out". Matching the shape
# rather than a specific errno avoids a list of numbers that has to grow every
# time the SDK gains a new failure. Duplicated from
# nmtk/launcher_control/akida_host_service.py's _RAW_DEVICE_ERROR_PATTERN
# (different package, no cross-import) -- keep the two in sync if the
# driver's error shape ever changes.
_RAW_DEVICE_ERROR_PATTERN = re.compile(r"\berr(?:no)?\(\d+\)|\b0x[0-9a-fA-F]{4,}\b")

_DEVICE_UNRESPONSIVE_MESSAGE = (
    "The Akida board could not be reached. Switch the host fully off and on again, then re-check."
)
_CONVERSION_FAILED_MESSAGE = (
    "Akida conversion failed; update the host runtime and retry the bundle."
)
_BENCHMARK_FAILED_MESSAGE = (
    "The benchmark run failed on the host; check the Akida device and retry."
)


def _device_unresponsive_error(exc: RuntimeError) -> AkidaModelJobError | None:
    """Recognize a wedged-card RuntimeError and translate it, or return None.

    ``model.predict``/``model.evaluate`` raise a bare ``RuntimeError`` from
    inside the Akida SDK when the PCIe card is wedged (PCI COMMAND register
    reads 0x0000). Left uncaught this reaches the router as an unhandled
    exception (falling through to the generic 500) or the job pipeline's
    catch-all, which blames "conversion" or "the benchmark run" regardless of
    which stage actually failed. Only this specific signature is translated;
    any other RuntimeError returns None so real bugs are not swallowed under a
    hardware message that doesn't apply to them.
    """
    if not _RAW_DEVICE_ERROR_PATTERN.search(str(exc)):
        return None
    return AkidaModelJobError("AKIDA_DEVICE_UNRESPONSIVE", _DEVICE_UNRESPONSIVE_MESSAGE)


class AkidaModelJobService(AkidaBundleArtifactsMixin):
    """Validate, convert, persist, map, and evaluate Akida model bundles."""

    def __init__(self, storage_dir: Path | None = None) -> None:
        data_dir = Path(os.getenv("NMTK_DATA_DIR", os.getenv("TMPDIR", "/tmp")))
        default_dir = data_dir / "akida-models"
        self._storage_dir = storage_dir or Path(
            os.getenv("NEUROCHIP_AKIDA_MODEL_DIR", str(default_dir))
        )
        self._storage_dir.mkdir(parents=True, exist_ok=True)
        self._jobs: dict[str, AkidaModelJobStatus] = {}
        self._job_by_checksum: dict[str, str] = {}
        self._models: dict[str, Any] = {}
        self._bundles: dict[str, _ValidatedBundle] = {}
        self._model_targets: dict[str, tuple[str, str | None]] = {}
        # model_id is only the first 24 chars of the bundle digest, so the full
        # checksum cannot be recovered from it. A benchmark job still has to
        # report which bundle it measured, hence this map.
        self._bundle_checksums: dict[str, str] = {}
        self._visualization_cache: collections.OrderedDict[
            tuple[str, AkidaVisualizationMode, int, int | None],
            AkidaModelVisualizationResult,
        ] = collections.OrderedDict()
        self._lock = threading.RLock()
        self._load_persisted_jobs()

    def submit(self, request: AkidaModelJobRequest) -> AkidaModelJobStatus:
        """Start a job, or return the existing retry-safe checksum match."""
        try:
            bundle_bytes = base64.b64decode(request.bundle_base64, validate=True)
        except ValueError as exc:
            raise AkidaModelJobError(
                "BUNDLE_BASE64_INVALID", "The selected model bundle is not valid base64."
            ) from exc
        if len(bundle_bytes) > AKIDA_MODEL_BUNDLE_MAX_BYTES:
            raise AkidaModelJobError(
                "BUNDLE_TOO_LARGE",
                "The selected model bundle exceeds the 32 MB upload limit.",
            )
        checksum = hashlib.sha256(bundle_bytes).hexdigest()
        if checksum != request.sha256.lower():
            raise AkidaModelJobError(
                "BUNDLE_CHECKSUM_MISMATCH",
                "The model bundle changed during transfer; select it again and retry.",
            )

        with self._lock:
            previous_id = self._job_by_checksum.get(checksum)
            if previous_id is not None:
                previous = self._jobs[previous_id]
                if previous.stage != AkidaModelJobStage.FAILED:
                    return previous.model_copy(deep=True)
                self._job_by_checksum.pop(checksum, None)
            job_id = uuid.uuid4().hex
            status = AkidaModelJobStatus(
                jobId=job_id,
                bundleSha256=checksum,
                stage=AkidaModelJobStage.VALIDATION,
                progress=0,
                message="Validating model bundle.",
            )
            self._jobs[job_id] = status
            self._job_by_checksum[checksum] = job_id
            self._persist_status(status)

        worker = threading.Thread(
            target=self._run_job,
            args=(job_id, bundle_bytes, request.require_physical_hardware),
            name=f"akida-model-job-{job_id[:8]}",
            daemon=True,
        )
        worker.start()
        return status.model_copy(deep=True)

    def get(self, job_id: str) -> AkidaModelJobStatus:
        """Return a snapshot of one job."""
        with self._lock:
            status = self._jobs.get(job_id)
            if status is None:
                raise KeyError(job_id)
            return status.model_copy(deep=True)

    def benchmark(self, model_id: str) -> AkidaModelJobStatus:
        """Re-run the whole evaluation set on an already-mapped model.

        A separate job, deliberately not routed through ``submit``: that path
        dedupes on the bundle checksum and returns the previous result for
        identical bytes, so re-submitting a bundle can never produce a fresh
        measurement. Benchmarking is a repeat run by definition, so it gets its
        own job id and never touches ``_job_by_checksum``.
        """
        model, bundle, target = self._resident_model(model_id)
        runtime_target, device_info = target

        with self._lock:
            job_id = uuid.uuid4().hex
            status = AkidaModelJobStatus(
                jobId=job_id,
                bundleSha256=self._bundle_checksums.get(model_id, ""),
                stage=AkidaModelJobStage.EVALUATION,
                progress=0,
                message=f"Benchmarking {len(bundle.evaluation_labels)} samples.",
                modelId=model_id,
                runtimeTarget=runtime_target,
                hardwareVerified=runtime_target == "hardware",
                deviceInfo=device_info,
            )
            self._jobs[job_id] = status
            self._persist_status(status)

        worker = threading.Thread(
            target=self._run_benchmark,
            args=(job_id, model_id, model, bundle),
            name=f"akida-benchmark-{job_id[:8]}",
            daemon=True,
        )
        worker.start()
        return status.model_copy(deep=True)

    def _run_benchmark(
        self, job_id: str, model_id: str, model: Any, bundle: _ValidatedBundle
    ) -> None:
        """Score the bundled set again and record accuracy plus timing.

        No accuracy floor is applied. The floors exist to stop a broken bundle
        being accepted at submission; refusing to *report* a measurement the
        user explicitly asked for would defeat the point of a benchmark.
        """
        try:
            outcome = self._evaluate_dataset(model, bundle)
            metrics = dict(bundle.manifest.source_metrics)
            metrics["akida_accuracy"] = outcome.accuracy
            metrics.update(self._performance_metrics(outcome))
            self._update(
                job_id,
                AkidaModelJobStage.COMPLETED,
                100,
                f"Benchmarked {outcome.total_samples} samples on {model_id}.",
                metrics=metrics,
                total_samples=outcome.total_samples,
                class_results=self._class_results(bundle, outcome.predictions),
            )
        except AkidaModelJobError as exc:
            self._fail(job_id, exc.error_code, str(exc))
        except RuntimeError as exc:
            translated = _device_unresponsive_error(exc)
            if translated is None:
                logger.exception("Akida benchmark failed: %s", job_id)
                self._fail(job_id, "AKIDA_BENCHMARK_FAILED", _BENCHMARK_FAILED_MESSAGE)
            else:
                logger.exception("Akida benchmark failed (device unresponsive): %s", job_id)
                self._fail(job_id, translated.error_code, str(translated))
        except Exception:
            logger.exception("Akida benchmark failed: %s", job_id)
            self._fail(job_id, "AKIDA_BENCHMARK_FAILED", _BENCHMARK_FAILED_MESSAGE)

    def _resident_model(
        self, model_id: str
    ) -> tuple[Any, _ValidatedBundle, tuple[str, str | None]]:
        """Return a loaded model, or explain how to get one back.

        ``_reload_model`` refuses to hand back a simulator-mode model after a
        restart, so "not loaded" genuinely means the bundle has to be sent
        again -- the message has to say that rather than read as a crash.
        """
        with self._lock:
            model = self._models.get(model_id)
            bundle = self._bundles.get(model_id)
            target = self._model_targets.get(model_id)
        if model is None or bundle is None:
            model, bundle = self._reload_model(model_id)
            with self._lock:
                target = self._model_targets.get(model_id)
        if model is None or bundle is None or target is None:
            raise AkidaModelJobError(
                "MODEL_NOT_LOADED",
                "This model is no longer loaded on the Akida host. Submit the "
                "bundle again to reload it, then benchmark.",
            )
        return model, bundle, target

    def infer(
        self, model_id: str, request: AkidaModelInferenceRequest
    ) -> AkidaModelInferenceResult:
        """Run one stored sample or explicit raw input through a converted model."""
        model, bundle, target = self._resident_model(model_id)

        sample_index = request.sample_index
        expected_values = int(np.prod(bundle.manifest.input.shape[1:]))
        label: int | None = None
        if request.input_values is not None:
            if len(request.input_values) != expected_values:
                raise AkidaModelJobError(
                    "INFERENCE_SHAPE_INVALID",
                    f"Input must contain exactly {expected_values} values.",
                )
            if any(value < 0 or value > 255 for value in request.input_values):
                raise AkidaModelJobError(
                    "INFERENCE_VALUE_INVALID",
                    "Input values must be raw pixels between 0 and 255.",
                )
            image = np.asarray(request.input_values, dtype=np.uint8).reshape(
                (1, *bundle.manifest.input.shape[1:])
            )
        else:
            sample_index = 0 if sample_index is None else sample_index
            if sample_index >= len(bundle.evaluation_inputs):
                raise AkidaModelJobError(
                    "SAMPLE_INDEX_INVALID",
                    f"Sample index must be below {len(bundle.evaluation_inputs)}.",
                )
            image = bundle.evaluation_inputs[sample_index : sample_index + 1]
            label = int(bundle.evaluation_labels[sample_index])

        try:
            outputs = np.asarray(model.predict(image)).reshape(-1)
        except RuntimeError as exc:
            translated = _device_unresponsive_error(exc)
            if translated is None:
                raise
            logger.exception("akida_inference_device_unresponsive model_id=%s", model_id)
            raise translated from exc
        prediction = int(outputs.argmax())
        labels = bundle.manifest.labels
        runtime_target, _device_info = target
        return AkidaModelInferenceResult(
            modelId=model_id,
            sampleIndex=sample_index,
            prediction=prediction,
            label=label,
            labelName=labels[prediction] if prediction < len(labels) else str(prediction),
            outputs=[float(value) for value in outputs],
            runtimeTarget=runtime_target,
            hardwareVerified=runtime_target == "hardware",
            telemetry=self._model_telemetry(model),
            layerSpikes=self._layer_spike_stats(model),
        )

    def visualize(
        self, model_id: str, request: AkidaModelVisualizationRequest
    ) -> AkidaModelVisualizationResult:
        """Replay an unmapped copy of the deployed model for visualization.

        This path never calls ``map`` and never touches the resident model used
        for physical inference. It loads a separate ``model.fbz`` and builds a
        prefix model ending at the requested layer.
        """
        bundle, related_runtime_target, model_path = self._visualization_source(model_id)
        sample_index = request.sample_index
        if request.mode == AkidaVisualizationMode.SAMPLE:
            sample_index = 0 if sample_index is None else sample_index
            if sample_index >= len(bundle.evaluation_inputs):
                raise AkidaModelJobError(
                    "SAMPLE_INDEX_INVALID",
                    f"Sample index must be below {len(bundle.evaluation_inputs)}.",
                )
        else:
            sample_index = None

        cache_key = (model_id, request.mode, request.layer_index, sample_index)
        with self._lock:
            cached = self._visualization_cache.get(cache_key)
            if cached is not None:
                self._visualization_cache.move_to_end(cache_key)
                return cached.model_copy(deep=True)

        import akida

        replay_model = akida.Model(str(model_path))
        layers = self._visualization_layers(replay_model)
        selected = next((layer for layer in layers if layer.index == request.layer_index), None)
        if selected is None:
            raise AkidaModelJobError(
                "VISUALIZATION_LAYER_INVALID",
                "Choose one of the deployed model layers shown in the layer picker.",
            )

        try:
            layer = replay_model.layers[request.layer_index]
            prefix = akida.Model(layers=list(replay_model.layers[: request.layer_index + 1]))
            inputs = (
                bundle.evaluation_inputs[sample_index : sample_index + 1]
                if sample_index is not None
                else bundle.evaluation_inputs
            )
            replay_output = np.asarray(prefix.forward(inputs))
            flattened = replay_output.reshape((len(inputs), -1))
            activity_values = (
                flattened[0]
                if request.mode == AkidaVisualizationMode.SAMPLE
                else flattened.mean(axis=0, dtype=np.float32)
            )
            weights = np.asarray(layer.get_variable("weights"))
            result = AkidaModelVisualizationResult(
                modelId=model_id,
                mode=request.mode,
                layers=layers,
                layerIndex=selected.index,
                layerName=selected.name,
                sampleIndex=sample_index,
                sampleCount=len(inputs),
                available=True,
                activity=self._compress_array(activity_values),
                raster=(
                    self._compress_array((flattened != 0).astype(np.uint8))
                    if request.mode == AkidaVisualizationMode.BENCHMARK
                    else None
                ),
                weights=self._compress_array(weights),
                weightBits=selected.weight_bits,
                relatedRuntimeTarget=related_runtime_target,
            )
        except (AttributeError, IndexError, TypeError, ValueError) as exc:
            logger.info(
                "Akida layer cannot be isolated for visualization: model=%s layer=%s: %s",
                model_id,
                request.layer_index,
                exc,
            )
            result = AkidaModelVisualizationResult(
                modelId=model_id,
                mode=request.mode,
                layers=layers,
                layerIndex=selected.index,
                layerName=selected.name,
                sampleIndex=sample_index,
                sampleCount=(1 if sample_index is not None else len(bundle.evaluation_inputs)),
                available=False,
                unavailableReason=(
                    "This Akida layer cannot be isolated by the installed software runtime. "
                    "The source-run visualization remains available for comparison."
                ),
                relatedRuntimeTarget=related_runtime_target,
            )

        with self._lock:
            self._visualization_cache[cache_key] = result
            self._visualization_cache.move_to_end(cache_key)
            while len(self._visualization_cache) > _VISUALIZATION_CACHE_SIZE:
                self._visualization_cache.popitem(last=False)
        return result.model_copy(deep=True)

    def _visualization_source(self, model_id: str) -> tuple[_ValidatedBundle, str, Path]:
        """Resolve replay inputs without loading or mapping the hardware model."""
        model_dir = self._storage_dir / model_id
        model_path = model_dir / "model.fbz"
        bundle_path = model_dir / "bundle.zip"
        with self._lock:
            bundle = self._bundles.get(model_id)
            target = self._model_targets.get(model_id)
            if target is None:
                matching_status = next(
                    (
                        status
                        for status in self._jobs.values()
                        if status.model_id == model_id
                        and status.stage == AkidaModelJobStage.COMPLETED
                    ),
                    None,
                )
                related_runtime_target = (
                    matching_status.runtime_target if matching_status else "unknown"
                )
            else:
                related_runtime_target = target[0]
        if not model_path.is_file() or not bundle_path.is_file():
            raise AkidaModelJobError(
                "MODEL_NOT_LOADED",
                "The deployed model files are no longer available on this Akida host. "
                "Deploy the bundle again to restore its visualizations.",
            )
        if bundle is None:
            bundle = self._validate_bundle(bundle_path.read_bytes())
            with self._lock:
                self._bundles[model_id] = bundle
        return bundle, related_runtime_target, model_path

    def _run_job(self, job_id: str, bundle_bytes: bytes, require_hardware: bool) -> None:
        try:
            bundle = self._validate_bundle(bundle_bytes)
            model_id = hashlib.sha256(bundle_bytes).hexdigest()[:24]
            model_dir = self._storage_dir / model_id
            model_dir.mkdir(parents=True, exist_ok=True)
            (model_dir / "bundle.zip").write_bytes(bundle_bytes)

            if bundle.is_preconverted:
                # Nothing to quantize: the canvas Akida Exporter already built
                # this model from the trained NIR graph. Reuse the CONVERSION
                # stage rather than adding one, so the app's stage mapping and
                # progress bar need no new case.
                self._update(
                    job_id,
                    AkidaModelJobStage.CONVERSION,
                    45,
                    "Loading converted Akida model.",
                )
                model = self._load_preconverted(bundle, model_dir)
            else:
                self._update(job_id, AkidaModelJobStage.QUANTIZATION, 20, "Quantizing ONNX model.")
                model_quantized = self._quantize(bundle)
                self._update(
                    job_id, AkidaModelJobStage.CONVERSION, 45, "Converting to Akida format."
                )
                model = self._convert(model_quantized)
                model.save(str(model_dir / "model.fbz"))

            self._update(job_id, AkidaModelJobStage.MAPPING, 65, "Mapping the Akida model.")
            runtime_target, device_info = self._map_model(model, require_hardware)
            self._update(job_id, AkidaModelJobStage.EVALUATION, 80, "Evaluating bundled samples.")
            outcome = self._evaluate_dataset(model, bundle)
            self._enforce_accuracy_floor(bundle, outcome.accuracy)
            metrics = dict(bundle.manifest.source_metrics)
            metrics["akida_accuracy"] = outcome.accuracy
            metrics.update(self._performance_metrics(outcome))
            class_results = self._class_results(bundle, outcome.predictions)
            hardware_verified = runtime_target == "hardware"
            if require_hardware and not hardware_verified:
                raise AkidaModelJobError(
                    "PHYSICAL_HARDWARE_REQUIRED",
                    "A physical Akida device is required for hardware verification.",
                )
            with self._lock:
                self._models[model_id] = model
                self._bundles[model_id] = bundle
                self._model_targets[model_id] = (runtime_target, device_info)
                self._bundle_checksums[model_id] = hashlib.sha256(bundle_bytes).hexdigest()
            self._update(
                job_id,
                AkidaModelJobStage.COMPLETED,
                100,
                "Model converted, mapped, and evaluated.",
                model_id=model_id,
                runtime_target=runtime_target,
                hardware_verified=hardware_verified,
                metrics=metrics,
                total_samples=outcome.total_samples,
                class_results=class_results,
                device_info=device_info,
            )
        except AkidaModelJobError as exc:
            self._fail(job_id, exc.error_code, str(exc))
        except (ImportError, ModuleNotFoundError):
            self._fail(
                job_id,
                "AKIDA_CONVERSION_DEPENDENCY_MISSING",
                "The Akida conversion runtime is incomplete; use Backend Setup to update this host.",
            )
        except RuntimeError as exc:
            translated = _device_unresponsive_error(exc)
            if translated is None:
                logger.exception("Akida model job failed: %s", job_id)
                self._fail(job_id, "AKIDA_CONVERSION_FAILED", _CONVERSION_FAILED_MESSAGE)
            else:
                logger.exception("Akida model job failed (device unresponsive): %s", job_id)
                self._fail(job_id, translated.error_code, str(translated))
        except Exception:
            logger.exception("Akida model job failed: %s", job_id)
            self._fail(job_id, "AKIDA_CONVERSION_FAILED", _CONVERSION_FAILED_MESSAGE)

    def _reload_model(self, model_id: str) -> tuple[Any | None, _ValidatedBundle | None]:
        model_dir = self._storage_dir / model_id
        model_path = model_dir / "model.fbz"
        bundle_path = model_dir / "bundle.zip"
        if not model_path.is_file() or not bundle_path.is_file():
            return None, None
        try:
            import akida

            bundle = self._validate_bundle(bundle_path.read_bytes())
            model = akida.Model(str(model_path))
            runtime_target, device_info = self._map_model(model, require_hardware=True)
            if runtime_target != "hardware":
                return None, None
        except Exception:
            logger.exception("Could not reload persisted Akida model %s", model_id)
            return None, None
        with self._lock:
            self._models[model_id] = model
            self._bundles[model_id] = bundle
            self._model_targets[model_id] = (runtime_target, device_info)
        return model, bundle

    def _update(
        self,
        job_id: str,
        stage: AkidaModelJobStage,
        progress: int,
        message: str,
        **updates: Any,
    ) -> None:
        with self._lock:
            current = self._jobs[job_id]
            data = current.model_dump()
            data.update({"stage": stage, "progress": progress, "message": message})
            aliases = {
                field.alias: name
                for name, field in AkidaModelJobStatus.model_fields.items()
                if field.alias is not None
            }
            data.update({aliases.get(key, key): value for key, value in updates.items()})
            status = AkidaModelJobStatus.model_validate(data)
            self._jobs[job_id] = status
            self._persist_status(status)

    def _fail(self, job_id: str, error_code: str, message: str) -> None:
        self._update(
            job_id,
            AkidaModelJobStage.FAILED,
            100,
            message,
            errorCode=error_code,
            hardwareVerified=False,
        )

    def _persist_status(self, status: AkidaModelJobStatus) -> None:
        path = self._storage_dir / f"job-{status.job_id}.json"
        temporary = path.with_suffix(".tmp")
        temporary.write_text(status.model_dump_json(by_alias=True), encoding="utf-8")
        temporary.replace(path)

    def _load_persisted_jobs(self) -> None:
        for path in self._storage_dir.glob("job-*.json"):
            try:
                status = AkidaModelJobStatus.model_validate_json(path.read_text(encoding="utf-8"))
            except (OSError, ValidationError, ValueError):
                logger.warning("Ignoring invalid persisted Akida job status: %s", path)
                continue
            if status.stage not in {
                AkidaModelJobStage.COMPLETED,
                AkidaModelJobStage.FAILED,
            }:
                status = status.model_copy(
                    update={
                        "stage": AkidaModelJobStage.FAILED,
                        "progress": 100,
                        "message": "The host restarted during conversion; submit the same bundle to retry safely.",
                        "error_code": "JOB_INTERRUPTED",
                        "hardware_verified": False,
                    }
                )
                self._persist_status(status)
            self._jobs[status.job_id] = status
            self._job_by_checksum[status.bundle_sha256] = status.job_id


akida_model_job_service = AkidaModelJobService()
