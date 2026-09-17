"""neuro new — scaffold a neuromorphic project from a template bundle.

Supported combinations (framework + target → bundle) (legacy):
  nir       + snntorch     → nir_snntorch
  nir       + lava_sim     → nir_lava_sim
  nir       + sc_neurocore → nir_sc_neurocore
  neurocnl  + pynq         → neurocnl_pynq
  akida     + brainchip    → akida_brainchip
  neurocnl  + neurosim     → neurocnl_neurosim

New training workflow:
  trainer (e.g., snntorch) + data (e.g., event) → scaffolds training sandbox
"""

from __future__ import annotations

import re
import shutil
import sys
import tempfile
from pathlib import Path

import typer

from neurocli.output import error_exit, print_result
from neurocli.renderer import render_template

# Combo → bundle name
_COMBOS: dict[tuple[str, str], str] = {
    ("nir", "snntorch"): "nir_snntorch",
    ("nir", "lava_sim"): "nir_lava_sim",
    ("nir", "sc_neurocore"): "nir_sc_neurocore",
    ("neurocnl", "pynq"): "neurocnl_pynq",
    ("akida", "brainchip"): "akida_brainchip",
    ("neurocnl", "neurosim"): "neurocnl_neurosim",
}

_SUPPORTED = [f"{fw}+{tgt}" for fw, tgt in _COMBOS]
_GOLDEN_COMBO = ("nir", "snntorch")
_PROJECT_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
_DATA_TYPES = {"static", "event"}


def new_command(
    name: str = typer.Argument(..., help="Project directory name"),
    trainer: str | None = typer.Option(None, "--trainer", help="Training framework (e.g., snntorch, norse)"),
    data: str | None = typer.Option(None, "--data", help="Dataset type (e.g., event, static)"),
    framework: str | None = typer.Option(None, "--framework", "-f", help="Framework (nir, neurocnl, akida)"),
    target: str | None = typer.Option(  # noqa: E501
        None, "--target", "-t", help="Target (deprecated, use --trainer for training or `neuro deploy` for hardware)"
    ),
    task: str = typer.Option("default", "--task", help="Task label embedded in generated files"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
    output_dir: Path | None = typer.Option(None, "--output-dir", "-o", help="Parent directory (default: cwd)"),
    experimental: bool = typer.Option(
        False,
        "--experimental",
        help="Allow an unverified template bundle. Only NIR+snnTorch is verified in the PoC.",
    ),
) -> None:
    """Scaffold a new neuromorphic project from a template bundle.
    Supported training workflows: --trainer <framework> --data <type>
    Legacy combos: nir+snntorch, nir+lava_sim, neurocnl+pynq, akida+brainchip, neurocnl+neurosim, etc.
    """
    if not _PROJECT_NAME.fullmatch(name):
        error_exit(
            {
                "error": "invalid_project_name",
                "message": "Use letters, numbers, underscores, and hyphens; start with a letter or number.",
            },
            json_mode,
            code=1,
        )

    bundle: str | None = None
    selected_combo: tuple[str, str]
    if trainer:
        # New training workflow
        if trainer.lower() == "snntorch":
            bundle = "nir_snntorch"
            selected_combo = _GOLDEN_COMBO
            if data is not None and data.lower() not in _DATA_TYPES:
                error_exit(
                    {"error": "unsupported_data_type", "data": data, "supported": sorted(_DATA_TYPES)},
                    json_mode,
                    code=1,
                )
        else:
            error_exit({"error": "unsupported_trainer", "trainer": trainer}, json_mode, code=1)
    else:
        # Legacy workflow
        if not framework or not target:
            error_exit(
                {"error": "missing_arguments", "message": "Must provide --trainer or --framework/--target"},
                json_mode,
                code=1,
            )
        assert framework is not None and target is not None
        key = (framework.lower(), target.lower())
        selected_combo = key
        bundle = _COMBOS.get(key)
        if bundle is None:
            error_exit(
                {
                    "error": "unsupported_combination",
                    "framework": framework,
                    "target": target,
                    "supported": _SUPPORTED,
                },
                json_mode,
                code=1,
            )

    if selected_combo != _GOLDEN_COMBO and not experimental:
        error_exit(
            {
                "error": "experimental_template",
                "combination": "+".join(selected_combo),
                "hint": "Re-run with --experimental; only nir+snntorch is verified end to end.",
            },
            json_mode,
            code=1,
        )

    parent = (output_dir or Path.cwd()).resolve()
    dest = parent / name
    if dest.exists():
        error_exit(
            {"error": "destination_exists", "path": str(dest)},
            json_mode,
            code=1,
        )

    parent.mkdir(parents=True, exist_ok=True)
    variables = {"project_name": name, "task": task, "data_type": data or "static"}
    assert bundle is not None
    staging = Path(tempfile.mkdtemp(prefix=f".{name}-", dir=parent))
    try:
        render_template(bundle, variables, staging)
        staging.rename(dest)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise

    if json_mode:
        print_result({"status": "created", "path": str(dest), "bundle": bundle}, json_mode)
    else:
        print(f"✓ Created '{name}' using {bundle} template.")
        print(f"  cd {dest}")
        print("  uv sync")
        print("  uv run python src/train.py")
    sys.exit(0)
