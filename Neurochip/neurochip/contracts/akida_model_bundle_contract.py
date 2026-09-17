"""Versioned contract for portable ONNX-to-Akida model bundles."""

from __future__ import annotations

from pathlib import PurePosixPath
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from .._compat import StrEnum

AKIDA_MODEL_BUNDLE_SCHEMA_VERSION = 1
AKIDA_MODEL_BUNDLE_MAX_BYTES = 32 * 1024 * 1024
AKIDA_MODEL_BUNDLE_REQUIRED_FILES = frozenset(
    {"manifest.json", "model.onnx", "calibration.npy", "evaluation.npz"}
)

AKIDA_MODEL_BUNDLE_V2_SCHEMA_VERSION = 2
AKIDA_MODEL_BUNDLE_V2_REQUIRED_FILES = frozenset({"manifest.json", "model.fbz", "evaluation.npz"})


class AkidaBundleInputV1(BaseModel):
    """Input tensor description used by conversion and inference."""

    model_config = ConfigDict(populate_by_name=True, frozen=True)

    shape: list[int] = Field(min_length=2, max_length=5)
    layout: Literal["NCHW", "NHWC"]
    dtype: Literal["float32", "uint8"]

    @field_validator("shape")
    @classmethod
    def validate_shape(cls, value: list[int]) -> list[int]:
        """Reject dynamic, empty, or implausibly large tensor dimensions."""
        if any(dimension <= 0 or dimension > 16_384 for dimension in value):
            raise ValueError("input shape dimensions must be between 1 and 16384")
        return value


class AkidaBundlePreprocessingV1(BaseModel):
    """Preprocessing applied before source and ONNX inference."""

    model_config = ConfigDict(populate_by_name=True, frozen=True)

    scale: float = Field(gt=0)
    offset: float = 0.0
    calibration_dtype: Literal["float32"] = "float32"
    evaluation_dtype: Literal["uint8"] = "uint8"


class AkidaModelBundleV1(BaseModel):
    """Manifest stored as ``manifest.json`` inside an Akida model bundle."""

    model_config = ConfigDict(populate_by_name=True, frozen=True, extra="forbid")

    schema_version: Literal[1] = Field(alias="schemaVersion")
    bundle_type: Literal["nmtk.akida.model"] = Field(alias="bundleType")
    model_name: str = Field(alias="modelName", min_length=1, max_length=128)
    source_framework: Literal["pytorch"] = Field(alias="sourceFramework")
    target: Literal["akida2"] = "akida2"
    input: AkidaBundleInputV1
    preprocessing: AkidaBundlePreprocessingV1
    labels: list[str] = Field(min_length=2, max_length=10_000)
    source_metrics: dict[str, float] = Field(alias="sourceMetrics")
    dependency_versions: dict[str, str] = Field(alias="dependencyVersions")
    files: dict[str, str]

    @field_validator("files")
    @classmethod
    def validate_files(cls, value: dict[str, str]) -> dict[str, str]:
        """Require all payload files and lowercase SHA-256 digests."""
        required_payloads = AKIDA_MODEL_BUNDLE_REQUIRED_FILES - {"manifest.json"}
        missing = required_payloads - value.keys()
        if missing:
            raise ValueError(f"missing checksums for: {', '.join(sorted(missing))}")
        for filename, digest in value.items():
            if filename.startswith("/") or ".." in filename.split("/"):
                raise ValueError("file checksum entries must use safe relative paths")
            if len(digest) != 64 or any(ch not in "0123456789abcdef" for ch in digest):
                raise ValueError(f"invalid SHA-256 checksum for {filename}")
        return value


class AkidaBundlePreprocessingV2(BaseModel):
    """Preprocessing for a bundle whose model is already converted.

    No calibration entry: nothing on the host quantizes a V2 bundle, so there is
    no calibration set to describe. `scale` is the factor the exporter used to
    turn float inputs into the quantized integers in ``evaluation.npz``.
    """

    model_config = ConfigDict(populate_by_name=True, frozen=True)

    scale: float = Field(gt=0)
    offset: float = 0.0
    evaluation_dtype: Literal["uint8"] = "uint8"


