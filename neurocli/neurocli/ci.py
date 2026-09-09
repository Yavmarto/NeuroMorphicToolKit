"""``neuro ci ...`` — headless, CI-friendly checks against a live backend.

The golden-path smoke test drives the exact path the launcher app takes when a
workspace runs end to end without the UI: open the authenticated SSH tunnel,
list the installed modules, then hit one representative endpoint on each
backend service the app reaches. ``scripts/dev_update.sh`` calls it after every
successful deploy; failures are reported (never fatal there), because the
deploy itself already succeeded.
"""

from __future__ import annotations

import httpx
import typer

from neurocli.backend import _connect
from neurocli.output import error_exit, print_result

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
