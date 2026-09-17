"""Pipeline (training/evaluation/export) config extraction.

This module bridges the CNL parser's `TrainingConfigRecord` /
`EvaluationConfigRecord` / `ExportConfigRecord` output to a single
plain dataclass, `PipelineConfig`, that backend code can merge onto a
`PipelineConfigPayload` (see `neurocnl.backend.app.routers.notebook`).

It is deliberately a sibling of `compiler.py`, not a modification to
it: `NIR_Compiler.compile()` keeps returning exactly `nir.NIRGraph`
with no pipeline metadata attached (see the compiler's Phase 0 comment
for why), and this module is where pipeline-config records go instead.
"""

from __future__ import annotations

from dataclasses import dataclass

from neurocnl.nir_cnl.ir_types import (
    EvaluationConfigRecord,
    ExportConfigRecord,
    NetworkContainer,
    NIREdgeRecord,
    NIRNodeRecord,
    TrainingConfigRecord,
)

__all__ = ["PipelineConfig", "extract_pipeline_config"]

_Record = (
    NIRNodeRecord
    | NIREdgeRecord
    | NetworkContainer
    | TrainingConfigRecord
    | EvaluationConfigRecord
    | ExportConfigRecord
)


@dataclass(frozen=True, slots=True)
class PipelineConfig:
    """CNL-derived training/evaluation/export config.

    Every field is `None`/`False`-by-omission — a `None` scalar or
    `False` boolean means "not specified by CNL", not "explicitly set
    to that value". Callers merge only the non-`None` fields (and,
    for the two export booleans, only the `True` ones) onto an
    existing `PipelineConfigPayload`; see
    `neurocnl.backend.app.routers.notebook._merge_cnl_pipeline_config`.
    """

    epochs: int | None = None
    learning_rate: float | None = None
    batch_size: int | None = None
    optimizer: str | None = None
    training_strategy: str | None = None
    loss_function: str | None = None
    run_evaluation: bool | None = None
    eval_metrics: tuple[str, ...] | None = None
    export_nir: bool | None = None
    generate_py_download: bool | None = None


def extract_pipeline_config(records: list[_Record]) -> PipelineConfig | None:
    """Extract pipeline config from a parsed CNL record list.

    Returns `None` iff *records* contains no `TrainingConfigRecord`,
    `EvaluationConfigRecord`, or `ExportConfigRecord`. When multiple
    records of the same kind are present (the grammar does not forbid
    repeating a `Train`/`Evaluate`/`Export` sentence), the *first* one
    wins — mirroring `NIR_Compiler`'s existing precedent for multiple
    `NetworkContainer` records ("this surface only honours the
    first").
    """
    training: TrainingConfigRecord | None = None
    evaluation: EvaluationConfigRecord | None = None
    export: ExportConfigRecord | None = None

    for rec in records:
        if isinstance(rec, TrainingConfigRecord) and training is None:
            training = rec
        elif isinstance(rec, EvaluationConfigRecord) and evaluation is None:
            evaluation = rec
        elif isinstance(rec, ExportConfigRecord) and export is None:
            export = rec

    if training is None and evaluation is None and export is None:
        return None

    return PipelineConfig(
        epochs=training.epochs if training is not None else None,
        learning_rate=training.learning_rate if training is not None else None,
        batch_size=training.batch_size if training is not None else None,
        optimizer=training.optimizer if training is not None else None,
        training_strategy=training.training_strategy if training is not None else None,
        loss_function=training.loss_function if training is not None else None,
        run_evaluation=True if evaluation is not None else None,
        eval_metrics=evaluation.eval_metrics if evaluation is not None else None,
        # The grammar has no negative form (Requirement/Non-goal: no
        # CNL-native way to force a boolean False), so a target's
        # *absence* from the Export sentence must surface as "not
        # specified" (None) rather than False, or a caller merging
        # this onto an existing PipelineConfigPayload would silently
        # disable a target the user never mentioned.
        export_nir=(True if export is not None and export.export_nir else None),
        generate_py_download=(True if export is not None and export.generate_py_download else None),
    )
