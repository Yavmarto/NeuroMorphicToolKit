"""Runtime dependency repair helpers for lightweight self-healing."""

from __future__ import annotations

import importlib
import subprocess
import sys

RUNTIME_PACKAGE_SPECS = {
    "nengo": "nengo>=3.2.0",
    "nengo_loihi": "nengo-loihi",
    "mujoco": "mujoco",
    "neurodreamhand": "neurodreamhand>=0.1.0",
    "neuroml": "libNeuroML",
    "pyneuroml": "pyneuroml",
}


def ensure_runtime_dependency(module_name: str) -> bool:
    """Ensure a known runtime dependency is available."""

    return ensure_python_package(
        module_name,
        RUNTIME_PACKAGE_SPECS.get(module_name, module_name),
    )


def ensure_python_package(module_name: str, package_spec: str | None = None) -> bool:
    """Ensure a Python package is importable in the active interpreter.

    Returns True when the module is importable after the check, including after
    a best-effort `pip install` into the current interpreter environment.
    """

    if _module_available(module_name):
        return True

    package = package_spec or module_name
    result = subprocess.run(
        [sys.executable, "-m", "pip", "install", package],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return False

    importlib.invalidate_caches()
    return _module_available(module_name)


def _module_available(module_name: str) -> bool:
    try:
        importlib.import_module(module_name)
        return True
    except Exception:
        # A native-extension package (mujoco, nengo_loihi, ...) can fail to
        # load with something other than ImportError — e.g. OSError when a
        # shared library it depends on is missing. Either way the package
        # is unusable, which is exactly the "not available" case this probe
        # exists to report; letting it propagate would 500 every caller
        # instead of the 503 they're set up to handle.
        return False
