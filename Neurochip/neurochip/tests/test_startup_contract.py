from __future__ import annotations

import os
import subprocess
import sys
import textwrap
from pathlib import Path


def test_app_imports_without_optional_sdks() -> None:
    """neurochip.app.main must import cleanly with optional SDK imports blocked."""
    repo_root = Path(__file__).resolve().parents[2]
    script = textwrap.dedent(
        """
        import importlib.abc
        import importlib.util
        import sys

        BLOCKED = {"numpy", "lava", "pynq", "akida", "sinabs", "samna"}

        class _Blocker(importlib.abc.MetaPathFinder):
            def find_spec(self, fullname, path=None, target=None):
                root = fullname.split(".", 1)[0]
                if root in BLOCKED:
                    raise ImportError(f"blocked optional dependency: {fullname}")
                return None

        _original_find_spec = importlib.util.find_spec

        def _patched_find_spec(name, package=None):
            if name.split(".", 1)[0] in BLOCKED:
                return None
            return _original_find_spec(name, package)

        importlib.util.find_spec = _patched_find_spec
        sys.meta_path.insert(0, _Blocker())
        import neurochip.app.main  # noqa: F401
        print("startup OK")
        """
    )
    nmtk_contracts_root = repo_root.parent / "nmtk_contracts"
    env = os.environ.copy()
    env["PYTHONPATH"] = os.pathsep.join([str(repo_root), str(nmtk_contracts_root)])
    result = subprocess.run(
        [sys.executable, "-c", script],
        capture_output=True,
        text=True,
        cwd=repo_root,
        env=env,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert "startup OK" in result.stdout
