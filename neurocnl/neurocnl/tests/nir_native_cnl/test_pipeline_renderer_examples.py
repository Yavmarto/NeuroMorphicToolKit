"""Tests for `NIR_Renderer.render_pipeline_config`.

_Validates: pipeline CNL grammar extension (Train/Evaluate/Export)_
"""

from __future__ import annotations

import pytest

from neurocnl.nir_cnl.parser import NIR_CNL_Parser
from neurocnl.nir_cnl.pipeline_config import PipelineConfig, extract_pipeline_config
from neurocnl.nir_cnl.renderer import NIR_Renderer


def test_render_pipeline_config_full() -> None:
    cfg = PipelineConfig(
        epochs=50,
        learning_rate=0.001,
        batch_size=32,
        optimizer="Adam",
        training_strategy="surrogate_gradient",
        loss_function="mse_count",
        run_evaluation=True,
        eval_metrics=("accuracy", "loss"),
        export_nir=True,
        generate_py_download=True,
    )
    text = NIR_Renderer().render_pipeline_config(cfg)
    assert text.startswith("Train the network for 50 epochs with")
    assert "Evaluate the network with accuracy and loss metrics." in text
    assert "Export the trained network to NIR and a Python script." in text


def test_render_pipeline_config_partial_only_export() -> None:
    text = NIR_Renderer().render_pipeline_config(PipelineConfig(export_nir=True))
    assert text == "Export the trained network to NIR.\n"


def test_render_pipeline_config_empty_returns_empty_string() -> None:
    assert NIR_Renderer().render_pipeline_config(PipelineConfig()) == ""


def test_render_pipeline_config_epochs_only_no_with_clause() -> None:
    text = NIR_Renderer().render_pipeline_config(PipelineConfig(epochs=10))
    assert text == "Train the network for 10 epochs.\n"


def test_render_pipeline_config_evaluate_bare_form_when_no_metrics() -> None:
    text = NIR_Renderer().render_pipeline_config(PipelineConfig(run_evaluation=True))
    assert text == "Evaluate the network.\n"


def test_render_pipeline_config_raises_on_train_field_without_epochs() -> None:
    with pytest.raises(ValueError):
        NIR_Renderer().render_pipeline_config(PipelineConfig(learning_rate=0.1))


@pytest.mark.parametrize(
    "cfg",
    [
        PipelineConfig(
            epochs=50,
            learning_rate=0.001,
            batch_size=32,
            optimizer="Adam",
            training_strategy="surrogate_gradient",
            loss_function="mse_count",
            run_evaluation=True,
            eval_metrics=("accuracy", "loss"),
            export_nir=True,
            generate_py_download=True,
        ),
        PipelineConfig(epochs=1),
        PipelineConfig(export_nir=True, generate_py_download=True),
        PipelineConfig(run_evaluation=True, eval_metrics=("loss",)),
    ],
)
def test_render_pipeline_config_round_trips_through_parser(cfg: PipelineConfig) -> None:
    text = NIR_Renderer().render_pipeline_config(cfg)
    records = NIR_CNL_Parser().parse(text)
    assert extract_pipeline_config(records) == cfg
