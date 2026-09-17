"""JSON manifest schema for conventional DNN accelerator targets."""

from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field


class ConventionalAcceleratorManifest(BaseModel):
    """Vendor toolchain metadata for export → compile → benchmark spikes.

    Separate from neuromorphic ``targets/*.json`` profiles — conventional
    accelerators share a DNN lifecycle, not SNN neuron/synapse limits.
    """

    model_config = ConfigDict(frozen=True, extra="forbid")

    id: str = Field(..., min_length=1, description="Stable accelerator id.")
    name: str = Field(..., min_length=1, description="Operator-facing label.")
    vendor: str = Field(..., min_length=1)
    required_format: str = Field(
        ...,
        description="Intermediate export format the vendor compiler accepts (e.g. onnx).",
    )
    artifact_format: str = Field(
        ...,
        description="Compiled runtime artifact extension or format name (e.g. axm, engine).",
    )
    compile_cmd: str = Field(
        ...,
        description="Repo-root command that compiles ``required_format`` into an artifact.",
    )
    benchmark_cmd: str | None = Field(
        default=None,
        description="Optional repo-root command for hardware or sim benchmark vs baseline.",
    )
    requires_hardware: bool = Field(
        default=False,
        description="True when the benchmark (not necessarily compile) needs real hardware.",
    )
    notes: str = Field(default="")


def load_manifest(path: Path) -> ConventionalAcceleratorManifest:
    """Load and validate a manifest JSON file."""
    import json

    data = json.loads(path.read_text(encoding="utf-8"))
    return ConventionalAcceleratorManifest(**data)
