"""Install smoke tests.

These tests build a wheel from the current source and install it into a
temporary venv, then verify that imports and entry points work correctly.
They are intentionally slow and are skipped unless the environment variable
NEUROCNL_RUN_INSTALL_SMOKE=1 is set.

Run manually:
    NEUROCNL_RUN_INSTALL_SMOKE=1 pytest tests/test_install_smoke.py -v

Excluded extras (not tested here):
  - spinnaker2: git URL dep requires network access to a private GitLab repo
  - synsense/rockpool/lava: torch is ~1 GB; gate test in core_venv is sufficient
"""

import os
import subprocess
import sys
import tempfile
from collections.abc import Generator
from pathlib import Path

import pytest

if os.getenv("NEUROCNL_RUN_INSTALL_SMOKE") != "1":
    pytest.skip(
        "Set NEUROCNL_RUN_INSTALL_SMOKE=1 to run install smoke tests.",
        allow_module_level=True,
    )

# Root of the neurocnl sub-project (the directory containing pyproject.toml).
PROJECT_ROOT = Path(__file__).parent.parent


def _make_venv(tmp_dir: str) -> Path:
    """Create a fresh venv and return its Python executable path."""
    venv_dir = Path(tmp_dir) / "venv"
    subprocess.run(
        [sys.executable, "-m", "venv", str(venv_dir)],
        check=True,
        capture_output=True,
    )
    if sys.platform == "win32":
        return venv_dir / "Scripts" / "python.exe"
    return venv_dir / "bin" / "python"


def _pip(python: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(python), "-m", "pip", *args],
        capture_output=True,
        text=True,
    )


def _python(python: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(python), *args],
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Core install smoke  (pip install .)
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def core_venv() -> Generator[Path, None, None]:
    """A venv with only `pip install .` (no extras)."""
    kwargs: dict[str, bool] = {}
    if sys.version_info >= (3, 12):
        kwargs["ignore_cleanup_errors"] = True  # avoids Windows file-lock issues
    with tempfile.TemporaryDirectory(prefix="neurocnl-smoke-core-", **kwargs) as tmp:
        python = _make_venv(tmp)
        result = _pip(python, "install", "--quiet", str(PROJECT_ROOT))
        assert result.returncode == 0, f"pip install . failed:\n{result.stdout}\n{result.stderr}"
        yield python


def test_core_import(core_venv):
    """import neurocnl works after pip install ."""
    result = _python(core_venv, "-c", "import neurocnl")
    assert result.returncode == 0, result.stderr


def test_core_version_accessible(core_venv):
    """neurocnl.__version__ is '0.6.0' after core install."""
    result = _python(
        core_venv,
        "-c",
        "import neurocnl; assert neurocnl.__version__ == '0.6.0', neurocnl.__version__",
    )
    assert result.returncode == 0, result.stderr


def test_core_public_api(core_venv):
    """Core public API symbols are importable after core install."""
    result = _python(
        core_venv,
        "-c",
        "from neurocnl import parse, validate, compile_to_nir, run_pipeline",
    )
    assert result.returncode == 0, result.stderr


def test_core_entry_point(core_venv):
    """The CLI entry point runs without ImportError or ModuleNotFoundError."""
    result = _python(core_venv, "-m", "neurocnl.simulation.run_simulation", "--help")
    assert "ImportError" not in result.stderr, result.stderr
    assert "ModuleNotFoundError" not in result.stderr, result.stderr


def test_core_viz_absent_is_graceful(core_venv):
    """Without [viz], spike_raster is NOT available on the neurocnl namespace."""
    # __init__.py gates visualization imports inside a try/except; without
    # matplotlib installed, spike_raster must simply be absent — not raise.
    result = _python(
        core_venv,
        "-c",
        "import neurocnl; assert not hasattr(neurocnl, 'spike_raster'), "
        "'spike_raster should not be present without [viz]'",
    )
    assert result.returncode == 0, result.stderr


# ---------------------------------------------------------------------------
# [viz] extra smoke  (pip install ".[viz]")
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def viz_venv() -> Generator[Path, None, None]:
    """A venv with `pip install .[viz]`."""
    kwargs: dict[str, bool] = {}
    if sys.version_info >= (3, 12):
        kwargs["ignore_cleanup_errors"] = True
    with tempfile.TemporaryDirectory(prefix="neurocnl-smoke-viz-", **kwargs) as tmp:
        python = _make_venv(tmp)
        result = _pip(python, "install", "--quiet", f"{PROJECT_ROOT}[viz]")
        assert result.returncode == 0, (
            f"pip install .[viz] failed:\n{result.stdout}\n{result.stderr}"
        )
        yield python


def test_viz_matplotlib_available(viz_venv):
    """After pip install .[viz], matplotlib is importable."""
    result = _python(viz_venv, "-c", "import matplotlib")
    assert result.returncode == 0, result.stderr


def test_viz_spike_raster_importable(viz_venv):
    """After pip install .[viz], neurocnl.visualization.spike_raster is importable."""
    result = _python(viz_venv, "-c", "from neurocnl.visualization import spike_raster")
    assert result.returncode == 0, result.stderr


# ---------------------------------------------------------------------------
# [loihi] extra smoke  (pip install ".[loihi]")
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def loihi_venv() -> Generator[Path, None, None]:
    """A venv with `pip install .[loihi]`."""
    kwargs: dict[str, bool] = {}
    if sys.version_info >= (3, 12):
        kwargs["ignore_cleanup_errors"] = True
    with tempfile.TemporaryDirectory(prefix="neurocnl-smoke-loihi-", **kwargs) as tmp:
        python = _make_venv(tmp)
        result = _pip(python, "install", "--quiet", f"{PROJECT_ROOT}[loihi]")
        assert result.returncode == 0, (
            f"pip install .[loihi] failed:\n{result.stdout}\n{result.stderr}"
        )
        yield python


def test_loihi_nengo_loihi_available(loihi_venv):
    """After pip install .[loihi], nengo_loihi is importable."""
    result = _python(loihi_venv, "-c", "import nengo_loihi")
    assert result.returncode == 0, result.stderr


# ---------------------------------------------------------------------------
# Gate tests (hardware extras absent in core_venv → clean ModuleNotFoundError)
# ---------------------------------------------------------------------------


def test_sinabs_gate_clean(core_venv):
    """Without [synsense], importing sinabs raises ModuleNotFoundError cleanly."""
    result = _python(core_venv, "-c", "import sinabs")
    assert result.returncode != 0, "sinabs should not be importable in core venv"
    assert "ModuleNotFoundError" in result.stderr or "No module named" in result.stderr, (
        f"Expected ModuleNotFoundError for sinabs, got:\n{result.stderr}"
    )
