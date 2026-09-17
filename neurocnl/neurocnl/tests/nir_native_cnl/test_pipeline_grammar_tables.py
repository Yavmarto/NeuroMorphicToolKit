"""Coverage tests for the pipeline (Train/Evaluate/Export) grammar tables.

Mirrors the invariants ``test_grammar_tables.py`` pins for the Primitive
noun-phrase tables: every id-to-phrase table must have a lossless
inverse, and no two ids may share a phrase.

_Validates: pipeline CNL grammar extension (Train/Evaluate/Export)_
"""

from __future__ import annotations

from neurocnl.nir_cnl.grammar_tables import (
    export_target_id_to_phrase,
    export_target_phrase_to_id,
    loss_function_id_to_phrase,
    loss_function_phrase_to_id,
    optimizer_id_to_phrase,
    optimizer_phrase_to_id,
    training_strategy_id_to_phrase,
    training_strategy_phrase_to_id,
)

_TABLE_PAIRS = [
    (optimizer_id_to_phrase, optimizer_phrase_to_id),
    (training_strategy_id_to_phrase, training_strategy_phrase_to_id),
    (loss_function_id_to_phrase, loss_function_phrase_to_id),
    (export_target_id_to_phrase, export_target_phrase_to_id),
]


def test_optimizer_phrases_is_inverse_of_id_to_phrase() -> None:
    for backend_id, phrase in optimizer_id_to_phrase.items():
        assert optimizer_phrase_to_id[phrase.lower()] == backend_id
    assert len(optimizer_phrase_to_id) == len(optimizer_id_to_phrase)


def test_training_strategy_phrases_is_inverse_of_id_to_phrase() -> None:
    for backend_id, phrase in training_strategy_id_to_phrase.items():
        assert training_strategy_phrase_to_id[phrase.lower()] == backend_id
    assert len(training_strategy_phrase_to_id) == len(training_strategy_id_to_phrase)


def test_loss_function_phrases_is_inverse_of_id_to_phrase() -> None:
    for backend_id, phrase in loss_function_id_to_phrase.items():
        assert loss_function_phrase_to_id[phrase.lower()] == backend_id
    assert len(loss_function_phrase_to_id) == len(loss_function_id_to_phrase)


def test_export_target_phrases_is_inverse_of_id_to_phrase() -> None:
    for field_name, phrase in export_target_id_to_phrase.items():
        assert export_target_phrase_to_id[phrase.lower()] == field_name
    assert len(export_target_phrase_to_id) == len(export_target_id_to_phrase)


def test_pipeline_phrase_tables_have_no_duplicate_phrases() -> None:
    for id_to_phrase, _phrase_to_id in _TABLE_PAIRS:
        phrases = [p.lower() for p in id_to_phrase.values()]
        assert len(set(phrases)) == len(phrases), f"Duplicate phrases in {id_to_phrase!r}"
