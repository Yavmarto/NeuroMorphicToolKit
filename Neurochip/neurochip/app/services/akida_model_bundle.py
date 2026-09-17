"""Akida model bundle validation, conversion, and evaluation scoring.

Everything here is stateless with respect to a running job: reading and
validating a bundle archive, quantizing/converting/loading the model it
describes, and scoring it against the bundled evaluation set. It is mixed
into ``AkidaModelJobService`` (in ``akida_model_jobs.py``) rather than called
as free functions so that existing tests can keep monkeypatching these
methods on a service instance (e.g. ``monkeypatch.setattr(service,
"_quantize", ...)``) and keep calling ``AkidaModelJobService._load_preconverted``
directly.

Two bundle kinds arrive here and they are deliberately not the same shape:

* **V1** carries ``model.onnx`` and a calibration set. The host quantizes with
  QuantizeML and converts with cnn2snn. It is the BrainChip MNIST companion
  path, and its 98%/96% accuracy gates exist because that demo asserts them.
* **V2** carries an already-converted ``model.fbz``, produced by the canvas
  Akida Exporter from a trained NIR graph. Nothing is quantized here; the host
  loads, maps, and measures. Applying V1's gates to it would reject a
  legitimately converted spiking model before it ever reached the card, so V2
  only refuses a result near chance -- which indicates broken scaling rather
  than a weak model -- and reports the number either way.
"""

from __future__ import annotations

import base64
import hashlib
import io
import json
import logging
import time
import zipfile
import zlib
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Any

try:
    import numpy as np
except ImportError:  # Optional at startup; conversion jobs report their own requirements.
    np = None  # type: ignore[assignment]
from pydantic import ValidationError

from ...contracts.akida_model_bundle_contract import (
    AKIDA_MODEL_BUNDLE_MAX_BYTES,
    AKIDA_MODEL_BUNDLE_REQUIRED_FILES,
    AKIDA_MODEL_BUNDLE_V2_REQUIRED_FILES,
    AkidaClassResult,
    AkidaCompressedArray,
    AkidaModelBundleV1,
    AkidaModelBundleV2,
    AkidaVisualizationLayer,
    LayerSpikeStats,
)

logger = logging.getLogger(__name__)

_MAX_ARCHIVE_UNCOMPRESSED_BYTES = 64 * 1024 * 1024
_MIN_SOURCE_ACCURACY = 0.98
_MAX_ONNX_ACCURACY_DELTA = 0.001
_MIN_AKIDA_ACCURACY = 0.96
# A converted spiking model is expected to lose accuracy; only a near-chance
# result says something is actually broken, and it is a scaling fault in the
# conversion rather than a bad model. Anything above this is reported, not
# refused -- comparing simulator to card is the reason the bundle exists.
_MIN_AKIDA_ACCURACY_V2 = 0.20


class AkidaModelJobError(RuntimeError):
    """Actionable failure safe to surface without a raw exception string."""

    def __init__(self, error_code: str, message: str) -> None:
        super().__init__(message)
        self.error_code = error_code


@dataclass(frozen=True)
class _ValidatedBundle:
    manifest: AkidaModelBundleV1 | AkidaModelBundleV2
    files: dict[str, bytes]
    evaluation_inputs: np.ndarray[Any, Any]
    evaluation_labels: np.ndarray[Any, Any]
    calibration: np.ndarray[Any, Any] | None

    @property
    def is_preconverted(self) -> bool:
        """True when the bundle already contains a built Akida model."""
        return isinstance(self.manifest, AkidaModelBundleV2)


@dataclass(frozen=True)
class _EvaluationOutcome:
    """Everything one whole-dataset pass on the card produced.

    ``predictions`` is None for V1 bundles, where ``model.evaluate`` returns an
    accuracy and nothing per-sample.
    """

    accuracy: float
    total_samples: int
    elapsed_s: float
    predictions: np.ndarray[Any, Any] | None = None
    sdk_statistics: dict[str, float] = field(default_factory=dict)


