"""Tests for `nir_cnl.pipeline_config.extract_pipeline_config` and the
compiler's pass-through of pipeline config records.

_Validates: pipeline CNL grammar extension (Train/Evaluate/Export)_
"""

from __future__ import annotations

import nir

from neurocnl.nir_cnl.compiler import NIR_Compiler
from neurocnl.nir_cnl.ir_types import (
    EvaluationConfigRecord,
    ExportConfigRecord,
    NetworkContainer,
    NIREdgeRecord,
    NIRNodeRecord,
    TrainingConfigRecord,
)
from neurocnl.nir_cnl.parser import NIR_CNL_Parser
from neurocnl.nir_cnl.pipeline_config import PipelineConfig, extract_pipeline_config


def test_extract_pipeline_config_returns_none_without_pipeline_sentences() -> None:
    records = NIR_CNL_Parser().parse(
        "Define a network named demo.\nDefine an input port named in1 with shape (1,).\n"
    )
    assert extract_pipeline_config(records) is None


def test_extract_pipeline_config_merges_train_evaluate_export_independently() -> None:
    records = NIR_CNL_Parser().parse(
        "Train the network for 5 epochs with learning rate 0.01.\n"
        "Evaluate the network with accuracy metrics.\n"
        "Export the trained network to NIR.\n"
    )
    cfg = extract_pipeline_config(records)
    assert cfg == PipelineConfig(
        epochs=5,
        learning_rate=0.01,
        run_evaluation=True,
        eval_metrics=("accuracy",),
        export_nir=True,
    )


_CompilerRecord = (
    NIRNodeRecord
    | NIREdgeRecord
    | NetworkContainer
    | TrainingConfigRecord
    | EvaluationConfigRecord
    | ExportConfigRecord
)


def test_extract_pipeline_config_first_wins_on_duplicate_train_sentences() -> None:
    records: list[_CompilerRecord] = [
        TrainingConfigRecord(
            epochs=5,
            learning_rate=None,
            batch_size=None,
            optimizer=None,
            training_strategy=None,
            loss_function=None,
            line=1,
        ),
        TrainingConfigRecord(
            epochs=99,
            learning_rate=None,
            batch_size=None,
            optimizer=None,
            training_strategy=None,
            loss_function=None,
            line=2,
        ),
    ]
    cfg = extract_pipeline_config(records)
    assert cfg is not None
    assert cfg.epochs == 5


def test_extract_pipeline_config_export_absent_target_is_none_not_false() -> None:
    records: list[_CompilerRecord] = [
        ExportConfigRecord(export_nir=True, generate_py_download=False, line=1)
    ]
    cfg = extract_pipeline_config(records)
    assert cfg is not None
    assert cfg.export_nir is True
    # generate_py_download was never mentioned in the sentence, so it
    # must surface as "not specified" (None), not an explicit False —
    # a merge onto an existing PipelineConfigPayload must not disable a
    # target the CNL text never mentioned.
    assert cfg.generate_py_download is None


def test_extract_pipeline_config_evaluate_without_metrics_still_sets_run_evaluation() -> (
    None
):
    records: list[_CompilerRecord] = [EvaluationConfigRecord(eval_metrics=None, line=1)]
    cfg = extract_pipeline_config(records)
    assert cfg is not None
    assert cfg.run_evaluation is True
    assert cfg.eval_metrics is None


def test_compiler_ignores_pipeline_config_records() -> None:
    records = NIR_CNL_Parser().parse(
        "Define a network named demo.\n"
        "Define an input port named in1 with shape (1,).\n"
        "Define an output port named out1 with shape (1,).\n"
        "Connect in1 to out1.\n"
        "Train the network for 5 epochs.\n"
        "Evaluate the network.\n"
        "Export the trained network to NIR.\n"
    )
    graph = NIR_Compiler().compile(records)
    assert isinstance(graph, nir.NIRGraph)
    assert set(graph.nodes.keys()) == {"in1", "out1"}
