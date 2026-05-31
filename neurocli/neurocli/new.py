"""neuro new — scaffold a neuromorphic project from a template bundle.

Supported combinations (framework + target → bundle):
  nir       + snntorch     → nir_snntorch
  nir       + lava_sim     → nir_lava_sim
  nir       + sc_neurocore → nir_sc_neurocore
  neurocnl  + pynq         → neurocnl_pynq
  akida     + brainchip    → akida_brainchip
  neurocnl  + neurosim     → neurocnl_neurosim
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Optional

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


def new_command(
    name: str = typer.Argument(..., help="Project directory name"),
    framework: str = typer.Option(..., "--framework", "-f", help="Framework (nir, neurocnl, akida)"),
    target: str = typer.Option(  # noqa: E501
        ..., "--target", "-t", help="Target (snntorch, lava_sim, pynq, brainchip, neurosim)"
    ),
    task: str = typer.Option("default", "--task", help="Task label embedded in generated files"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
    output_dir: Optional[Path] = typer.Option(None, "--output-dir", "-o", help="Parent directory (default: cwd)"),
) -> None:
    """Scaffold a new neuromorphic project from a template bundle.

    Supported framework+target combos:
    nir+snntorch, nir+lava_sim, nir+sc_neurocore, neurocnl+pynq, akida+brainchip, neurocnl+neurosim
    """
    key = (framework.lower(), target.lower())
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

    dest = (output_dir or Path.cwd()) / name
    if dest.exists():
        error_exit(
            {"error": "destination_exists", "path": str(dest)},
            json_mode,
            code=1,
        )

    dest.mkdir(parents=True)
    variables = {"project_name": name, "task": task}
    render_template(bundle, variables, dest)  # type: ignore[arg-type]

    if json_mode:
        print_result({"status": "created", "path": str(dest), "bundle": bundle}, json_mode)
    else:
        print(f"✓ Created '{name}' using {bundle} template.")
        print(f"  cd {dest}")
        print("  uv sync")
        print("  bash scripts/run.sh")
    sys.exit(0)
