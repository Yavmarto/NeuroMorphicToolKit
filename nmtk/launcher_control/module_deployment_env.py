"""Module deployment environment helpers (manifest → required vars → .env sync)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def load_module_manifest(repo_root: Path) -> list[dict[str, Any]]:
    path = repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
    if not path.exists():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    if not isinstance(payload, list):
        return []
    return [item for item in payload if isinstance(item, dict)]


def module_env_requirements(
    repo_root: Path,
) -> dict[str, tuple[tuple[str, ...], tuple[str, ...]]]:
    """Return module id → (required_environment, secret_fields)."""
    requirements: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {}
    for module in load_module_manifest(repo_root):
        module_id = str(module.get("id") or "").strip()
        deployment = module.get("deployment")
        if not module_id or not isinstance(deployment, dict):
            continue
        required = tuple(
            str(item).strip()
            for item in deployment.get("requiredEnvironment", [])
            if str(item).strip()
        )
        secrets = tuple(
            str(item).strip()
            for item in deployment.get("secretFields", [])
            if str(item).strip()
        )
        if required or secrets:
            requirements[module_id] = (required, secrets)
    return requirements


def missing_module_environment(
    module_environment: dict[str, str],
    repo_root: Path,
    *,
    module_secret_refs: dict[str, str] | None = None,
) -> list[str]:
    """Plain-English warnings for unset required module env vars."""
    missing: list[str] = []
    secret_refs = module_secret_refs or {}
    for module_id, (required, secrets) in module_env_requirements(repo_root).items():
        for key in (*required, *secrets):
            if str(module_environment.get(key) or "").strip():
                continue
            if str(secret_refs.get(key) or "").strip():
                continue
            missing.append(
                f"degraded optional capability: {module_id} needs {key} "
                "before its integrations can start"
            )
    return missing


def build_dotenv_sync_script(deploy_dir: str, values: dict[str, str]) -> str:
    """Merge ``values`` into ``deploy_dir/.env`` without shell-escaping hazards."""
    if not values:
        return "true"
    payload = json.dumps(values, sort_keys=True)
    return f"""python3 - <<'PY'
import json, pathlib
deploy = pathlib.Path({json.dumps(deploy_dir)})
path = deploy / ".env"
path.parent.mkdir(parents=True, exist_ok=True)
values = json.loads({json.dumps(payload)})
existing = {{}}
if path.exists():
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        existing[key.strip()] = value
existing.update(values)
path.write_text(
    "\\n".join(f"{{key}}={{value}}" for key, value in sorted(existing.items())) + "\\n",
    encoding="utf-8",
)
PY"""
