"""Tests for neuro hub commands."""

from __future__ import annotations

import json
import stat
from pathlib import Path
from unittest.mock import MagicMock, patch

from typer.testing import CliRunner

from neurocli.cli import app

runner = CliRunner()


# ---------------------------------------------------------------------------
# login
# ---------------------------------------------------------------------------


def test_hub_login_writes_config(tmp_path: Path) -> None:
    config_path = tmp_path / "hub.json"
    with patch("neurocli.hub._CONFIG_PATH", config_path):
        result = runner.invoke(
            app,
            ["hub", "login", "--registry", "http://example.com", "--token", "tok123"],
        )
    assert result.exit_code == 0, result.output
    assert config_path.exists()
    data = json.loads(config_path.read_text())
    assert data["registry"] == "http://example.com"
    assert data["token"] == "tok123"


def test_hub_login_stores_600_permissions(tmp_path: Path) -> None:
    config_path = tmp_path / "hub.json"
    with patch("neurocli.hub._CONFIG_PATH", config_path):
        runner.invoke(app, ["hub", "login", "--registry", "http://x.com", "--token", "t"])
    mode = config_path.stat().st_mode & 0o777
    assert mode == stat.S_IRUSR | stat.S_IWUSR


def test_hub_login_json_mode_no_token_exits_1() -> None:
    with patch("neurocli.hub._CONFIG_PATH", Path("/tmp/neurocli_test_noop.json")):
        with patch.dict("os.environ", {"NEUROHUB_TOKEN": ""}, clear=False):
            result = runner.invoke(app, ["hub", "login", "--json"])
    assert result.exit_code == 1
    data = json.loads(result.output)
    assert data["error"] == "missing_token"


# ---------------------------------------------------------------------------
# push
# ---------------------------------------------------------------------------


def test_hub_push_no_credentials_exits_1(tmp_path: Path) -> None:
    fake_file = tmp_path / "model.nir"
    fake_file.write_bytes(b"fake nir data")
    nonexistent_config = tmp_path / "no_hub.json"
    with patch("neurocli.hub._CONFIG_PATH", nonexistent_config):
        result = runner.invoke(app, ["hub", "push", str(fake_file), "--json"])
    assert result.exit_code == 1
    data = json.loads(result.output)
    assert data["error"] == "not_logged_in"


def test_hub_push_missing_file_exits_1(tmp_path: Path) -> None:
    result = runner.invoke(app, ["hub", "push", str(tmp_path / "nonexistent.nir"), "--json"])
    assert result.exit_code == 1
    data = json.loads(result.output)
    assert data["error"] == "file_not_found"


# ---------------------------------------------------------------------------
# pull
# ---------------------------------------------------------------------------


def test_hub_pull_invalid_uri_exits_1() -> None:
    result = runner.invoke(app, ["hub", "pull", "https://wrong.com/model", "--json"])
    assert result.exit_code == 1
    data = json.loads(result.output)
    assert data["error"] == "invalid_uri"


def test_hub_pull_valid_uri_stub() -> None:
    result = runner.invoke(app, ["hub", "pull", "neurohub://my_org/lif_model@1.0", "--json"])
    assert result.exit_code == 0
    data = json.loads(result.output)
    assert data["status"] == "not_implemented"


# ---------------------------------------------------------------------------
# search
# ---------------------------------------------------------------------------


def test_hub_search_json_shape() -> None:
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {"results": [{"id": "model_1", "name": "LIF demo"}]}
    mock_resp.raise_for_status = MagicMock()

    with patch("neurocli.hub.httpx.get", return_value=mock_resp):
        result = runner.invoke(app, ["hub", "search", "lif neuron", "--json"])

    assert result.exit_code == 0
    data = json.loads(result.output)
    assert "results" in data
    assert isinstance(data["results"], list)


def test_hub_search_registry_unreachable() -> None:
    import httpx as _httpx

    with patch("neurocli.hub.httpx.get", side_effect=_httpx.ConnectError("refused")):
        result = runner.invoke(app, ["hub", "search", "lif", "--json"])
    assert result.exit_code != 0
    data = json.loads(result.output)
    assert data["error"] == "registry_unreachable"
