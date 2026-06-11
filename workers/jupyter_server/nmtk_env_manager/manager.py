"""Environment management for the NMTK Jupyter worker.

Implements the lightweight "clone the immutable base, customise the clone"
model described in the Python Environment Editor plan:

* The base kernel (``neurocnl`` / "Python (NeuroStudio)") is baked into the
  container image with ``--sys-prefix`` and is **immutable** — every mutating
  operation that targets it is refused.
* A user environment is a ``venv`` created with ``--system-site-packages`` so it
  inherits the heavy base packages (torch, lava-nc, …) instantly. Only the
  user-added delta lives in the clone's own ``site-packages``.
* Each clone registers a Jupyter kernelspec (via ``ipykernel install --user``)
  so JupyterLab discovers it automatically.

All operations are plain ``subprocess`` calls, mirroring the synchronous
``subprocess.run(..., capture_output=True, text=True)`` style used by
``nmtk/launcher_control/server.py``. Long-running operations are wrapped in
background jobs by the Tornado handlers, not here.
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

# Immutable base kernel — must match the name registered in the Dockerfile.
BASE_KERNEL = "neurocnl"
BASE_DISPLAY_NAME = "Python (NeuroStudio)"

_SLUG_RE = re.compile(r"[^a-z0-9]+")


class EnvironmentError_(Exception):
    """Base class for environment-manager errors (HTTP-mappable)."""

    status_code = 400


class ImmutableEnvironmentError(EnvironmentError_):
    """Raised when a mutating operation targets the immutable base kernel."""

    status_code = 409


class EnvironmentNotFoundError(EnvironmentError_):
    """Raised when an environment slug does not exist."""

    status_code = 404


class CommandError(EnvironmentError_):
    """Raised when an underlying pip/venv/ipykernel command fails."""

    status_code = 500

    def __init__(self, message: str, *, log: str = "") -> None:
        super().__init__(message)
        self.log = log


def slugify(display_name: str) -> str:
    """Derive a filesystem/kernel-safe slug from a human display name."""
    slug = _SLUG_RE.sub("-", display_name.strip().lower()).strip("-")
    return slug or "env"


class EnvironmentManager:
    """Create, inspect, mutate, and share cloned Python environments.

    Args are injectable so the unit tests can point at a temp root and a stub
    Python without touching the real container filesystem.
    """

    def __init__(
        self,
        envs_root: Path | None = None,
        base_python: Path | None = None,
        base_kernel: str = BASE_KERNEL,
    ) -> None:
        self.envs_root = Path(envs_root) if envs_root else (Path.home() / ".nmtk-envs")
        # The extension runs inside the immutable base env, so the interpreter
        # executing it IS the base python.
        self.base_python = Path(base_python) if base_python else Path(sys.executable)
        self.base_kernel = base_kernel

    # ── paths ────────────────────────────────────────────────────────────────
    def _env_dir(self, slug: str) -> Path:
        return self.envs_root / slug

    def _venv_dir(self, slug: str) -> Path:
        return self._env_dir(slug) / "venv"

    def _venv_python(self, slug: str) -> Path:
        venv = self._venv_dir(slug)
        win = venv / "Scripts" / "python.exe"
        return win if win.exists() else venv / "bin" / "python"

    def _meta_path(self, slug: str) -> Path:
        return self._env_dir(slug) / "meta.json"

    # ── command helper ─────────────────────────────────────────────────────--
    @staticmethod
    def _run(cmd: list[str]) -> str:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            raise CommandError(
                f"Command failed: {' '.join(cmd)}",
                log=(result.stdout or "") + (result.stderr or ""),
            )
        return result.stdout or ""

    # ── guards / lookup ───────────────────────────────────────────────────---
    def _ensure_mutable(self, slug: str) -> None:
        if slug == self.base_kernel:
            raise ImmutableEnvironmentError(
                f"'{BASE_DISPLAY_NAME}' is immutable; clone it to add packages."
            )

    def _ensure_exists(self, slug: str) -> None:
        if slug == self.base_kernel:
            return
        if not self._meta_path(slug).exists():
            raise EnvironmentNotFoundError(f"Environment '{slug}' not found.")

    def _python_for(self, slug: str) -> Path:
        return self.base_python if slug == self.base_kernel else self._venv_python(slug)

    # ── queries ────────────────────────────────────────────────────────────--
    def _package_count(self, python: Path) -> int:
        try:
            data = json.loads(self._run([str(python), "-m", "pip", "list", "--format=json"]))
            return len(data)
        except (CommandError, json.JSONDecodeError):
            return 0

    def _base_descriptor(self) -> dict:
        return {
            "slug": self.base_kernel,
            "displayName": BASE_DISPLAY_NAME,
            "kernelName": self.base_kernel,
            "basedOn": None,
            "immutable": True,
            "pythonVersion": self._python_version(self.base_python),
            "createdAt": None,
            "packageCount": self._package_count(self.base_python),
        }

    @staticmethod
    def _python_version(python: Path) -> str:
        try:
            out = subprocess.run(
                [str(python), "-c", "import platform; print(platform.python_version())"],
                capture_output=True,
                text=True,
                check=False,
            )
            return out.stdout.strip() or "unknown"
        except OSError:
            return "unknown"

    def list_environments(self) -> list[dict]:
        envs = [self._base_descriptor()]
        if self.envs_root.exists():
            for env_dir in sorted(self.envs_root.iterdir()):
                meta = env_dir / "meta.json"
                if not meta.exists():
                    continue
                info = json.loads(meta.read_text())
                slug = info["slug"]
                envs.append(
                    {
                        "slug": slug,
                        "displayName": info.get("displayName", slug),
                        "kernelName": slug,
                        "basedOn": info.get("basedOn", self.base_kernel),
                        "immutable": False,
                        "pythonVersion": self._python_version(self._venv_python(slug)),
                        "createdAt": info.get("createdAt"),
                        "packageCount": self._package_count(self._venv_python(slug)),
                    }
                )
        return envs

    def list_packages(self, slug: str) -> list[dict]:
        self._ensure_exists(slug)
        raw = self._run([str(self._python_for(slug)), "-m", "pip", "list", "--format=json"])
        return json.loads(raw)

    # ── unique slug ────────────────────────────────────────────────────────--
    def _unique_slug(self, display_name: str) -> str:
        base = slugify(display_name)
        if base == self.base_kernel:
            base = f"{base}-copy"
        slug = base
        n = 2
        while slug == self.base_kernel or self._env_dir(slug).exists():
            slug = f"{base}-{n}"
            n += 1
        return slug

    # ── mutations ──────────────────────────────────────────────────────────--
    def create_environment(
        self,
        display_name: str,
        based_on: str = BASE_KERNEL,
        *,
        slug: str | None = None,
    ) -> dict:
        """Clone the base env into a new ``--system-site-packages`` venv + kernel.

        Args:
            display_name: Human-readable kernel name shown in JupyterLab.
            based_on: Must be the immutable base kernel (v1 only).
            slug: Optional explicit filesystem/kernel slug. If omitted, derived
                from ``display_name`` via ``_unique_slug()``. Callers that need
                a stable, predictable slug (e.g. provisioning) should supply this.
        """
        display_name = (display_name or "").strip()
        if not display_name:
            raise EnvironmentError_("A display name is required.")
        if based_on != self.base_kernel:
            # v1 only clones the immutable base.
            raise EnvironmentError_(f"Unsupported base environment '{based_on}'.")

        slug = slug if slug is not None else self._unique_slug(display_name)
        # Guard: explicit slug must not be empty or collide with the immutable base.
        if not slug:
            raise EnvironmentError_("Slug must not be empty.")
        if slug == self.base_kernel:
            raise EnvironmentError_(
                f"Slug '{slug}' is reserved for the immutable base kernel."
            )
        venv_dir = self._venv_dir(slug)
        venv_dir.parent.mkdir(parents=True, exist_ok=True)

        # Inherit the immutable base packages instantly — no re-download.
        self._run([str(self.base_python), "-m", "venv", "--system-site-packages", str(venv_dir)])

        # Register the kernelspec with the clone's python so installs land here.
        self._run(
            [
                str(self._venv_python(slug)),
                "-m",
                "ipykernel",
                "install",
                "--user",
                "--name",
                slug,
                "--display-name",
                display_name,
            ]
        )

        self._meta_path(slug).write_text(
            json.dumps(
                {
                    "slug": slug,
                    "displayName": display_name,
                    "basedOn": based_on,
                    "createdAt": datetime.now(timezone.utc).isoformat(),
                }
            )
        )
        return next(e for e in self.list_environments() if e["slug"] == slug)

    def delete_environment(self, slug: str) -> None:
        self._ensure_mutable(slug)
        self._ensure_exists(slug)
        # Remove the kernelspec (best-effort) then the venv tree.
        try:
            self._run([str(self.base_python), "-m", "jupyter", "kernelspec", "remove", "-f", slug])
        except CommandError:
            pass
        shutil.rmtree(self._env_dir(slug), ignore_errors=True)

    def install_packages(self, slug: str, specs: list[str]) -> None:
        self._ensure_mutable(slug)
        self._ensure_exists(slug)
        specs = [s for s in (specs or []) if s.strip()]
        if not specs:
            raise EnvironmentError_("No package specifiers provided.")
        self._run([str(self._venv_python(slug)), "-m", "pip", "install", *specs])

    def uninstall_packages(self, slug: str, names: list[str]) -> None:
        self._ensure_mutable(slug)
        self._ensure_exists(slug)
        names = [n for n in (names or []) if n.strip()]
        if not names:
            raise EnvironmentError_("No package names provided.")
        self._run([str(self._venv_python(slug)), "-m", "pip", "uninstall", "-y", *names])

    # ── share ──────────────────────────────────────────────────────────────--
    @staticmethod
    def _freeze_set(output: str) -> set[str]:
        return {
            line.strip()
            for line in output.splitlines()
            if line.strip() and not line.startswith("#")
        }

    def export_requirements(self, slug: str, mode: str = "delta") -> str:
        """Return a requirements.txt body.

        ``delta`` (default) lists only packages the user added on top of the
        immutable base; ``full`` returns the entire frozen environment.
        """
        self._ensure_exists(slug)
        freeze = self._run([str(self._python_for(slug)), "-m", "pip", "freeze"])
        if mode == "full" or slug == self.base_kernel:
            return freeze
        base_freeze = self._run([str(self.base_python), "-m", "pip", "freeze"])
        delta = self._freeze_set(freeze) - self._freeze_set(base_freeze)
        return "\n".join(sorted(delta)) + ("\n" if delta else "")

    def import_requirements(self, display_name: str, requirements_text: str) -> dict:
        """Create a fresh clone and install the supplied requirements into it."""
        env = self.create_environment(display_name)
        slug = env["slug"]
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as fh:
            fh.write(requirements_text or "")
            req_path = fh.name
        try:
            self._run([str(self._venv_python(slug)), "-m", "pip", "install", "-r", req_path])
        finally:
            Path(req_path).unlink(missing_ok=True)
        return next(e for e in self.list_environments() if e["slug"] == slug)