class AkidaModelBundleV2(BaseModel):
    """Manifest for a bundle carrying an already-converted ``model.fbz``.

    V1 ships an ONNX model and the host quantizes it with QuantizeML. V2 ships
    the finished Akida model instead, which is what the canvas Akida Exporter
    produces: the conversion happens where the trained weights and the NIR graph
    already are, and the host only maps and evaluates it.

    Consequently there is no ONNX-parity metric to check and no source-accuracy
    gate -- the bundle reports what it measured on the simulator, and the host
    reports what it measures on the card. Comparing those two is the point.
    """

    model_config = ConfigDict(populate_by_name=True, frozen=True, extra="forbid")

    schema_version: Literal[2] = Field(alias="schemaVersion")
    bundle_type: Literal["nmtk.akida.model"] = Field(alias="bundleType")
    model_name: str = Field(alias="modelName", min_length=1, max_length=128)
    source_framework: Literal["pytorch", "snntorch"] = Field(alias="sourceFramework")
    target: Literal["akida2"] = "akida2"
    input: AkidaBundleInputV1
    preprocessing: AkidaBundlePreprocessingV2
    labels: list[str] = Field(min_length=2, max_length=10_000)
    source_metrics: dict[str, float] = Field(alias="sourceMetrics")
    dependency_versions: dict[str, str] = Field(alias="dependencyVersions")
    files: dict[str, str]

    @field_validator("files")
    @classmethod
    def validate_files(cls, value: dict[str, str]) -> dict[str, str]:
        """Require all V2 payload files and lowercase SHA-256 digests."""
        required_payloads = AKIDA_MODEL_BUNDLE_V2_REQUIRED_FILES - {"manifest.json"}
        missing = required_payloads - value.keys()
        if missing:
            raise ValueError(f"missing checksums for: {', '.join(sorted(missing))}")
        for filename, digest in value.items():
            if filename.startswith("/") or ".." in filename.split("/"):
                raise ValueError("file checksum entries must use safe relative paths")
            if len(digest) != 64 or any(ch not in "0123456789abcdef" for ch in digest):
                raise ValueError(f"invalid SHA-256 checksum for {filename}")
        return value


class AkidaModelJobStage(StrEnum):
    """Stable stages surfaced to Studio while an Akida job runs."""

    VALIDATION = "validation"
    QUANTIZATION = "quantization"
    CONVERSION = "conversion"
    MAPPING = "mapping"
    EVALUATION = "evaluation"
    COMPLETED = "completed"
    FAILED = "failed"


class AkidaModelJobRequest(BaseModel):
    """Encoded bundle submission accepted by Neurochip and launcher proxy."""

    model_config = ConfigDict(populate_by_name=True, extra="forbid")

    filename: str = Field(min_length=1, max_length=255)
    bundle_base64: str = Field(alias="bundleBase64", min_length=1, max_length=45 * 1024 * 1024)
    sha256: str = Field(min_length=64, max_length=64)
    require_physical_hardware: bool = Field(default=True, alias="requirePhysicalHardware")

    @field_validator("filename")
    @classmethod
    def validate_filename(cls, value: str) -> str:
        """Accept only the dedicated portable-bundle suffix and a base name."""
        if value != PurePosixPath(value).name or not value.endswith(".akida-bundle.zip"):
            raise ValueError("filename must end with .akida-bundle.zip and contain no path")
        return value

    @field_validator("sha256")
    @classmethod
    def validate_sha256(cls, value: str) -> str:
        """Require a lowercase hexadecimal bundle checksum."""
        normalized = value.lower()
        if any(character not in "0123456789abcdef" for character in normalized):
            raise ValueError("sha256 must be a hexadecimal checksum")
        return normalized


class AkidaClassResult(BaseModel):
    """Per-class outcome of a whole-dataset evaluation.

    ``metrics`` is ``dict[str, float]`` and cannot carry this, so per-class
    results live in their own field. Only produced for V2 bundles: the V1 path
    goes through ``akida.Model.evaluate``, which returns a single accuracy and
    no per-sample predictions to bucket.
    """

    model_config = ConfigDict(populate_by_name=True)

    label: int = Field(ge=0)
    label_name: str = Field(alias="labelName")
    support: int = Field(ge=0, description="Samples in the set with this true label.")
    correct: int = Field(ge=0, description="Of those, how many the card got right.")

    @property
    def accuracy(self) -> float | None:
        """Fraction correct, or None when the set contains no such label."""
        if self.support == 0:
            return None
        return self.correct / self.support


