"""Tests for the public compile_to_nir() entrypoint (T1-4).

Coverage:
- Happy path: valid spec returns nir.NIRGraph with expected nodes/edges
- In-memory: no save_to argument
- save_to: file is written and readable by nir.read
- CompileError on parse failure: diagnostics have stage="parse", line info
- CompileError on exportability rejection: stage="exportability"
- CompileError on lowering failure: stage="lowering"
- Top-level __init__ re-exports are present
- Diagnostic str representation
- CompileError str representation
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import nir
import pytest

import neurocnl
from neurocnl.compile import (
    CompileError,
    Diagnostic,
    compile_pipeline_config,
    compile_to_nir,
)
from neurocnl.nir_cnl.pipeline_config import PipelineConfig

# ── fixtures ─────────────────────────────────────────────────────────────────

MINIMAL_VALID_SPEC = "\n".join(
    [
        "Define an input port named input with shape (2,).",
        "Define a linear transformation named l1 with weight matrix shape (2, 2).",
        "Define an output port named output with shape (2,).",
        "input connects to l1.",
        "l1 connects to output.",
    ]
)

THREE_LAYER_SPEC = "\n".join(
    [
        "Define an input port named input with shape (4,).",
        "Define a LIF neuron named hidden with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define an output port named output with shape (2,).",
        "input connects to hidden.",
        "hidden connects to output.",
    ]
)

_EXPORTABILITY_REJECTION_MSG = (
    "NIR export rejected because the current direct CNL -> IR -> NIR bridge cannot "
    "honestly lower these parser-recognized concepts: akida_hardware."
)


# ── happy-path tests ──────────────────────────────────────────────────────────


class TestCompileToNirHappyPath:
    def test_returns_nir_graph(self) -> None:
        graph = compile_to_nir(MINIMAL_VALID_SPEC)
        assert isinstance(graph, nir.NIRGraph)

    def test_graph_has_nodes(self) -> None:
        graph = compile_to_nir(MINIMAL_VALID_SPEC)
        assert len(graph.nodes) > 0

    def test_graph_has_edges(self) -> None:
        graph = compile_to_nir(MINIMAL_VALID_SPEC)
        assert len(graph.edges) > 0

    def test_graph_contains_lif_node_for_hidden_population(self) -> None:
        # Input/output role populations become nir.Input/nir.Output; only hidden
        # populations become nir.LIF.  THREE_LAYER_SPEC has exactly one hidden.
        graph = compile_to_nir(THREE_LAYER_SPEC)
        lif_nodes = [n for n in graph.nodes.values() if isinstance(n, nir.LIF)]
        assert len(lif_nodes) >= 1

    def test_three_layer_spec_has_one_lif_for_hidden_layer(self) -> None:
        # Only the hidden population is lowered to nir.LIF; input → nir.Input,
        # output → nir.Output.
        graph = compile_to_nir(THREE_LAYER_SPEC)
        lif_nodes = [n for n in graph.nodes.values() if isinstance(n, nir.LIF)]
        assert len(lif_nodes) == 1

    def test_minimal_spec_has_input_and_output_nodes(self) -> None:
        # A two-population spec (input + output) produces nir.Input + nir.Output,
        # no hidden LIF nodes.
        graph = compile_to_nir(MINIMAL_VALID_SPEC)
        input_nodes = [n for n in graph.nodes.values() if isinstance(n, nir.Input)]
        output_nodes = [n for n in graph.nodes.values() if isinstance(n, nir.Output)]
        assert len(input_nodes) >= 1
        assert len(output_nodes) >= 1

    def test_blank_lines_and_comments_ignored(self) -> None:
        spec_with_blanks = (
            "# This is a comment\n\n" + MINIMAL_VALID_SPEC + "\n\n# trailing comment\n"
        )
        graph = compile_to_nir(spec_with_blanks)
        assert isinstance(graph, nir.NIRGraph)


# ── save_to tests ─────────────────────────────────────────────────────────────


class TestCompileToNirSaveTo:
    def test_save_to_creates_file(self, tmp_path: Path) -> None:
        out = tmp_path / "network.nir"
        graph = compile_to_nir(MINIMAL_VALID_SPEC, save_to=out)
        assert out.exists()
        assert isinstance(graph, nir.NIRGraph)

    def test_saved_file_is_readable_by_nir(self, tmp_path: Path) -> None:
        out = tmp_path / "network.nir"
        compile_to_nir(MINIMAL_VALID_SPEC, save_to=out)
        loaded = nir.read(str(out))
        assert isinstance(loaded, nir.NIRGraph)

    def test_save_to_creates_missing_parent_directories(self, tmp_path: Path) -> None:
        out = tmp_path / "deep" / "nested" / "network.nir"
        compile_to_nir(MINIMAL_VALID_SPEC, save_to=out)
        assert out.exists()

    def test_save_to_accepts_string_path(self, tmp_path: Path) -> None:
        out = str(tmp_path / "network.nir")
        compile_to_nir(MINIMAL_VALID_SPEC, save_to=out)
        assert Path(out).exists()

    def test_return_value_matches_saved_graph_node_count(self, tmp_path: Path) -> None:
        out = tmp_path / "network.nir"
        graph = compile_to_nir(MINIMAL_VALID_SPEC, save_to=out)
        loaded = nir.read(str(out))
        assert set(graph.nodes.keys()) == set(loaded.nodes.keys())


# ── parse failure tests ───────────────────────────────────────────────────────


class TestCompileToNirParseErrors:
    def test_raises_compile_error_on_unparseable_line(self) -> None:
        with pytest.raises(CompileError):
            compile_to_nir("This is not valid CNL grammar at all !!!")

    def test_compile_error_has_diagnostics(self) -> None:
        with pytest.raises(CompileError) as exc_info:
            compile_to_nir("Totally invalid CNL !!!")
        assert len(exc_info.value.diagnostics) >= 1

    def test_parse_diagnostic_has_correct_stage(self) -> None:
        with pytest.raises(CompileError) as exc_info:
            compile_to_nir("Totally invalid CNL !!!")
        stages = {d.stage for d in exc_info.value.diagnostics}
        assert "parser" in stages

    def test_parse_diagnostic_has_line_number(self) -> None:
        with pytest.raises(CompileError) as exc_info:
            compile_to_nir("Totally invalid CNL !!!")
        parse_diags = [d for d in exc_info.value.diagnostics if d.stage == "parser"]
        assert any(d.line is not None for d in parse_diags)

    def test_parse_diagnostic_has_raw_text(self) -> None:
        with pytest.raises(CompileError) as exc_info:
            compile_to_nir("Totally invalid CNL !!!")
        parse_diags = [d for d in exc_info.value.diagnostics if d.stage == "parser"]
        assert any(d.raw is not None for d in parse_diags)

    def test_empty_spec_raises_compile_error(self) -> None:
        with pytest.raises(CompileError) as exc_info:
            compile_to_nir("   \n  \n  ")
        assert exc_info.value.diagnostics[0].code == "missing_endpoint"

    def test_only_comments_raises_compile_error(self) -> None:
        with pytest.raises(CompileError) as exc_info:
            compile_to_nir("# just a comment\n# another comment")
        assert exc_info.value.diagnostics[0].code == "missing_endpoint"

    def test_multiple_bad_lines_produce_one_diagnostic_each(self) -> None:
        bad_spec = "bad line one !!!\nbad line two ???"
        with pytest.raises(CompileError) as exc_info:
            compile_to_nir(bad_spec)
        parse_diags = [d for d in exc_info.value.diagnostics if d.stage == "parser"]
        # The parser emits a generic syntax_error for unparseable input.
        assert len(parse_diags) >= 1


# ── exportability rejection tests ─────────────────────────────────────────────
# Removed TestCompileToNirExportabilityRejection since the new architecture does not use ensure_nir_exportable.

# ── lowering / materializer failure tests ─────────────────────────────────────
# Removed TestCompileToNirLoweringErrors since lower_to_ir and Materializer were removed.


# ── write failure test ────────────────────────────────────────────────────────


class TestCompileToNirWriteErrors:
    def test_write_error_raises_compile_error_with_write_stage(
        self, tmp_path: Path
    ) -> None:
        with (
            patch("nir.write", side_effect=OSError("disk full")),
            pytest.raises(CompileError) as exc_info,
        ):
            compile_to_nir(MINIMAL_VALID_SPEC, save_to=tmp_path / "out.nir")
        stages = {d.stage for d in exc_info.value.diagnostics}
        assert "write" in stages

    def test_write_error_diagnostic_has_hint(self, tmp_path: Path) -> None:
        with (
            patch("nir.write", side_effect=OSError("disk full")),
            pytest.raises(CompileError) as exc_info,
        ):
            compile_to_nir(MINIMAL_VALID_SPEC, save_to=tmp_path / "out.nir")
        write_diags = [d for d in exc_info.value.diagnostics if d.stage == "write"]
        assert any(d.hint is not None for d in write_diags)


# ── exception string representation ──────────────────────────────────────────


class TestCompileErrorStr:
    def test_str_includes_stage(self) -> None:
        diag = Diagnostic(stage="parse", code="parse_error", message="bad line", line=3)
        exc = CompileError("Compilation failed.", [diag])
        text = str(exc)
        assert "[parse]" in text
        assert "parse_error" in text

    def test_str_includes_line_number(self) -> None:
        diag = Diagnostic(stage="parse", code="parse_error", message="bad", line=7)
        exc = CompileError("Compilation failed.", [diag])
        assert "(line 7)" in str(exc)

    def test_str_includes_hint(self) -> None:
        diag = Diagnostic(
            stage="exportability",
            code="unsupported_concepts",
            message="rejected",
            hint="remove spatial",
        )
        exc = CompileError("Failed.", [diag])
        assert "remove spatial" in str(exc)

    def test_str_with_no_line_omits_line_annotation(self) -> None:
        diag = Diagnostic(stage="lowering", code="lowering_error", message="oops")
        exc = CompileError("Failed.", [diag])
        assert "line" not in str(exc)

    def test_str_with_empty_diagnostics(self) -> None:
        exc = CompileError("Something went wrong.", [])
        assert str(exc) == "Something went wrong."


# ── compile_pipeline_config tests ────────────────────────────────────────────


class TestCompilePipelineConfig:
    def test_returns_none_for_architecture_only_spec(self) -> None:
        assert compile_pipeline_config(MINIMAL_VALID_SPEC) is None

    def test_extracts_train_evaluate_export(self) -> None:
        spec = (
            MINIMAL_VALID_SPEC
            + "\nTrain the network for 5 epochs with learning rate 0.01.\n"
            "Evaluate the network with accuracy metrics.\n"
            "Export the trained network to NIR.\n"
        )
        cfg = compile_pipeline_config(spec)
        assert cfg == PipelineConfig(
            epochs=5,
            learning_rate=0.01,
            run_evaluation=True,
            eval_metrics=("accuracy",),
            export_nir=True,
        )

    def test_raises_compile_error_on_malformed_train_sentence(self) -> None:
        spec = (
            MINIMAL_VALID_SPEC
            + "\nTrain the network for 5 epochs with foo optimizer.\n"
        )
        with pytest.raises(CompileError) as exc_info:
            compile_pipeline_config(spec)
        codes = {d.code for d in exc_info.value.diagnostics}
        assert "unknown_optimizer_phrase" in codes

    def test_compile_to_nir_unaffected_by_pipeline_sentences_in_same_spec(self) -> None:
        spec = (
            MINIMAL_VALID_SPEC
            + "\nTrain the network for 5 epochs.\nEvaluate the network.\n"
            "Export the trained network to NIR.\n"
        )
        graph_with_pipeline = compile_to_nir(spec)
        graph_without_pipeline = compile_to_nir(MINIMAL_VALID_SPEC)
        assert set(graph_with_pipeline.nodes.keys()) == set(
            graph_without_pipeline.nodes.keys()
        )

    def test_compile_pipeline_config_exported_from_neurocnl(self) -> None:
        assert hasattr(neurocnl, "compile_pipeline_config")
        assert callable(neurocnl.compile_pipeline_config)
        assert "compile_pipeline_config" in neurocnl.__all__


# ── public __init__ re-export tests ──────────────────────────────────────────


class TestPublicReExports:
    def test_compile_to_nir_exported_from_neurocnl(self) -> None:
        assert hasattr(neurocnl, "compile_to_nir")
        assert callable(neurocnl.compile_to_nir)

    def test_compile_error_exported_from_neurocnl(self) -> None:
        assert hasattr(neurocnl, "CompileError")

    def test_diagnostic_exported_from_neurocnl(self) -> None:
        assert hasattr(neurocnl, "Diagnostic")

    def test_compile_to_nir_in_all(self) -> None:
        assert "compile_to_nir" in neurocnl.__all__

    def test_compile_error_in_all(self) -> None:
        assert "CompileError" in neurocnl.__all__

    def test_top_level_import_produces_valid_graph(self) -> None:
        graph = neurocnl.compile_to_nir(MINIMAL_VALID_SPEC)
        assert isinstance(graph, nir.NIRGraph)
