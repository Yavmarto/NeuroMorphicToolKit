"""Tests for neuro hub commands (Neurohub Global Registry CLI)."""

from __future__ import annotations

import hashlib
import json
import stat
from pathlib import Path
from unittest.mock import MagicMock, patch

import httpx
from typer.testing import CliRunner

from neurocli.cli import app

runner = CliRunner()


def _make_response(payload: dict | bytes, status_code: int = 200) -> MagicMock:
    """Build a mock httpx.Response with json() or content and raise_for_status()."""
    resp = MagicMock()
    resp.status_code = status_code
    if isinstance(payload, bytes):
        resp.content = payload
    else:
        resp.json.return_value = payload
    resp.raise_for_status = MagicMock()
    return resp


def _write_creds(path: Path, token: str = "tok123") -> None:
    """Write a credentials file with a token."""
    path.write_text(json.dumps({"registry": "http://x.test", "token": token}))


# ---------------------------------------------------------------------------
# login
# ---------------------------------------------------------------------------


def test_hub_login_with_token_writes_config(tmp_path: Path) -> None:
    config_path = tmp_path / "hub.json"
    with patch("neurocli.hub._CONFIG_PATH", config_path):
        result = runner.invoke(app, ["hub", "login", "--registry", "http://example.com", "--token", "tok123"])
    assert result.exit_code == 0, result.output
    data = json.loads(config_path.read_text())
    assert data == {"registry": "http://example.com", "token": "tok123"}


def test_hub_login_stores_600_permissions(tmp_path: Path) -> None:
    config_path = tmp_path / "hub.json"
    with patch("neurocli.hub._CONFIG_PATH", config_path):
        runner.invoke(app, ["hub", "login", "--registry", "http://x.com", "--token", "t"])
    assert config_path.stat().st_mode & 0o777 == stat.S_IRUSR | stat.S_IWUSR


def test_hub_login_reads_token_from_environment(tmp_path: Path) -> None:
    config_path = tmp_path / "hub.json"
    with (
        patch("neurocli.hub._CONFIG_PATH", config_path),
        patch.dict("os.environ", {"NEUROHUB_TOKEN": "env-token"}),
    ):
        result = runner.invoke(app, ["hub", "login", "--registry", "http://example.com", "--json"])
    assert result.exit_code == 0, result.output
    assert json.loads(config_path.read_text())["token"] == "env-token"


def test_hub_login_username_password_obtains_jwt(tmp_path: Path) -> None:
    config_path = tmp_path / "hub.json"
    resp = _make_response({"access_token": "jwt-abc", "refresh_token": "r", "token_type": "bearer"})
    with (
        patch("neurocli.hub._CONFIG_PATH", config_path),
        patch("neurocli.hub.httpx.post", return_value=resp) as mock_post,
    ):
        result = runner.invoke(
            app,
            ["hub", "login", "-r", "http://x.test", "-u", "yoshi", "--password", "pw", "--json"],
        )
    assert result.exit_code == 0, result.output
    assert mock_post.call_args.args[0] == "http://x.test/api/v1/auth/login"
    assert json.loads(config_path.read_text())["token"] == "jwt-abc"


def test_hub_login_json_mode_no_username_exits_1(tmp_path: Path) -> None:
    with patch("neurocli.hub._CONFIG_PATH", tmp_path / "hub.json"):
        result = runner.invoke(app, ["hub", "login", "-r", "http://x.test", "--json"])
    assert result.exit_code == 1
    assert json.loads(result.output)["error"] == "missing_username"


# ---------------------------------------------------------------------------
# push
# ---------------------------------------------------------------------------


def test_hub_push_no_credentials_exits_1(tmp_path: Path) -> None:
    fake_file = tmp_path / "model.nir"
    fake_file.write_bytes(b"fake nir data")
    with patch("neurocli.hub._CONFIG_PATH", tmp_path / "no_hub.json"):
        result = runner.invoke(
            app,
            ["hub", "push", str(fake_file), "-t", "snn_model", "-s", "lif", "-v", "1.0.0", "--json"],
        )
    assert result.exit_code == 1
    assert json.loads(result.output)["error"] == "not_logged_in"


def test_hub_push_missing_file_exits_1(tmp_path: Path) -> None:
    result = runner.invoke(
        app,
        ["hub", "push", str(tmp_path / "nope.nir"), "-t", "snn_model", "-s", "lif", "-v", "1.0.0", "--json"],
    )
    assert result.exit_code == 1
    assert json.loads(result.output)["error"] == "file_not_found"


def test_hub_push_invalid_type_exits_1(tmp_path: Path) -> None:
    fake_file = tmp_path / "model.nir"
    fake_file.write_bytes(b"data")
    _write_creds(tmp_path / "hub.json")
    with patch("neurocli.hub._CONFIG_PATH", tmp_path / "hub.json"):
        result = runner.invoke(
            app,
            ["hub", "push", str(fake_file), "-t", "bogus", "-s", "lif", "-v", "1.0.0", "--json"],
        )
    assert result.exit_code == 1
    assert json.loads(result.output)["error"] == "invalid_type"