class AkidaModelJobStatus(BaseModel):
    """Persisted, retry-safe model conversion job status."""

    model_config = ConfigDict(populate_by_name=True)

    job_id: str = Field(alias="jobId")
    bundle_sha256: str = Field(alias="bundleSha256")
    stage: AkidaModelJobStage
    progress: int = Field(ge=0, le=100)
    message: str
    model_id: str | None = Field(default=None, alias="modelId")
    runtime_target: str = Field(default="unknown", alias="runtimeTarget")
    hardware_verified: bool = Field(default=False, alias="hardwareVerified")
    metrics: dict[str, float] = Field(default_factory=dict)
    # Number of samples the evaluation actually scored. Sent so the client can
    # bound its sample-index input instead of discovering the ceiling by
    # triggering SAMPLE_INDEX_INVALID.
    total_samples: int | None = Field(default=None, alias="totalSamples", ge=0)
    class_results: list[AkidaClassResult] | None = Field(default=None, alias="classResults")
    device_info: str | None = Field(default=None, alias="deviceInfo")
    error_code: str | None = Field(default=None, alias="errorCode")


class AkidaModelInferenceRequest(BaseModel):
    """Request inference for one bundled evaluation sample or explicit image."""

    model_config = ConfigDict(populate_by_name=True, extra="forbid")

    sample_index: int | None = Field(default=None, alias="sampleIndex", ge=0)
    input_values: list[int] | None = Field(default=None, alias="inputValues", max_length=1_000_000)


class LayerSpikeStats(BaseModel):
    """Per-layer spike count reported by the Akida SDK after one inference."""

    model_config = ConfigDict(populate_by_name=True)

    name: str
    nz_spikes: int = Field(alias="nzSpikes")


class AkidaModelInferenceResult(BaseModel):
    """Physical/simulator inference result for a converted bundle model."""

    model_config = ConfigDict(populate_by_name=True)

    model_id: str = Field(alias="modelId")
    sample_index: int | None = Field(alias="sampleIndex")
    prediction: int
    label: int | None = None
    label_name: str = Field(alias="labelName")
    outputs: list[float]
    runtime_target: str = Field(alias="runtimeTarget")
    hardware_verified: bool = Field(alias="hardwareVerified")
    telemetry: dict[str, object] = Field(default_factory=dict)
    layer_spikes: list[LayerSpikeStats] | None = Field(
        default=None,
        alias="layerSpikes",
        description="Per-layer non-zero spike counts from the Akida SDK. "
        "Present only when the SDK exposes per-layer statistics.",
    )


class AkidaVisualizationMode(StrEnum):
    """Whether replay covers one evaluation sample or the whole set."""

    SAMPLE = "sample"
    BENCHMARK = "benchmark"


class AkidaModelVisualizationRequest(BaseModel):
    """Select one deployed-model layer for truthful software replay."""

    model_config = ConfigDict(populate_by_name=True, extra="forbid")

    mode: AkidaVisualizationMode
    layer_index: int = Field(default=1, alias="layerIndex", ge=1)
    sample_index: int | None = Field(default=None, alias="sampleIndex", ge=0)


class AkidaCompressedArray(BaseModel):
    """A NumPy-compatible array compressed for transfer to Studio."""

    model_config = ConfigDict(populate_by_name=True)

    encoding: Literal["zlib+base64"] = "zlib+base64"
    dtype: str
    shape: list[int]
    data: str


class AkidaVisualizationLayer(BaseModel):
    """One layer available from the exact deployed Akida model."""

    model_config = ConfigDict(populate_by_name=True)

    index: int = Field(ge=1)
    name: str
    output_shape: list[int] = Field(default_factory=list, alias="outputShape")
    weight_shape: list[int] | None = Field(default=None, alias="weightShape")
    weight_bits: int | None = Field(default=None, alias="weightBits", ge=1)
    visualizable: bool = True


class AkidaModelVisualizationResult(BaseModel):
    """Companion visualization replayed from the deployed ``model.fbz``.

    The visualization is deliberately never hardware-verified. Physical-card
    inference and benchmark results remain separate contracts.
    """

    model_config = ConfigDict(populate_by_name=True)

    model_id: str = Field(alias="modelId")
    mode: AkidaVisualizationMode
    layers: list[AkidaVisualizationLayer]
    layer_index: int = Field(alias="layerIndex", ge=1)
    layer_name: str = Field(alias="layerName")
    sample_index: int | None = Field(default=None, alias="sampleIndex")
    sample_count: int = Field(alias="sampleCount", ge=1)
    available: bool
    unavailable_reason: str | None = Field(default=None, alias="unavailableReason")
    activity: AkidaCompressedArray | None = None
    raster: AkidaCompressedArray | None = None
    weights: AkidaCompressedArray | None = None
    weight_bits: int | None = Field(default=None, alias="weightBits", ge=1)
    provenance: Literal["akida_software_replay"] = "akida_software_replay"
    related_runtime_target: str = Field(alias="relatedRuntimeTarget")
    hardware_verified: Literal[False] = Field(default=False, alias="hardwareVerified")
