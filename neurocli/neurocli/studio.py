"""neuro studio run — generate a notebook from a NeuroStudio workspace file and run it.

Drives the same two `neurocnl` backend endpoints the NeuroStudio GUI calls when a
user clicks "Generate" on the Pipeline tab:

  1. ``POST /api/notebook/generate-v2`` — compiles the CNL spec and writes a notebook
  2. ``POST /api/notebook/run``          — executes it via ``jupyter nbconvert``

then streams live progress from ``GET /api/training/jobs/{job_id}/events`` (SSE)
until the run reaches a terminal ``done``/``failed`` state.

The workspace file (``*.nmtk``) does not carry training/pipeline
parameters (epochs, learning rate, ...) — those only exist as ephemeral in-app state
in the GUI. The ``--epochs``/``--learning-rate``/etc. flags below default to the same
values the GUI's ``PipelineConfig`` defaults to, so an unmodified workspace file
behaves the same from the CLI as it would freshly opened in the GUI.

Exit codes: 0 = run completed, 1 = user/input error (bad file, compile error),
2 = runtime/infrastructure error (backend unreachable, run failed).
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import httpx
import typer

from neurocli.manifest import ManifestNotFoundError, find_module, load_manifest
from neurocli.output import error_exit, print_result

studio_app = typer.Typer(help="NeuroStudio (neurocnl): generate and run notebooks from a workspace file.")

_REPO_ROOT = Path(__file__).parent.parent.parent  # neurocli/ -> repo root
_FALLBACK_BASE_URL = "http://127.0.0.1:9000"


def _resolve_base_url(flag: str | None) -> str:
    """Resolve the neurocnl backend base URL: flag > NMTK_ROOT manifest > fallback."""
    if flag:
        return flag.rstrip("/")
    configured = os.environ.get("NMTK_SUITE_API_URL")
    if configured:
        return configured.rstrip("/")
    try:
        modules = load_manifest(Path(os.environ.get("NMTK_ROOT", _REPO_ROOT)))
    except (ManifestNotFoundError, OSError, json.JSONDecodeError):
        return _FALLBACK_BASE_URL
    entry = find_module(modules, "neurocnl")
    if entry is not None and entry.port is not None:
        return f"http://localhost:{entry.port}"
    return _FALLBACK_BASE_URL


def _load_workspace(workspace_file: Path) -> dict[str, Any]:
    raw = json.loads(workspace_file.read_text())
    if not isinstance(raw, dict) or "workspace" not in raw:
        raise ValueError("Workspace file must contain a top-level 'workspace' object.")
    return raw["workspace"]


def _active_spec(workspace: dict[str, Any]) -> str:
    files = workspace.get("files", [])
    active_id = workspace.get("activeFileId")
    active_file = next((f for f in files if f.get("id") == active_id), None) or (files[0] if files else None)
    if active_file is None:
        return ""
    canonical = (active_file.get("canonicalDocument") or {}).get("cnlText", "")
    return canonical if canonical.strip() else active_file.get("content", "")


def _post(url: str, base_url: str, json_mode: bool, error_msg: str, **kwargs: Any) -> httpx.Response:
    try:
        resp = httpx.post(url, **kwargs)
        resp.raise_for_status()
        return resp
    except httpx.ConnectError:
        error_exit({"error": "backend_unreachable", "base_url": base_url}, json_mode, code=2)
        raise  # unreachable, error_exit exits
    except httpx.HTTPStatusError as exc:
        detail = _safe_detail(exc.response)
        code = 2 if exc.response.status_code >= 500 else 1
        error_exit(
            {"error": error_msg, "status_code": exc.response.status_code, "detail": detail}, json_mode, code=code
        )
        raise


def _safe_detail(response: httpx.Response) -> str:
    try:
        return str(response.json().get("detail", response.text))
    except (json.JSONDecodeError, ValueError):
        return response.text


@studio_app.command("run")
def run(
    workspace_file: Path = typer.Argument(..., help="Path to a *.nmtk file"),
    epochs: int = typer.Option(50, "--epochs", help="Training epochs"),
    learning_rate: float = typer.Option(1e-3, "--learning-rate", help="Optimizer learning rate"),
    optimizer: str = typer.Option("Adam", "--optimizer", help="Optimizer algorithm"),
    batch_size: int = typer.Option(32, "--batch-size", help="Mini-batch size"),
    framework: str | None = typer.Option(None, "--framework", help="Overrides the workspace file's selectedPlatforms"),
    dataset: str | None = typer.Option(None, "--dataset", help="Overrides the workspace file's selectedDataset"),
    registry: str | None = typer.Option(
        None,
        "--api-url",
        "--registry",
        "-r",
        help="Suite API base URL (`--registry` is retained for compatibility)",
    ),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Generate a Jupyter notebook from a workspace file's CNL spec and run it."""
    if not workspace_file.exists():
        error_exit({"error": "file_not_found", "path": str(workspace_file)}, json_mode, code=1)

    try:
        workspace = _load_workspace(workspace_file)
    except (json.JSONDecodeError, ValueError) as exc:
        error_exit({"error": "invalid_workspace_file", "detail": str(exc)}, json_mode, code=1)
        return

    spec = _active_spec(workspace)
    if not spec.strip():
        error_exit({"error": "empty_spec", "hint": "The workspace's active file has no CNL spec."}, json_mode, code=1)
        return

    resolved_framework = framework or (workspace.get("selectedPlatforms") or [None])[0] or "snntorch_sim"
    resolved_dataset = dataset if dataset is not None else workspace.get("selectedDataset")
    workspace_path = workspace.get("workspaceName", "") or ""

    base_url = _resolve_base_url(registry)
    pipeline_config: dict[str, Any] = {
        "epochs": epochs,
        "learning_rate": learning_rate,
        "optimizer": optimizer,
        "batch_size": batch_size,
        "framework": resolved_framework,
    }
    if resolved_dataset:
        pipeline_config["dataset"] = resolved_dataset

    gen_resp = _post(
        f"{base_url}/api/notebook/generate-v2",
        base_url,
        json_mode,
        "generate_failed",
        json={"spec": spec, "pipeline_config": pipeline_config, "workspace_path": workspace_path},
        timeout=60.0,
    )
    gen_data = gen_resp.json()
    notebooks = gen_data.get("notebooks") or []
    if not notebooks:
        error_exit({"error": "no_notebook_generated"}, json_mode, code=2)
        return
    notebook_path = f"{gen_data['workspace_folder']}/{notebooks[0]['filename']}"

    run_resp = _post(
        f"{base_url}/api/notebook/run",
        base_url,
        json_mode,
        "run_failed",
        json={"notebook_path": notebook_path, "platform": resolved_framework, "kernel_name": "python3"},
        timeout=30.0,
    )
    job_id = run_resp.json()["job_id"]

    exit_code = _stream_progress(base_url, job_id, json_mode)
    if exit_code != 0:
        raise typer.Exit(code=exit_code)
    result = {"status": "done", "notebook_path": notebook_path, "job_id": job_id}
    if json_mode:
        # Compact single-line JSON (not print_result's indented form) so --json output
        # stays one-JSON-object-per-line, matching the SSE events streamed above it.
        print(json.dumps(result))
    else:
        print_result(result, json_mode)