class AkidaBundleArtifactsMixin:
    """Bundle validation, conversion, and evaluation-scoring methods.

    Mixed into ``AkidaModelJobService``. Every method here is static,
    class-level, or touches only its arguments -- none reads or writes the
    service's job/model registries -- so the split from the job lifecycle
    state machine is a pure code-organization move, not a behavior change.
    """

    def _validate_bundle(self, bundle_bytes: bytes) -> _ValidatedBundle:
        """Validate either bundle kind, dispatching on the manifest version."""
        files = self._extract_archive(bundle_bytes)
        schema_version = self._peek_schema_version(files)
        if schema_version == 2:
            return self._validate_bundle_v2(files)
        return self._validate_bundle_v1(files)

    def _extract_archive(self, bundle_bytes: bytes) -> dict[str, bytes]:
        """Read every member safely. Shared by both bundle versions.

        This is the security-relevant half -- path traversal, per-file size, and
        the expansion cap -- so it deliberately runs before anything looks at
        the manifest and before either version-specific path can diverge.
        """
        self._ensure_zip(bundle_bytes)
        files: dict[str, bytes] = {}
        try:
            with zipfile.ZipFile(io.BytesIO(bundle_bytes)) as archive:
                if "manifest.json" not in set(archive.namelist()):
                    raise AkidaModelJobError(
                        "BUNDLE_FILE_MISSING", "Bundle is missing: manifest.json."
                    )
                total_uncompressed = 0
                for info in archive.infolist():
                    path = PurePosixPath(info.filename)
                    if path.is_absolute() or ".." in path.parts or info.is_dir():
                        if info.is_dir():
                            continue
                        raise AkidaModelJobError(
                            "BUNDLE_PATH_UNSAFE", "The bundle contains an unsafe file path."
                        )
                    if info.file_size > AKIDA_MODEL_BUNDLE_MAX_BYTES:
                        raise AkidaModelJobError(
                            "BUNDLE_FILE_TOO_LARGE", "A file inside the bundle is too large."
                        )
                    total_uncompressed += info.file_size
                    if total_uncompressed > _MAX_ARCHIVE_UNCOMPRESSED_BYTES:
                        raise AkidaModelJobError(
                            "BUNDLE_EXPANSION_TOO_LARGE",
                            "The model bundle expands beyond the 64 MB safety limit.",
                        )
                    files[info.filename] = archive.read(info)
        except zipfile.BadZipFile as exc:
            raise AkidaModelJobError(
                "BUNDLE_ZIP_INVALID", "The selected file is not a valid model bundle."
            ) from exc
        return files

    @staticmethod
    def _peek_schema_version(files: dict[str, bytes]) -> int:
        """Read only ``schemaVersion`` so the right manifest model is applied."""
        try:
            document = json.loads(files["manifest.json"])
        except (ValueError, KeyError) as exc:
            raise AkidaModelJobError(
                "BUNDLE_MANIFEST_INVALID",
                "The model bundle manifest is invalid or unsupported.",
            ) from exc
        if not isinstance(document, dict):
            raise AkidaModelJobError(
                "BUNDLE_MANIFEST_INVALID",
                "The model bundle manifest is invalid or unsupported.",
            )
        version = document.get("schemaVersion")
        return version if isinstance(version, int) else 1

    @staticmethod
    def _require_files(files: dict[str, bytes], required: frozenset[str]) -> None:
        missing = required - files.keys()
        if missing:
            raise AkidaModelJobError(
                "BUNDLE_FILE_MISSING",
                f"Bundle is missing: {', '.join(sorted(missing))}.",
            )

    @staticmethod
    def _verify_checksums(files: dict[str, bytes], declared: dict[str, str]) -> None:
        for filename, expected in declared.items():
            content = files.get(filename)
            if content is None or hashlib.sha256(content).hexdigest() != expected:
                raise AkidaModelJobError(
                    "BUNDLE_FILE_CHECKSUM_MISMATCH",
                    f"Checksum validation failed for {filename}.",
                )

    @staticmethod
    def _load_evaluation(
        files: dict[str, bytes],
        manifest: AkidaModelBundleV1 | AkidaModelBundleV2,
    ) -> tuple[np.ndarray[Any, Any], np.ndarray[Any, Any]]:
        try:
            with np.load(io.BytesIO(files["evaluation.npz"]), allow_pickle=False) as evaluation:
                inputs = evaluation["inputs"].copy()
                labels = evaluation["labels"].copy()
        except (ValueError, KeyError) as exc:
            raise AkidaModelJobError(
                "BUNDLE_ARRAY_INVALID", "Calibration or evaluation arrays are invalid."
            ) from exc
        if inputs.dtype != np.uint8 or labels.dtype != np.int32:
            raise AkidaModelJobError(
                "EVALUATION_DTYPE_INVALID", "Evaluation inputs must be uint8 and labels int32."
            )
        if len(inputs) != len(labels) or len(inputs) == 0:
            raise AkidaModelJobError(
                "EVALUATION_SHAPE_INVALID", "Evaluation inputs and labels must have equal length."
            )
        if np.any(labels < 0) or np.any(labels >= len(manifest.labels)):
            raise AkidaModelJobError(
                "EVALUATION_LABEL_INVALID",
                "Evaluation labels must refer to entries in the manifest label list.",
            )
        if tuple(inputs.shape[1:]) != tuple(manifest.input.shape[1:]):
            raise AkidaModelJobError(
                "BUNDLE_INPUT_SHAPE_MISMATCH",
                "Bundle arrays do not match the manifest input shape.",
            )
        return inputs, labels

    def _validate_bundle_v2(self, files: dict[str, bytes]) -> _ValidatedBundle:
        """Validate a bundle whose model is already an Akida ``.fbz``."""
        self._require_files(files, AKIDA_MODEL_BUNDLE_V2_REQUIRED_FILES)
        try:
            manifest = AkidaModelBundleV2.model_validate_json(files["manifest.json"])
        except (ValidationError, ValueError) as exc:
            raise AkidaModelJobError(
                "BUNDLE_MANIFEST_INVALID",
                "The model bundle manifest is invalid or unsupported.",
            ) from exc
        self._verify_checksums(files, manifest.files)
        if "akida_sim_accuracy" not in manifest.source_metrics:
            raise AkidaModelJobError(
                "SOURCE_METRICS_INCOMPLETE",
                "A converted bundle must report the accuracy it measured on the simulator.",
            )
        self._check_producer_sdk_version(manifest)
        evaluation_inputs, evaluation_labels = self._load_evaluation(files, manifest)
        return _ValidatedBundle(
            manifest=manifest,
            files=files,
            evaluation_inputs=evaluation_inputs,
            evaluation_labels=evaluation_labels,
            calibration=None,
        )

    @staticmethod
    def _check_producer_sdk_version(manifest: AkidaModelBundleV2) -> None:
        """Reject a ``.fbz`` written by a different Akida SDK than we run.

        A ``.fbz`` is a version-gated flatbuffer, so a bundle built by a newer
        SDK than the host's makes ``akida.Model(path)`` throw a generic parse
        error further down -- which used to surface as the opaque
        "could not be loaded by the Akida runtime" with no way to see why.

        The bundle has always carried the producer's version in
        ``dependencyVersions`` and nothing read it. Comparing here turns an
        unfixable failure into a named one. Only an exact mismatch is reported,
        and only when both sides are known: a bundle from an older writer that
        recorded no version still loads or fails on its own merits.
        """
        producer = (manifest.dependency_versions or {}).get("akida", "").strip()
        if not producer:
            return
        try:
            import akida
        except ImportError:  # pragma: no cover - host always has the SDK
            return
        host = str(getattr(akida, "__version__", "") or "").strip()
        if not host or host == producer:
            return
        raise AkidaModelJobError(
            "MODEL_SDK_VERSION_MISMATCH",
            f"This bundle was built with Akida SDK {producer} but this host runs "
            f"{host}. A .fbz can only be reopened by the version that wrote it. "
            "Align the two: rebuild the jupyter-server image, or update this "
            "host's Akida runtime, so both use the same version.",
        )

    def _validate_bundle_v1(self, files: dict[str, bytes]) -> _ValidatedBundle:
        self._require_files(files, AKIDA_MODEL_BUNDLE_REQUIRED_FILES)
        try:
            manifest = AkidaModelBundleV1.model_validate_json(files["manifest.json"])
        except (ValidationError, ValueError) as exc:
            raise AkidaModelJobError(
                "BUNDLE_MANIFEST_INVALID",
                "The model bundle manifest is invalid or unsupported.",
            ) from exc
        self._verify_checksums(files, manifest.files)
        pytorch_accuracy = manifest.source_metrics.get("pytorch_accuracy")
        onnx_accuracy = manifest.source_metrics.get("onnx_accuracy")
        if (
            pytorch_accuracy is None
            or onnx_accuracy is None
            or pytorch_accuracy < _MIN_SOURCE_ACCURACY
        ):
            raise AkidaModelJobError(
                "SOURCE_ACCURACY_BELOW_THRESHOLD",
                "The bundle must report at least 98% PyTorch accuracy and an ONNX result.",
            )
        if abs(pytorch_accuracy - onnx_accuracy) > _MAX_ONNX_ACCURACY_DELTA:
            raise AkidaModelJobError(
                "ONNX_PARITY_FAILED",
                "ONNX accuracy differs from PyTorch by more than 0.1 percentage point.",
            )
        try:
            calibration = np.load(io.BytesIO(files["calibration.npy"]), allow_pickle=False)
        except ValueError as exc:
            raise AkidaModelJobError(
                "BUNDLE_ARRAY_INVALID", "Calibration or evaluation arrays are invalid."
            ) from exc
        if calibration.dtype != np.float32 or calibration.shape[0] != 128:
            raise AkidaModelJobError(
                "CALIBRATION_INVALID", "Calibration must contain 128 float32 samples."
            )
        evaluation_inputs, evaluation_labels = self._load_evaluation(files, manifest)
        if tuple(calibration.shape[1:]) != tuple(manifest.input.shape[1:]):
            raise AkidaModelJobError(
                "BUNDLE_INPUT_SHAPE_MISMATCH",
                "Bundle arrays do not match the manifest input shape.",
            )
        return _ValidatedBundle(
            manifest=manifest,
            files=files,
            evaluation_inputs=evaluation_inputs,
            evaluation_labels=evaluation_labels,
            calibration=calibration,
        )

    @staticmethod
    def _ensure_zip(bundle_bytes: bytes) -> None:
        if not bundle_bytes.startswith(b"PK"):
            raise AkidaModelJobError(
                "BUNDLE_ZIP_INVALID", "The selected file is not a valid model bundle."
            )

    @staticmethod
    def _quantize(bundle: _ValidatedBundle) -> Any:
        import onnx
        from quantizeml.models import quantize

        model_onnx = onnx.load_model_from_string(bundle.files["model.onnx"])
        return quantize(model_onnx, samples=bundle.calibration)

    @staticmethod
    def _convert(model_quantized: Any) -> Any:
        from cnn2snn import convert

        return convert(model_quantized)

    @staticmethod
    def _load_preconverted(bundle: _ValidatedBundle, model_dir: Path) -> Any:
        """Write the bundled ``.fbz`` to disk and load it as an Akida model.

        It is written out rather than loaded from memory because ``akida.Model``
        takes a path, and because `_reload_model` expects to find exactly this
        file after a restart.
        """
        import akida

        model_path = model_dir / "model.fbz"
        model_path.write_bytes(bundle.files["model.fbz"])
        try:
            return akida.Model(str(model_path))
        except Exception as exc:
            # Carry the SDK's own reason and log it. `from exc` alone discarded
            # it completely -- the AkidaModelJobError branch of `_run_job` does
            # not log, unlike the generic handler beside it -- so the one message
            # that could explain the failure never reached anyone.
            logger.exception("akida_model_load_failed path=%s", model_path)
            host_version = str(getattr(akida, "__version__", "") or "unknown")
            raise AkidaModelJobError(
                "MODEL_FILE_UNREADABLE",
                "The converted model in this bundle could not be loaded by the "
                f"Akida runtime (SDK {host_version}): "
                f"{type(exc).__name__}: {exc}",
            ) from exc

    @staticmethod
    def _reset_statistics(model: Any) -> None:
        """Zero the SDK's counters so a following run reports only its own work.

        ``Model.statistics`` on real Akida accumulates since the last reset, so
        reading it without this yields figures covering every inference the
        model has served since it was mapped.
        """
        try:
            statistics = getattr(model, "statistics", None)
            reset = getattr(statistics, "reset", None)
            if callable(reset):
                reset()
        except Exception:  # noqa: BLE001
            # Never let a telemetry nicety fail an evaluation. Older SDKs have
            # no reset; the figures are then cumulative, which _sdk_statistics
            # reports as-is rather than pretending otherwise.
            logger.debug("akida_statistics_reset_unavailable", exc_info=True)

        # Also reset per-layer counters when exposed by the SDK.
        for layer in getattr(model, "layers", []):
            try:
                layer_stats = getattr(layer, "statistics", None)
                layer_reset = getattr(layer_stats, "reset", None)
                if callable(layer_reset):
                    layer_reset()
            except Exception:  # noqa: BLE001
                logger.debug("akida_layer_statistics_reset_unavailable", exc_info=True)
                break  # If first layer fails, assume none support it.

    @staticmethod
    def _sdk_statistics(model: Any) -> dict[str, float]:
        """Numeric SDK telemetry, restricted to values it actually reported.

        Only keys the SDK returns as real numbers are emitted. A missing or
        None power reading must stay absent rather than become a zero, because
        the app is required to distinguish measured figures from estimates.
        """
        statistics = getattr(model, "statistics", None)
        if statistics is None:
            return {}
        collected: dict[str, float] = {}
        for attribute, key in (("fps", "sdk_fps"), ("power", "power_mw")):
            value = getattr(statistics, attribute, None)
            if isinstance(value, bool) or not isinstance(value, int | float):
                continue
            collected[key] = float(value)
        return collected

    @staticmethod
    def _layer_spike_stats(model: Any) -> list[LayerSpikeStats] | None:
        """Per-layer non-zero spike counts from the Akida SDK.

        Returns ``None`` when the SDK exposes no per-layer statistics so the
        caller can omit the field entirely rather than returning an empty list,
        which would be indistinguishable from "all layers had zero spikes".
        """
        results: list[LayerSpikeStats] = []
        for layer in getattr(model, "layers", []):
            try:
                layer_stats = getattr(layer, "statistics", None)
                nz = getattr(layer_stats, "total_nz_spike", None)
                if not isinstance(nz, int | float) or isinstance(nz, bool):
                    continue
                results.append(
                    LayerSpikeStats(
                        name=str(getattr(layer, "name", f"layer_{len(results)}")),
                        nzSpikes=int(nz),
                    )
                )
            except Exception:  # noqa: BLE001
                logger.debug("akida_layer_spike_stats_unavailable", exc_info=True)
        return results if results else None

    @staticmethod
    def _compress_array(values: np.ndarray[Any, Any]) -> AkidaCompressedArray:
        contiguous = np.ascontiguousarray(values)
        return AkidaCompressedArray(
            dtype=contiguous.dtype.str,
            shape=list(contiguous.shape),
            data=base64.b64encode(zlib.compress(contiguous.tobytes())).decode("ascii"),
        )

    def _evaluate_dataset(self, model: Any, bundle: _ValidatedBundle) -> _EvaluationOutcome:
        """Score `model` over the bundle's whole evaluation set, and time it.

        V1 models keep ``model.evaluate``, which is what that path has always
        used. A V2 model is scored with ``predict`` + argmax instead: its
        classifier layer has activation disabled, so ``predict`` returns the raw
        potentials, and this is exactly how `infer` serves a single sample --
        the reported accuracy therefore describes the same computation a user
        will see per sample rather than a second, differently-shaped one.

        Timing is wall-clock around the call, because the hardware inference
        path reports no per-sample duration of its own (only the simulator
        populates ``execution_time_us``). It therefore includes host-side
        marshalling, which is what a user waits for anyway.
        """
        labels = bundle.evaluation_labels
        total = int(len(labels))
        self._reset_statistics(model)

        started = time.perf_counter()
        if not bundle.is_preconverted:
            accuracy = float(model.evaluate(bundle.evaluation_inputs, labels))
            predictions = None
        else:
            outputs = np.asarray(model.predict(bundle.evaluation_inputs))
            predicted = outputs.reshape(total, -1).argmax(-1)
            accuracy = float((predicted == labels).mean())
            predictions = predicted
        elapsed_s = time.perf_counter() - started

        return _EvaluationOutcome(
            accuracy=accuracy,
            total_samples=total,
            elapsed_s=elapsed_s,
            predictions=predictions,
            sdk_statistics=self._sdk_statistics(model),
        )

    @staticmethod
    def _class_results(
        bundle: _ValidatedBundle, predictions: Any | None
    ) -> list[AkidaClassResult] | None:
        """Bucket predictions by true label, or None when unavailable.

        Returns None for V1 bundles: ``model.evaluate`` hands back one accuracy
        and no per-sample predictions, so there is nothing to bucket. Reporting
        an empty list instead would read as "every class scored zero".
        """
        if predictions is None:
            return None
        labels = bundle.evaluation_labels
        names = list(bundle.manifest.labels)
        results: list[AkidaClassResult] = []
        for index, name in enumerate(names):
            mask = labels == index
            support = int(mask.sum())
            correct = int((predictions[mask] == index).sum()) if support else 0
            results.append(
                AkidaClassResult(
                    label=index,
                    labelName=str(name),
                    support=support,
                    correct=correct,
                )
            )
        return results

    @staticmethod
    def _performance_metrics(outcome: _EvaluationOutcome) -> dict[str, float]:
        """Latency and throughput derived from the timed run.

        ``sdk_fps`` is kept separate from the derived ``fps``: the SDK counts
        only on-chip time, so the two legitimately disagree and collapsing them
        would hide which one a number came from.
        """
        metrics: dict[str, float] = {"total_samples": float(outcome.total_samples)}
        if outcome.total_samples > 0 and outcome.elapsed_s > 0:
            metrics["latency_ms"] = (outcome.elapsed_s / outcome.total_samples) * 1000.0
            metrics["fps"] = outcome.total_samples / outcome.elapsed_s
        metrics.update(outcome.sdk_statistics)
        return metrics

    @staticmethod
    def _enforce_accuracy_floor(bundle: _ValidatedBundle, accuracy: float) -> None:
        if bundle.is_preconverted:
            if accuracy < _MIN_AKIDA_ACCURACY_V2:
                raise AkidaModelJobError(
                    "AKIDA_ACCURACY_NEAR_CHANCE",
                    "The converted model scored near chance on the card, which points at the "
                    "conversion scaling rather than the trained model. Report this result; "
                    "retraining will not change it.",
                )
            return
        if accuracy < _MIN_AKIDA_ACCURACY:
            raise AkidaModelJobError(
                "AKIDA_ACCURACY_BELOW_THRESHOLD",
                "Akida evaluation accuracy was below the required 96%; retrain the source model and create a new bundle.",
            )

    @staticmethod
    def _map_model(model: Any, require_hardware: bool) -> tuple[str, str | None]:
        import akida

        devices = list(akida.devices())
        if not devices:
            if require_hardware:
                raise AkidaModelJobError(
                    "PHYSICAL_HARDWARE_REQUIRED",
                    "No physical Akida device is available on the selected host.",
                )
            return "akd1000_simulator", None
        device = devices[0]
        model.map(device)
        return "hardware", str(device)

    @classmethod
    def _model_telemetry(cls, model: Any) -> dict[str, object]:
        telemetry: dict[str, object] = {}
        for key, value in cls._sdk_statistics(model).items():
            telemetry[key] = f"{value:.2f}"

        statistics = getattr(model, "statistics", None)
        if statistics is not None and not telemetry:
            telemetry["raw"] = str(statistics)

        return telemetry

    @classmethod
    def _visualization_layers(cls, model: Any) -> list[AkidaVisualizationLayer]:
        layers: list[AkidaVisualizationLayer] = []
        for index, layer in enumerate(model.layers):
            if index == 0:
                continue
            weight_shape: list[int] | None = None
            visualizable = True
            try:
                weight_shape = list(np.asarray(layer.get_variable("weights")).shape)
            except (AttributeError, KeyError, TypeError, ValueError):
                visualizable = False
            parameters = getattr(layer, "parameters", None)
            raw_bits = getattr(parameters, "weights_bits", None)
            weight_bits = int(raw_bits) if isinstance(raw_bits, int | np.integer) else None
            raw_output_shape = getattr(layer, "output_shape", ())
            output_shape = [int(value) for value in raw_output_shape] if raw_output_shape else []
            layers.append(
                AkidaVisualizationLayer(
                    index=index,
                    name=str(getattr(layer, "name", f"Layer {index}")),
                    outputShape=output_shape,
                    weightShape=weight_shape,
                    weightBits=weight_bits,
                    visualizable=visualizable,
                )
            )
        return layers
