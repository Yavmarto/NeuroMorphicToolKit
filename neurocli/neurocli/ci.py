"""``neuro ci ...`` — headless, CI-friendly checks against a live backend.

The golden-path smoke test drives the exact path the launcher app takes when a
workspace runs end to end without the UI: open the authenticated SSH tunnel,
list the installed modules, then hit one representative endpoint on each
backend service the app reaches. ``scripts/dev_update.sh`` calls it after every
successful deploy; failures are reported (never fatal there), because the
deploy itself already succeeded.

``golden-paths`` goes one level deeper: for each representative
framework+target combo it generates a Studio notebook from a committed
``.nmtk`` workspace and — for the one trainable target (snnTorch) — runs it to
completion. Every combo's generate step must succeed against the live backend
and the trainable combo must finish, otherwise the command exits non-zero.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import httpx
import typer

from neurocli.backend import _connect
from neurocli.output import error_exit, print_result
from neurocli.studio import StudioRunError, generate_workspace, run_workspace

ci_app = typer.Typer(
    name="ci",
    help="Headless checks: verify a live backend works end to end.",
    no_args_is_help=True,
)

# name, method, path, service. One representative call per backend service the
# app reaches over the tunnel (launcher-control, Suite API, Jupyter proxy).
_SMOKE_CHECKS = (
    ("list_modules", "GET", "/api/launcher/modules", "launcher"),
    ("suite_health", "GET", "/api/suite/health", "suite"),
    ("jupyter_health", "GET", "/api/jupyter/health", "suite"),
)


@dataclass(frozen=True)
class GoldenPath:
    """One framework+target combo with its committed workspace and expectations."""

    id: str
    framework: str
    workspace: str
    # Only snnTorch has a Studio training adapter on the live backend; the
    # other targets generate a notebook but cannot train without their SDK.
    expect_trainable: bool = False


# The representative combos CEL-124b covers. Workspaces live next to this file
# under golden_paths/ (package data) so the runner works from any cwd.
_GOLDEN_PATHS = (
    GoldenPath("nir+snntorch", "snntorch_sim", "nir_snntorch.nmtk", expect_trainable=True),
    GoldenPath("nir+lava_sim", "lava_sim", "nir_lava_sim.nmtk"),
    GoldenPath("neurocnl+pynq", "pynq", "neurocnl_pynq.nmtk"),
    GoldenPath("akida+brainchip", "akida", "akida_brainchip.nmtk"),
    GoldenPath("neurocnl+neurosim", "neurosim", "neurocnl_neurosim.nmtk"),
)


def _decode(response: httpx.Response) -> object:
    try:
        return response.json()
    except ValueError:
        return {"body": response.text}


@ci_app.command("smoke-test")
def smoke_test_command(
    target: str = typer.Option(None, "--target", help="Which configured backend to smoke-test."),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Golden-path smoke test: connect, list modules, hit representative endpoints."""
    steps: list[dict[str, object]] = []
    with _connect(target, json_mode) as backend:
        for name, method, path, service in _SMOKE_CHECKS:
            try:
                response = backend.request(method, path, service=service, timeout=30.0)
            except httpx.HTTPError as exc:
                error_exit(
                    {"error": "smoke_test_failed", "step": name, "detail": str(exc)},
                    json_mode,
                    code=2,
                )
            if response.status_code >= 400:
                error_exit(
                    {
                        "error": "smoke_test_failed",
                        "step": name,
                        "status_code": response.status_code,
                        "response": _decode(response),
                    },
                    json_mode,
                    code=2,
                )
            payload = _decode(response)
            if name == "list_modules":
                steps.append(
                    {
                        "name": name,
                        "ok": True,
                        "module_count": len(payload) if isinstance(payload, list) else None,
                    }
                )
            elif name == "suite_health":
                steps.append(
                    {
                        "name": name,
                        "ok": True,
                        "version": payload.get("version") if isinstance(payload, dict) else None,
                    }
                )
            else:
                steps.append({"name": name, "ok": True})
    print_result({"status": "ok", "target": backend.target.id, "steps": steps}, json_mode)


def _golden_paths_dir() -> Path:
    return Path(__file__).parent / "golden_paths"


def _one_golden_path(path: GoldenPath, base_url: str, epochs: int) -> dict[str, object]:
    """Drive one combo: generate, and run to completion when trainable."""
    workspace = _golden_paths_dir() / path.workspace
    result: dict[str, object] = {"id": path.id, "framework": path.framework, "workspace": path.workspace}

    try:
        gen_data = generate_workspace(workspace, framework=path.framework, registry=base_url, epochs=epochs)
    except StudioRunError as exc:
        result["generate"] = {"ok": False, "error": exc.payload}
        result["ok"] = False
        return result
    notebooks = gen_data.get("notebooks") or []
    first = notebooks[0] if notebooks else {}
    result["generate"] = {
        "ok": True,
        "notebook": first.get("filename"),
        "target": first.get("target"),
        "support_level": first.get("support_level"),
        "diagnostics": first.get("diagnostics") or [],
    }

    if not path.expect_trainable:
        result["run"] = {"ok": None, "reason": "no_studio_training_adapter"}
        result["ok"] = True
        return result

    try:
        run_result = run_workspace(workspace, framework=path.framework, registry=base_url, epochs=epochs, quiet=True)
        result["run"] = {"ok": True, **run_result}
        result["ok"] = True
    except StudioRunError as exc:
        result["run"] = {"ok": False, "error": exc.payload}
        result["ok"] = False
    return result


@ci_app.command("golden-paths")
def golden_paths_command(
    target: str = typer.Option(None, "--target", help="Which configured backend to smoke-test."),
    api_url: str = typer.Option(
        None,
        "--api-url",
        "-r",
        help="Suite API base URL (default: http://<target>:9000 or the manifest port).",
    ),
    epochs: int = typer.Option(1, "--epochs", help="Training epochs for the trainable combo"),
    output: Path | None = typer.Option(None, "--output", "-o", help="Write the JSON summary to this file"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Run every golden-path combo back-to-back against a live backend.

    Each combo's Studio notebook must generate successfully; the trainable
    combo (nir+snntorch) must also run to completion. Writes a JSON summary
    (stdout and/or ``--output``) and exits non-zero if any combo failed.
    """
    if api_url is not None:
        base_url = api_url.rstrip("/")
        resolved_target = target
        results = [_one_golden_path(path, base_url, epochs) for path in _GOLDEN_PATHS]
    elif target is not None:
        with _connect(target, json_mode) as backend:
            base_url = backend.urls["suite"]
            resolved_target = backend.target.id
            results = [_one_golden_path(path, base_url, epochs) for path in _GOLDEN_PATHS]
    else:
        from neurocli.studio import _resolve_base_url

        base_url = _resolve_base_url(None)
        resolved_target = None
        results = [_one_golden_path(path, base_url, epochs) for path in _GOLDEN_PATHS]

    failed = [r["id"] for r in results if not r.get("ok")]
    summary: dict[str, object] = {
        "status": "failed" if failed else "ok",
        "target": resolved_target or target or base_url,
        "api_url": base_url,
        "epochs": epochs,
        "golden_paths": results,
        "failed": failed,
    }
    if output is not None:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(summary, indent=2))
    print_result(summary, json_mode)
    if failed:
        raise typer.Exit(code=1)
