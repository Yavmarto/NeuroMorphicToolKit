"""Tests for neuro studio run (NeuroStudio workspace-file generate + run)."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import httpx
from typer.testing import CliRunner

from neurocli.cli import app

runner = CliRunner()


def _workspace(tmp_path: Path, *, spec: str = "network kws { }", **overrides) -> Path:
    workspace: dict = {
        "files": [{"id": "f1", "name": "main.cnl", "content": spec}],
        "activeFileId": "f1",
        "workspaceName": "my-project",
        "selectedPlatforms": ["snntorch_sim"],
        "selectedDataset": "mnist",
    }
    workspace.update(overrides)
    path = tmp_path / "session.nmtk"
    path.write_text(json.dumps({"version": 1, "workspace": workspace}))
    return path


def _sse_response(events: list[dict]) -> MagicMock:
    """Build a mock httpx streaming response usable as a context manager."""
    lines = [f"data: {json.dumps(e)}" for e in events]
    resp = MagicMock()
    resp.iter_lines.return_value = lines
    ctx = MagicMock()
    ctx.__enter__.return_value = resp
    ctx.__exit__.return_value = False
    return ctx


def _make_response(payload: dict, status_code: int = 200) -> MagicMock:
    resp = MagicMock()
    resp.status_code = status_code
    resp.json.return_value = payload
    resp.raise_for_status = MagicMock()
    return resp


def test_run_missing_file_exits_1(tmp_path: Path) -> None:
    result = runner.invoke(app, ["studio", "run", str(tmp_path / "nope.json"), "--json"])
    assert result.exit_code == 1
    assert json.loads(result.output)["error"] == "file_not_found"


def test_run_invalid_json_exits_1(tmp_path: Path) -> None:
    bad = tmp_path / "bad.nmtk"
    bad.write_text("not json")
    result = runner.invoke(app, ["studio", "run", str(bad), "--json"])
    assert result.exit_code == 1
    assert json.loads(result.output)["error"] == "invalid_workspace_file"


def test_run_missing_workspace_key_exits_1(tmp_path: Path) -> None:
    bad = tmp_path / "bad.nmtk"
    bad.write_text(json.dumps({"version": 1}))
    result = runner.invoke(app, ["studio", "run", str(bad), "--json"])
    assert result.exit_code == 1
    assert json.loads(result.output)["error"] == "invalid_workspace_file"


def test_run_empty_spec_exits_1(tmp_path: Path) -> None:
    workspace_file = _workspace(tmp_path, spec="")
    result = runner.invoke(app, ["studio", "run", str(workspace_file), "--json"])
    assert result.exit_code == 1
    assert json.loads(result.output)["error"] == "empty_spec"


def test_run_generate_then_run_then_stream_success(tmp_path: Path) -> None:
    workspace_file = _workspace(tmp_path)
    gen_resp = _make_response(
        {"workspace_folder": "my-project/notebooks", "notebooks": [{"filename": "pipeline_snntorch_sim.ipynb"}]}
    )
    run_resp = _make_response({"job_id": "job-1"})
    sse = _sse_response([{"type": "epoch", "epoch": 1, "total_epochs": 2, "loss": 0.5}, {"type": "done"}])
    with (
        patch("neurocli.studio.httpx.post", side_effect=[gen_resp, run_resp]) as mock_post,
        patch("neurocli.studio.httpx.stream", return_value=sse),
    ):
        result = runner.invoke(app, ["studio", "run", str(workspace_file), "-r", "http://x.test", "--json"])
    assert result.exit_code == 0, result.output
    gen_call = mock_post.call_args_list[0]
    assert gen_call.args[0] == "http://x.test/api/notebook/generate-v2"
    assert gen_call.kwargs["json"]["spec"] == "network kws { }"
    assert gen_call.kwargs["json"]["pipeline_config"]["framework"] == "snntorch_sim"
    assert gen_call.kwargs["json"]["pipeline_config"]["dataset"] == "mnist"
    run_call = mock_post.call_args_list[1]
    assert run_call.args[0] == "http://x.test/api/notebook/run"
    assert run_call.kwargs["json"]["notebook_path"] == "my-project/notebooks/pipeline_snntorch_sim.ipynb"
    lines = [line for line in result.output.strip().splitlines()]
    assert json.loads(lines[-1])["status"] == "done"


def test_run_flags_override_workspace_config(tmp_path: Path) -> None:
    workspace_file = _workspace(tmp_path)
    gen_resp = _make_response(
        {"workspace_folder": "wf/notebooks", "notebooks": [{"filename": "pipeline_lava_sim.ipynb"}]}
    )
    run_resp = _make_response({"job_id": "job-2"})
    sse = _sse_response([{"type": "done"}])
    with (
        patch("neurocli.studio.httpx.post", side_effect=[gen_resp, run_resp]) as mock_post,
        patch("neurocli.studio.httpx.stream", return_value=sse),
    ):
        result = runner.invoke(
            app,
            [
                "studio",
                "run",
                str(workspace_file),
                "-r",
                "http://x.test",
                "--framework",
                "lava_sim",
                "--dataset",
                "shd",
                "--epochs",
                "5",
                "--json",
            ],
        )
    assert result.exit_code == 0, result.output
    cfg = mock_post.call_args_list[0].kwargs["json"]["pipeline_config"]
    assert cfg["framework"] == "lava_sim"
    assert cfg["dataset"] == "shd"
    assert cfg["epochs"] == 5


def test_run_generate_compile_error_exits_1(tmp_path: Path) -> None:
    workspace_file = _workspace(tmp_path)
    resp = MagicMock()
    resp.status_code = 422
    resp.json.return_value = {"detail": "unknown node type"}
    resp.raise_for_status.side_effect = httpx.HTTPStatusError("bad", request=MagicMock(), response=resp)
    with patch("neurocli.studio.httpx.post", return_value=resp):
        result = runner.invoke(app, ["studio", "run", str(workspace_file), "-r", "http://x.test", "--json"])
    assert result.exit_code == 1
    body = json.loads(result.output)
    assert body["error"] == "generate_failed"
    assert body["detail"] == "unknown node type"


def test_run_backend_unreachable_exits_2(tmp_path: Path) -> None:
    workspace_file = _workspace(tmp_path)
    with patch("neurocli.studio.httpx.post", side_effect=httpx.ConnectError("refused")):
        result = runner.invoke(app, ["studio", "run", str(workspace_file), "-r", "http://x.test", "--json"])
    assert result.exit_code == 2
    assert json.loads(result.output)["error"] == "backend_unreachable"


def test_run_streamed_failure_exits_2(tmp_path: Path) -> None:
    workspace_file = _workspace(tmp_path)
    gen_resp = _make_response(
        {"workspace_folder": "wf/notebooks", "notebooks": [{"filename": "pipeline_snntorch_sim.ipynb"}]}
    )
    run_resp = _make_response({"job_id": "job-3"})
    sse = _sse_response([{"type": "failed", "error": "kernel died"}])
    with (
        patch("neurocli.studio.httpx.post", side_effect=[gen_resp, run_resp]),
        patch("neurocli.studio.httpx.stream", return_value=sse),
    ):
        result = runner.invoke(app, ["studio", "run", str(workspace_file), "-r", "http://x.test"])
    assert result.exit_code == 2
