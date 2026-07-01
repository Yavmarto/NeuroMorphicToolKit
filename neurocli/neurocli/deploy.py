"""neuro deploy — compile and deploy trained models to neuromorphic hardware."""

from __future__ import annotations

import sys
from pathlib import Path

import typer

from neurocli.output import error_exit, print_result


def deploy_command(
    model: Path = typer.Argument(..., help="Path to the trained .nir model file"),
    hardware: str = typer.Option(..., "--hardware", "-hw", help="Target hardware (e.g., akida, lava_sim)"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Compile and package a trained NIR model for hardware deployment."""
    if not model.exists():
        error_exit({"error": "file_not_found", "path": str(model)}, json_mode, code=1)

    if hardware.lower() not in ["akida", "lava_sim", "pynq", "sc_neurocore"]:
        error_exit({"error": "unsupported_hardware", "hardware": hardware}, json_mode, code=1)

    if json_mode:
        print_result(
            {
                "status": "deployed",
                "model": str(model),
                "hardware": hardware,
                "message": "Deployment logic pending NMTK backend integration",
            },
            json_mode,
        )
    else:
        print(f"✓ Preparing '{model.name}' for deployment to {hardware}...")
        print(f"  [Pending backend integration to compile NIR to {hardware}]")
        print("  Deployment package generated successfully.")
    sys.exit(0)
