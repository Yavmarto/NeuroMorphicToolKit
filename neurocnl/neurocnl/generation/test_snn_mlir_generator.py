import sys
from pathlib import Path
from unittest import mock

import pytest

from neurocnl.compile import compile_to_nir
from neurocnl.generation.snn_mlir_generator import generate_mlir

REFLEX_SPEC = "\n".join(
    [
        "Define an input port named input with shape (2,).",
        "Define a linear transformation named l1 with weight matrix shape (2, 2).",
        "Define an output port named output with shape (2,).",
        "input connects to l1.",
        "l1 connects to output.",
    ]
)


@pytest.fixture
def nir_path(tmp_path: Path) -> Path:
    path = tmp_path / "network.nir"
    compile_to_nir(REFLEX_SPEC, save_to=path)
    return path


def _fake_snn_mlir_module(*, to_mlir_return: str = "module {}\n") -> mock.MagicMock:
    fake = mock.MagicMock()
    fake.to_mlir = mock.Mock(return_value=to_mlir_return)
    return fake


def test_generate_mlir_calls_snn_mlir_with_path_and_quantize(nir_path: Path) -> None:
    fake_module = _fake_snn_mlir_module()
    with mock.patch.dict(sys.modules, {"snn_mlir": fake_module}):
        result = generate_mlir(nir_path, quantize=True)

    fake_module.to_mlir.assert_called_once_with(str(nir_path), quantize=True)
    assert result == "module {}\n"


def test_generate_mlir_defaults_to_float(nir_path: Path) -> None:
    fake_module = _fake_snn_mlir_module()
    with mock.patch.dict(sys.modules, {"snn_mlir": fake_module}):
        generate_mlir(nir_path)

    fake_module.to_mlir.assert_called_once_with(str(nir_path), quantize=False)


def test_generate_mlir_missing_package_raises_runtime_error(nir_path: Path) -> None:
    with (
        mock.patch.dict(sys.modules, {"snn_mlir": None}),
        pytest.raises(RuntimeError, match="snn-mlir.*required"),
    ):
        generate_mlir(nir_path)


def test_generate_mlir_wraps_lowering_failure(nir_path: Path) -> None:
    fake_module = mock.MagicMock()
    fake_module.to_mlir = mock.Mock(
        side_effect=ValueError("recurrent connection found")
    )
    with (
        mock.patch.dict(sys.modules, {"snn_mlir": fake_module}),
        pytest.raises(RuntimeError, match="failed to lower NIR graph"),
    ):
        generate_mlir(nir_path)