def test_hub_push_success_prints_uri(tmp_path: Path) -> None:
    fake_file = tmp_path / "model.nir"
    fake_file.write_bytes(b"data")
    config = tmp_path / "hub.json"
    _write_creds(config)
    uri = "neurohub://snn_model/yoshi/lif@1.0.0"
    resp = _make_response({"neurohub_uri": uri}, status_code=201)
    with (
        patch("neurocli.hub._CONFIG_PATH", config),
        patch("neurocli.hub.httpx.post", return_value=resp) as mock_post,
    ):
        result = runner.invoke(
            app,
            [
                "hub",
                "push",
                str(fake_file),
                "-r",
                "http://x.test",
                "-t",
                "snn_model",
                "-s",
                "lif",
                "-v",
                "1.0.0",
                "--tag",
                "a",
                "--tag",
                "b",
                "--json",
            ],
        )
    assert result.exit_code == 0, result.output
    body = json.loads(result.output)
    assert body["status"] == "pushed"
    assert body["uri"] == uri
    assert mock_post.call_args.args[0] == "http://x.test/api/v1/artefacts"


# ---------------------------------------------------------------------------
# pull
# ---------------------------------------------------------------------------


def test_hub_pull_invalid_uri_exits_1() -> None:
    result = runner.invoke(app, ["hub", "pull", "https://wrong.com/model", "--json"])
    assert result.exit_code == 1
    assert json.loads(result.output)["error"] == "invalid_uri"


def test_hub_pull_success_verifies_checksum(tmp_path: Path) -> None:
    blob = b"the-weights"
    sha = hashlib.sha256(blob).hexdigest()
    meta = _make_response(
        {
            "sha256": sha,
            "version": "1.0.0",
            "download_url": "/api/v1/artefacts/yoshi/lif/1.0.0/download",
        }
    )
    blob_resp = _make_response(blob)
    out = tmp_path / "out.nir"
    with (
        patch("neurocli.hub._CONFIG_PATH", tmp_path / "hub.json"),
        patch("neurocli.hub.httpx.get", side_effect=[meta, blob_resp]),
    ):
        result = runner.invoke(
            app,
            ["hub", "pull", "neurohub://snn_model/yoshi/lif@1.0.0", "-r", "http://x.test", "-o", str(out), "--json"],
        )
    assert result.exit_code == 0, result.output
    assert out.read_bytes() == blob
    assert json.loads(result.output)["sha256"] == sha


def test_hub_pull_checksum_mismatch_exits_2(tmp_path: Path) -> None:
    blob = b"the-weights"
    meta = _make_response(
        {
            "sha256": "deadbeef" * 8,  # wrong digest
            "version": "1.0.0",
            "download_url": "/api/v1/artefacts/yoshi/lif/1.0.0/download",
        }
    )
    blob_resp = _make_response(blob)
    out = tmp_path / "out.nir"
    with (
        patch("neurocli.hub._CONFIG_PATH", tmp_path / "hub.json"),
        patch("neurocli.hub.httpx.get", side_effect=[meta, blob_resp]),
    ):
        result = runner.invoke(
            app,
            ["hub", "pull", "neurohub://snn_model/yoshi/lif@1.0.0", "-r", "http://x.test", "-o", str(out)],
        )
    assert result.exit_code == 2
    assert not out.exists()


def test_hub_pull_without_checksum_exits_2_without_download(tmp_path: Path) -> None:
    meta = _make_response({"version": "1.0.0", "download_url": "/api/v1/artefacts/yoshi/lif/1.0.0/download"})
    out = tmp_path / "out.nir"
    with (
        patch("neurocli.hub._CONFIG_PATH", tmp_path / "hub.json"),
        patch("neurocli.hub.httpx.get", return_value=meta) as get,
    ):
        result = runner.invoke(
            app,
            [
                "hub",
                "pull",
                "neurohub://snn_model/yoshi/lif@1.0.0",
                "-r",
                "http://x.test",
                "-o",
                str(out),
                "--json",
            ],
        )
    assert result.exit_code == 2
    assert json.loads(result.output)["error"] == "missing_checksum"
    assert get.call_count == 1
    assert not out.exists()


# ---------------------------------------------------------------------------
# search
# ---------------------------------------------------------------------------


def test_hub_search_json_shape() -> None:
    resp = _make_response(
        {"items": [{"slug": "lif", "type": "snn_model", "owner": "y", "version": "1.0.0"}], "search_degraded": False}
    )
    with patch("neurocli.hub.httpx.get", return_value=resp):
        result = runner.invoke(app, ["hub", "search", "lif", "--json"])
    assert result.exit_code == 0
    data = json.loads(result.output)
    assert isinstance(data["items"], list)
    assert data["items"][0]["slug"] == "lif"


def test_hub_search_registry_unreachable() -> None:
    with patch("neurocli.hub.httpx.get", side_effect=httpx.ConnectError("refused")):
        result = runner.invoke(app, ["hub", "search", "lif", "--json"])
    assert result.exit_code == 2
    assert json.loads(result.output)["error"] == "registry_unreachable"