def _stream_progress(base_url: str, job_id: str, json_mode: bool) -> int:
    """Stream SSE progress for *job_id* until a terminal event; return its exit code."""
    url = f"{base_url}/api/training/jobs/{job_id}/events"
    try:
        with httpx.stream("GET", url, timeout=None) as response:
            response.raise_for_status()
            for line in response.iter_lines():
                if not line.startswith("data: "):
                    continue
                event = json.loads(line[len("data: ") :])
                if json_mode:
                    print(json.dumps(event))
                else:
                    _print_human_event(event)
                if event.get("type") == "done":
                    return 0
                if event.get("type") == "failed":
                    return 2
    except httpx.ConnectError:
        error_exit({"error": "backend_unreachable", "base_url": base_url}, json_mode, code=2)
    except httpx.HTTPStatusError as exc:
        error_exit(
            {
                "error": "progress_stream_failed",
                "status_code": exc.response.status_code,
                "detail": _safe_detail(exc.response),
            },
            json_mode,
            code=2,
        )
    return 2


def _print_human_event(event: dict[str, Any]) -> None:
    if event.get("type") == "epoch":
        total = event.get("total_epochs")
        suffix = f"/{total}" if total else ""
        acc = event.get("accuracy")
        acc_str = f", accuracy={acc:.4f}" if acc is not None else ""
        print(f"  epoch {event.get('epoch')}{suffix}: loss={event.get('loss'):.4f}{acc_str}")
    elif event.get("type") == "failed":
        print(f"  failed: {event.get('error', 'unknown error')}")
    elif event.get("type") == "done":
        print("  done.")
