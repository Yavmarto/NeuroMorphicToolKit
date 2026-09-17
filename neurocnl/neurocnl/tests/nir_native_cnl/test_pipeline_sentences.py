"""Tests for the Train / Evaluate / Export CNL sentence forms.

Covers the new grammar added alongside `Define`/`Create`/`Connect`:
happy-path parsing, per-clause error diagnostics, and a dispatch-order
regression pinning that a node literally named ``Train``/``Evaluate``/
``Export`` followed by an active-voice edge sentence is unaffected.

_Validates: pipeline CNL grammar extension (Train/Evaluate/Export)_
"""

from __future__ import annotations

import pytest

from neurocnl.nir_cnl.errors import ParseError
from neurocnl.nir_cnl.ir_types import (
    EvaluationConfigRecord,
    ExportConfigRecord,
    NetworkContainer,
    NIREdgeRecord,
    NIRNodeRecord,
    TrainingConfigRecord,
)
from neurocnl.nir_cnl.parser import NIR_CNL_Parser


def _parse_one(
    text: str,
) -> (
    NIRNodeRecord
    | NIREdgeRecord
    | NetworkContainer
    | TrainingConfigRecord
    | EvaluationConfigRecord
    | ExportConfigRecord
):
    records = NIR_CNL_Parser().parse(text)
    assert len(records) == 1
    return records[0]


def _codes(exc_info: pytest.ExceptionInfo[ParseError]) -> set[str]:
    return {d.code for d in exc_info.value.errors}


# ---------------------------------------------------------------------------
# Train
# ---------------------------------------------------------------------------


def test_train_sentence_parses_all_clauses() -> None:
    rec = _parse_one(
        "Train the network for 50 epochs with learning rate 0.001, "
        "batch size 32, Adam optimizer, surrogate gradient training "
        "strategy, and mse count loss."
    )
    assert rec == TrainingConfigRecord(
        epochs=50,
        learning_rate=0.001,
        batch_size=32,
        optimizer="Adam",
        training_strategy="surrogate_gradient",
        loss_function="mse_count",
        line=1,
    )


def test_train_sentence_epochs_only_leaves_other_fields_none() -> None:
    rec = _parse_one("Train the network for 10 epochs.")
    assert rec == TrainingConfigRecord(
        epochs=10,
        learning_rate=None,
        batch_size=None,
        optimizer=None,
        training_strategy=None,
        loss_function=None,
        line=1,
    )


def test_train_sentence_clause_order_is_independent() -> None:
    rec = _parse_one(
        "Train the network for 5 epochs with mse count loss, Adam "
        "optimizer, and learning rate 0.01."
    )
    assert isinstance(rec, TrainingConfigRecord)
    assert rec.loss_function == "mse_count"
    assert rec.optimizer == "Adam"
    assert rec.learning_rate == 0.01


def test_train_sentence_rejects_unknown_optimizer_phrase() -> None:
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse("Train the network for 5 epochs with foo optimizer.")
    assert "unknown_optimizer_phrase" in _codes(exc_info)


def test_train_sentence_rejects_unknown_training_strategy_phrase() -> None:
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(
            "Train the network for 5 epochs with foo training strategy."
        )
    assert "unknown_training_strategy_phrase" in _codes(exc_info)


def test_train_sentence_rejects_unknown_loss_function_phrase() -> None:
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse("Train the network for 5 epochs with foo loss.")
    assert "unknown_loss_function_phrase" in _codes(exc_info)


def test_train_sentence_rejects_duplicate_clause() -> None:
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(
            "Train the network for 5 epochs with Adam optimizer, SGD optimizer."
        )
    assert "duplicate_pipeline_clause" in _codes(exc_info)


def test_train_sentence_requires_numeric_epoch_count() -> None:
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse("Train the network for many epochs.")
    assert "invalid_value" in _codes(exc_info)


# ---------------------------------------------------------------------------
# Evaluate
# ---------------------------------------------------------------------------


def test_evaluate_sentence_with_metrics() -> None:
    rec = _parse_one("Evaluate the network with accuracy and loss metrics.")
    assert rec == EvaluationConfigRecord(eval_metrics=("accuracy", "loss"), line=1)


def test_evaluate_sentence_bare_form_sets_metrics_none() -> None:
    rec = _parse_one("Evaluate the network.")
    assert rec == EvaluationConfigRecord(eval_metrics=None, line=1)


def test_evaluate_sentence_single_metric() -> None:
    rec = _parse_one("Evaluate the network with accuracy metrics.")
    assert isinstance(rec, EvaluationConfigRecord)
    assert rec.eval_metrics == ("accuracy",)


def test_evaluate_sentence_rejects_empty_metric_list() -> None:
    with pytest.raises(ParseError):
        NIR_CNL_Parser().parse("Evaluate the network with metrics.")


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------


def test_export_sentence_nir_only() -> None:
    rec = _parse_one("Export the trained network to NIR.")
    assert rec == ExportConfigRecord(
        export_nir=True, generate_py_download=False, line=1
    )


def test_export_sentence_both_targets() -> None:
    rec = _parse_one("Export the trained network to NIR and a Python script.")
    assert rec == ExportConfigRecord(export_nir=True, generate_py_download=True, line=1)


def test_export_sentence_requires_at_least_one_target() -> None:
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse("Export the trained network to.")
    assert "unknown_export_target_phrase" in _codes(
        exc_info
    ) or "syntax_error" in _codes(exc_info)


def test_export_sentence_rejects_unknown_target_phrase() -> None:
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse("Export the trained network to ONNX.")
    assert "unknown_export_target_phrase" in _codes(exc_info)


def test_export_sentence_rejects_duplicate_target() -> None:
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse("Export the trained network to NIR and NIR.")
    assert "duplicate_pipeline_clause" in _codes(exc_info)


# ---------------------------------------------------------------------------
# Dispatch-order regression
# ---------------------------------------------------------------------------


def test_pipeline_sentences_do_not_participate_in_duplicate_identifier_check() -> None:
    # A node named "epochs" and a Train sentence's "epochs" keyword must
    # not collide via the identifier-uniqueness tracker.
    records = NIR_CNL_Parser().parse(
        "Define a network named demo.\n"
        "Define an input port named epochs with shape (1,).\n"
        "Train the network for 5 epochs.\n"
    )
    assert len(records) == 3


def test_node_named_train_then_active_voice_edge_still_parses_as_edge() -> None:
    # Active-voice edge detection (`<id> connects to <id>.`) runs before
    # the Train/Evaluate/Export verb dispatch, so a node identifier that
    # happens to be "Train" is unaffected.
    records = NIR_CNL_Parser().parse(
        "Define a network named demo.\n"
        "Define an input port named Train with shape (1,).\n"
        "Define an output port named out1 with shape (1,).\n"
        "Train connects to out1.\n"
    )
    edge_records = [r for r in records if isinstance(r, NIREdgeRecord)]
    assert len(edge_records) == 1
    assert edge_records[0].src == "Train"
    assert edge_records[0].target == "out1"
