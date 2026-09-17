"""Public request and response contracts for notebook APIs.

The router re-exports these names for one compatibility release. New code
should import them from this module so transport and generation can evolve
independently.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field

from backend.app.schemas.pipeline_dag import PipelinePhasesPayload


class NotebookEntry(BaseModel):
    filename: str
    target: str
    support_level: str | None = None
    diagnostics: list[str] = Field(default_factory=list)


class EnsureWorkspaceRequest(BaseModel):
    workspace_path: str


class EnsureWorkspaceResponse(BaseModel):
    workspace_folder: str


class PipelineConfigPayload(BaseModel):
    """Execution parameters supplied by the Pipeline canvas tab."""

    dataset: str = ""
    custom_dataset_path: str = ""
    framework: str = "snntorch_sim"
    epochs: int = 50
    seed: int = 42
    learning_rate: float = 1e-3
    optimizer: str = "Adam"
    batch_size: int = 32
    run_evaluation: bool = True
    export_nir: bool = False
    eval_metrics: list[str] = Field(default_factory=lambda: ["accuracy", "loss"])
    generate_py_download: bool = True
    training_strategy: str = "surrogate_gradient"
    loss_function: str = "mse_count"
    surrogate_function: str = "fast_sigmoid"
    surrogate_slope: float = 25.0
    nengo_dt: float = 1e-4
    nengo_presentation_time: float = 1e-4
    nengo_probes: list[str] = Field(default_factory=lambda: ["spikes"])
    evaluation_profile: str = "classification"
    max_eval_batches: int | None = None


class GenerateV2Request(BaseModel):
    spec: str
    pipeline_config: PipelineConfigPayload = Field(
        default_factory=PipelineConfigPayload
    )
    pipeline_phases: PipelinePhasesPayload = Field(
        default_factory=PipelinePhasesPayload
    )
    pipeline_cnl: str = ""
    workspace_path: str = ""
    import_id: str = ""


class GenerateV2Response(BaseModel):
    workspace_folder: str
    notebooks: list[NotebookEntry]
    jupyter_url: str = ""
    generated_at: float = 0.0
    trainable: bool = True
    not_trainable_reason: str = ""


class AkidaMnistNotebookRequest(BaseModel):
    workspace_path: str = "akida-mnist"


class AkidaBundleArtifactResponse(BaseModel):
    filename: str
    bundle_base64: str
    sha256: str
    modified_at: float
    schema_version: int = 0


class TrainedNirArtifactResponse(BaseModel):
    filename: str
    nir_base64: str
    sha256: str
    modified_at: float


class DatasetSampleResponse(BaseModel):
    filename: str
    sample_index: int
    sample_count: int
    input_width: int
    label: int | None = None
    input_spikes: list[int]
    spike_count: int
    modified_at: float


class NotebookLastModifiedResponse(BaseModel):
    last_modified: float | None = None


class PipelineCnlRequest(BaseModel):
    pipeline_config: PipelineConfigPayload = Field(
        default_factory=PipelineConfigPayload
    )


class PipelineCnlResponse(BaseModel):
    cnl_text: str
    diagnostics: list[str] = Field(default_factory=list)


class ParsePipelineCnlRequest(BaseModel):
    cnl_text: str
    pipeline_config: PipelineConfigPayload = Field(
        default_factory=PipelineConfigPayload
    )


class ParsePipelineCnlResponse(BaseModel):
    pipeline_config: PipelineConfigPayload
    diagnostics: list[str] = Field(default_factory=list)


class DeployPreviewRequest(BaseModel):
    spec: str
    target: str


class DeployPreviewResponse(BaseModel):
    target: str
    support_level: str | None = None
    diagnostics: list[str] = Field(default_factory=list)
    io_error: str | None = None
    code: str


class ProvisionFromNotebookRequest(BaseModel):
    notebook_content: dict[str, Any]
    display_name: str = "Imported environment"


class ProvisionFromNotebookResponse(BaseModel):
    provisioned: bool
    reason: str = ""
    job_url: str = ""


__all__ = [
    "AkidaBundleArtifactResponse",
    "AkidaMnistNotebookRequest",
    "DatasetSampleResponse",
    "DeployPreviewRequest",
    "DeployPreviewResponse",
    "EnsureWorkspaceRequest",
    "EnsureWorkspaceResponse",
    "GenerateV2Request",
    "GenerateV2Response",
    "NotebookEntry",
    "NotebookLastModifiedResponse",
    "ParsePipelineCnlRequest",
    "ParsePipelineCnlResponse",
    "PipelineCnlRequest",
    "PipelineCnlResponse",
    "PipelineConfigPayload",
    "ProvisionFromNotebookRequest",
    "ProvisionFromNotebookResponse",
    "TrainedNirArtifactResponse",
]
