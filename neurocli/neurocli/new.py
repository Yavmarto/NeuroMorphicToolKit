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

import sys
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
) -> None:
    """Scaffold a new neuromorphic project from a template bundle.
    Supported training workflows: --trainer <framework> --data <type>
    Legacy combos: nir+snntorch, nir+lava_sim, neurocnl+pynq, akida+brainchip, neurocnl+neurosim, etc.
    """
    bundle: str | None = None
    if trainer:
        # New training workflow
        if trainer.lower() == "snntorch":
            bundle = "nir_snntorch"
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
    variables = {"project_name": name, "task": task, "data_type": data or "static"}
    assert bundle is not None
    render_template(bundle, variables, dest)

    if json_mode:
        print_result({"status": "created", "path": str(dest), "bundle": bundle}, json_mode)
    else:
        print(f"✓ Created '{name}' using {bundle} template.")
        print(f"  cd {dest}")
        print("  uv sync")
        print("  bash scripts/run.sh")
    sys.exit(0)
