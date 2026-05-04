"""Runtime bootstrap checks for suite_api."""

from __future__ import annotations

from collections.abc import Callable
from importlib.util import find_spec as default_find_spec
from itertools import compress

_REQUIRED_RUNTIME_MODULES: tuple[tuple[str, str], ...] = (
    ("pydantic_settings", "pydantic-settings"),
    ("httpx", "httpx"),
    ("sqlalchemy", "sqlalchemy"),
    ("alembic", "alembic"),
    ("pythonjsonlogger", "python-json-logger"),
)


def missing_runtime_dependencies(
    *,
    find_spec: Callable[[str], object | None] = default_find_spec,
) -> list[str]:
    """Return missing suite_api runtime distributions for the active interpreter."""

    present = [find_spec(module_name) is None for module_name, _ in _REQUIRED_RUNTIME_MODULES]
    return list(compress((dist_name for _, dist_name in _REQUIRED_RUNTIME_MODULES), present))


def validate_runtime_dependencies(
    *,
    find_spec: Callable[[str], object | None] = default_find_spec,
) -> None:
    """Fail early with one actionable error when suite_api deps are absent."""

    missing = missing_runtime_dependencies(find_spec=find_spec)
    if not missing:
        return

    missing_list = ", ".join(missing)
    raise RuntimeError(
        "suite_api cannot start because the active Python environment is missing "
        f"required runtime packages: {missing_list}. "
        "Install suite_api into the active environment first, for example: "
        "python -m pip install -e suite_api/. "
        "If you are following the shared manual setup, install the other root-managed "
        "backend packages into the same venv as documented in SETUP_GUIDE.md."
    )
