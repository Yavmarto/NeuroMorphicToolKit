"""Compiles and runs codegen.py's emitted C to verify it's real, working code.

No real snn_mlir/snn-opt dependency is exercised here (they aren't installed in
this environment) — this only proves the C emitted from fake layer objects is
syntactically valid and produces the expected integrate-and-fire behavior.
"""

import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

from workers.snn_mlir_compiler.codegen import emit_c_artifacts

pytestmark = pytest.mark.skipif(
    subprocess.run(["which", "gcc"], capture_output=True, check=False).returncode != 0,
    reason="gcc not available",
)


def _layer(name: str, size: int, weights: list[list[float]] | None = None, threshold: float = 1.0):
    return SimpleNamespace(name=name, size=size, weights=weights, threshold=threshold)


def _build_and_run(tmp_path: Path, layers: list[object], input_values: list[float], n_steps: int) -> str:
    artifacts = emit_c_artifacts(layers, n_steps=n_steps)
    (tmp_path / "snn_data.h").write_text(artifacts.snn_data_h)
    (tmp_path / "main.c").write_text(artifacts.main_c)

    input_flat = ", ".join(str(v) for v in input_values)
    (tmp_path / "input.h").write_text(
        f"static const float SNN_INPUT[{len(input_values)}] = {{{input_flat}}};\n"
    )

    binary_path = tmp_path / "network_bin"
    compile_proc = subprocess.run(
        ["gcc", "-O2", "-Wall", "-Werror", str(tmp_path / "main.c"), "-I", str(tmp_path), "-o", str(binary_path)],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    assert compile_proc.returncode == 0, compile_proc.stderr

    run_proc = subprocess.run(
        [str(binary_path)],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    assert run_proc.returncode == 0, run_proc.stderr
    return run_proc.stdout


def test_two_layer_network_fires_every_step_when_input_exceeds_threshold(tmp_path):
    layers = [
        _layer("input", 2),
        _layer("output", 1, weights=[[1.0, 1.0]], threshold=1.0),
    ]

    stdout = _build_and_run(tmp_path, layers, input_values=[1.0, 1.0], n_steps=10)

    assert "SNN_OUTPUT_SPIKES=10" in stdout


def test_two_layer_network_never_fires_when_input_is_silent(tmp_path):
    layers = [
        _layer("input", 2),
        _layer("output", 1, weights=[[1.0, 1.0]], threshold=1.0),
    ]

    stdout = _build_and_run(tmp_path, layers, input_values=[0.0, 0.0], n_steps=10)

    assert "SNN_OUTPUT_SPIKES=0" in stdout


def test_three_layer_network_compiles_and_runs(tmp_path):
    layers = [
        _layer("input", 2),
        _layer("hidden", 3, weights=[[1.0, 0.0], [0.0, 1.0], [0.5, 0.5]], threshold=1.0),
        _layer("output", 1, weights=[[1.0, 1.0, 1.0]], threshold=2.0),
    ]

    stdout = _build_and_run(tmp_path, layers, input_values=[1.0, 1.0], n_steps=5)

    assert "SNN_OUTPUT_SPIKES=" in stdout


def test_membrane_potential_accumulates_below_threshold(tmp_path):
    # Weight 0.5 against threshold 1.0 — needs 2 steps of input to fire once.
    layers = [
        _layer("input", 1),
        _layer("output", 1, weights=[[0.5]], threshold=1.0),
    ]

    stdout = _build_and_run(tmp_path, layers, input_values=[1.0], n_steps=4)

    assert "SNN_OUTPUT_SPIKES=2" in stdout
