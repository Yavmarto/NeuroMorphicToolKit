"""Tests for truthful offline PYNQ packaging."""

from __future__ import annotations

import json
import zipfile
from pathlib import Path
from unittest.mock import MagicMock, patch

from typer.testing import CliRunner

from neurocli.cli import app

runner = CliRunner()


def _response(payload: dict | bytes) -> MagicMock:
    response = MagicMock()
    response.status_code = 200
    response.raise_for_status.return_value = None
    if isinstance(payload, bytes):
        response.content = payload
    else:
        response.json.return_value = payload
    return response


def _inputs(tmp_path: Path) -> tuple[Path, Path, Path]:
    spec = tmp_path / "network.cnl"
    model = tmp_path / "trained.nir"
    output = tmp_path / "pynq.zip"
    spec.write_text("Define a network named demo.")
    model.write_bytes(b"nir")
    return spec, model, output


def test_deploy_packages_validated_artifact_without_programming_hardware(tmp_path: Path) -> None:
    spec, model, output = _inputs(tmp_path)
    verdict = _response(
        {
            "support_state": "exportable",
            "warnings": [],
            "rejections": [],
            "trained_weights": {"applied": True},
            "deploy_payload": {"num_neurons": 2, "num_synapses": 4},
        }
    )
    with patch("neurocli.deploy.httpx.post", return_value=verdict) as post:
        result = runner.invoke(
            app,
            [
                "deploy",
                str(spec),
                "--trained-nir",
                str(model),
                "--hardware",
                "pynq",
                "--output",
                str(output),
                "--api-url",
                "http://suite.test",
                "--json",
            ],
        )
    assert result.exit_code == 0, result.output
    assert output.is_file()
    payload = json.loads(result.output)
    assert payload["status"] == "packaged"
    assert payload["hardware_programmed"] is False
    assert post.call_args.args[0] == "http://suite.test/api/neurocnl/deploy/pynq/network"
    with zipfile.ZipFile(output) as archive:
        assert set(archive.namelist()) == {"manifest.json", "network.cnl", "trained.nir", "deploy_request.json"}
        assert json.loads(archive.read("manifest.json"))["package_kind"] == "validated_offline_handoff"


def test_deploy_rejects_unsupported_hardware(tmp_path: Path) -> None:
    spec, model, output = _inputs(tmp_path)
    result = runner.invoke(
        app,
        [
            "deploy",
            str(spec),
            "--trained-nir",
            str(model),
            "--hardware",
            "akida",
            "--output",
            str(output),
            "--json",
        ],
    )
    assert result.exit_code == 1
    assert json.loads(result.output)["error"] == "unsupported_hardware"


def test_deploy_rejects_unapplied_weights(tmp_path: Path) -> None:
    spec, model, output = _inputs(tmp_path)
    verdict = _response(
        {
            "support_state": "exportable",
            "trained_weights": {"applied": False},
            "deploy_payload": {"num_neurons": 2},
        }
    )
    with patch("neurocli.deploy.httpx.post", return_value=verdict):
        result = runner.invoke(
            app,
            ["deploy", str(spec), "--trained-nir", str(model), "--output", str(output), "--json"],
        )
    assert result.exit_code == 1
    assert json.loads(result.output)["error"] == "trained_weights_not_applied"
    assert not output.exists()


def test_deploy_rejects_invalid_backend_zip(tmp_path: Path) -> None:
    spec, model, output = _inputs(tmp_path)
    verdict = _response(
        {
            "support_state": "exportable",
            "trained_weights": {"applied": True},
            "deploy_payload": {"num_neurons": 2},
        }
    )

    def write_bad_archive(destination: Path, **_: object) -> None:
        destination.write_bytes(b"not a zip")

    with (
        patch("neurocli.deploy.httpx.post", return_value=verdict),
        patch("neurocli.deploy._write_handoff_archive", side_effect=write_bad_archive),
    ):
        result = runner.invoke(
            app,
            ["deploy", str(spec), "--trained-nir", str(model), "--output", str(output), "--json"],
        )
    assert result.exit_code == 2
    assert json.loads(result.output)["error"] == "invalid_package"
    assert not output.exists()
