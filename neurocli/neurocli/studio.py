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
# The consolidated Suite API mounts the neurocnl routers under /api/neurocnl.
# The standalone neurocnl backend served them at /api directly; the CLI follows
# the suite layout because that is what `neuro run` and the launcher deploy.
_NEUROCNL_API_PREFIX = "/api/neurocnl"


def _resolve_base_url(flag: str | None) -> str:
    """Resolve the Suite API base URL: flag > NMTK_ROOT manifest > fallback."""
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


class StudioRunError(RuntimeError):
    """A step of the studio run failed; carries the JSON payload and exit code."""

    def __init__(self, payload: dict[str, Any], code: int) -> None:
        super().__init__(str(payload))
        self.payload = payload
        self.code = code


def _post(url: str, base_url: str, error_msg: str, **kwargs: Any) -> httpx.Response:
    try:
        resp = httpx.post(url, **kwargs)
        resp.raise_for_status()
        return resp
    except httpx.ConnectError as exc:
        raise StudioRunError({"error": "backend_unreachable", "base_url": base_url}, code=2) from exc
    except httpx.HTTPStatusError as exc:
        detail = _safe_detail(exc.response)
        code = 2 if exc.response.status_code >= 500 else 1
        raise StudioRunError(
            {"error": error_msg, "status_code": exc.response.status_code, "detail": detail}, code=code
        ) from exc


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
    try:
        result = run_workspace(
            workspace_file,
            epochs=epochs,
            learning_rate=learning_rate,
            optimizer=optimizer,
            batch_size=batch_size,
            framework=framework,
            dataset=dataset,
            registry=registry,
        )
    except StudioRunError as exc:
        error_exit(exc.payload, json_mode, code=exc.code)
    if json_mode:
        # Compact single-line JSON (not print_result's indented form) so --json output
        # stays one-JSON-object-per-line, matching the SSE events streamed above it.
        print(json.dumps(result))
    else:
        print_result(result, json_mode)


def run_workspace(
    workspace_file: Path,
    *,
    epochs: int = 50,
    learning_rate: float = 1e-3,
    optimizer: str = "Adam",
    batch_size: int = 32,
    framework: str | None = None,
    dataset: str | None = None,
    registry: str | None = None,
    json_mode: bool = False,
    quiet: bool = False,
) -> dict[str, Any]:
    """Generate a notebook from *workspace_file*'s CNL spec and run it to completion.

    Raises :class:`StudioRunError` on any failure (user input, compile error,
    unreachable backend, or a failed notebook run). Returns a result dict with
    ``status``, ``notebook_path`` and ``job_id`` on success. ``json_mode`` is
    forwarded so the streamed progress events stay JSON-per-line; ``quiet``
    suppresses progress output entirely (used by the golden-paths runner).
    """
    workspace, resolved_framework, base_url, pipeline_config = _prepare(
        workspace_file,
        framework,
        dataset,
        registry,
        epochs=epochs,
        learning_rate=learning_rate,
        optimizer=optimizer,
        batch_size=batch_size,
    )
    gen_data = generate_workspace(workspace_file, pipeline_config=pipeline_config, base_url=base_url)
    notebooks = gen_data.get("notebooks") or []
    if not notebooks:
        raise StudioRunError({"error": "no_notebook_generated"}, code=2)
    notebook_path = f"{gen_data['workspace_folder']}/{notebooks[0]['filename']}"

    run_resp = _post(
        f"{base_url}{_NEUROCNL_API_PREFIX}/notebook/run",
        base_url,
        "run_failed",
        json={"notebook_path": notebook_path, "platform": resolved_framework, "kernel_name": "python3"},
        timeout=30.0,
    )
    job_id = run_resp.json()["job_id"]

    exit_code = _stream_progress(base_url, job_id, json_mode, quiet=quiet)
    if exit_code != 0:
        raise StudioRunError({"error": "run_failed", "job_id": job_id}, code=exit_code)
    return {"status": "done", "notebook_path": notebook_path, "job_id": job_id}


def _prepare(
    workspace_file: Path,
    framework: str | None,
    dataset: str | None,
    registry: str | None,
    *,
    epochs: int = 50,
    learning_rate: float = 1e-3,
    optimizer: str = "Adam",
    batch_size: int = 32,
) -> tuple[dict[str, Any], str, str, dict[str, Any]]:
    """Load a workspace file and resolve framework/dataset/base_url/pipeline config.

    Raises :class:`StudioRunError` for unreadable/empty workspace files.
    """
    if not workspace_file.exists():
        raise StudioRunError({"error": "file_not_found", "path": str(workspace_file)}, code=1)

    try:
        workspace = _load_workspace(workspace_file)
    except (json.JSONDecodeError, ValueError) as exc:
        raise StudioRunError({"error": "invalid_workspace_file", "detail": str(exc)}, code=1) from exc

    spec = _active_spec(workspace)
    if not spec.strip():
        raise StudioRunError({"error": "empty_spec", "hint": "The workspace's active file has no CNL spec."}, code=1)

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
    return workspace, resolved_framework, base_url, pipeline_config


def generate_workspace(
    workspace_file: Path,
    *,
    pipeline_config: dict[str, Any] | None = None,
    base_url: str | None = None,
    epochs: int = 50,
    learning_rate: float = 1e-3,
    optimizer: str = "Adam",
    batch_size: int = 32,
    framework: str | None = None,
    dataset: str | None = None,
    registry: str | None = None,
) -> dict[str, Any]:
    """Generate a notebook from *workspace_file*'s CNL spec and return the generate payload.

    The returned dict is the raw ``/notebook/generate-v2`` response body, so callers
    can read the generated notebook's target and support level. Raises
    :class:`StudioRunError` on compile/backend failures. No notebook is run.
    """
    _ws, resolved_framework, resolved_base, resolved_cfg = _prepare(
        workspace_file,
        framework,
        dataset,
        registry,
        epochs=epochs,
        learning_rate=learning_rate,
        optimizer=optimizer,
        batch_size=batch_size,
    )
    if pipeline_config is None:
        pipeline_config = resolved_cfg
    base_url = base_url or resolved_base

    spec = _active_spec(_ws)
    workspace_path = _ws.get("workspaceName", "") or ""
    gen_resp = _post(
        f"{base_url}{_NEUROCNL_API_PREFIX}/notebook/generate-v2",
        base_url,
        "generate_failed",
        json={"spec": spec, "pipeline_config": pipeline_config, "workspace_path": workspace_path},
        timeout=60.0,
    )
    return gen_resp.json()


def _stream_progress(base_url: str, job_id: str, json_mode: bool, quiet: bool = False) -> int:
    """Stream SSE progress for *job_id* until a terminal event; return its exit code."""
    url = f"{base_url}{_NEUROCNL_API_PREFIX}/training/jobs/{job_id}/events"
    try:
        with httpx.stream("GET", url, timeout=None) as response:
            response.raise_for_status()
            for line in response.iter_lines():
                if not line.startswith("data: "):
                    continue
                event = json.loads(line[len("data: ") :])
                if not quiet:
                    if json_mode:
                        print(json.dumps(event))
                    else:
                        _print_human_event(event)
                if event.get("type") == "done":
                    return 0
                if event.get("type") == "failed":
                    return 2
    except httpx.ConnectError as exc:
        raise StudioRunError({"error": "backend_unreachable", "base_url": base_url}, code=2) from exc
    except httpx.HTTPStatusError as exc:
        raise StudioRunError(
            {
                "error": "progress_stream_failed",
                "status_code": exc.response.status_code,
                "detail": _safe_detail(exc.response),
            },
            code=2,
        ) from exc
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
