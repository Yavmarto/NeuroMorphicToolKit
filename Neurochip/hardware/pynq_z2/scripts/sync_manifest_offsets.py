#!/usr/bin/env python3
"""Derive the overlay manifest's register offsets from the built ``.hwh``.

Overlay-v1 shipped a manifest whose register offsets were written by hand and
disagreed with the hardware on every scalar argument — the manifest said
8/12/16/20 where Vitis HLS had actually placed them at 0x10/0x18/0x20/0x28.
Nothing in the build caught it, because nothing compared the two.

This script is that comparison.  ``--write`` fills the manifest in from the
generated hardware handoff; ``--check`` fails if they have drifted apart.  The
build runs ``--write`` immediately after Vivado, and the repository test suite
runs ``--check`` against the staged overlay, so a hand-edited offset cannot
survive to a board.
"""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

#: AXI-Lite control registers every Vitis HLS kernel exposes.
CONTROL_REGISTERS: dict[str, str] = {
    "control_reg_offset": "CTRL",
    "global_interrupt_enable_offset": "GIER",
    "interrupt_enable_offset": "IP_IER",
    "interrupt_status_offset": "IP_ISR",
}

#: Manifest key -> HLS argument name, for the arguments the host must write.
ARGUMENT_REGISTERS: dict[str, str] = {
    "weights_ptr_offset": "weights",
    "layer_config_ptr_offset": "layer_config",
    "layer_count_offset": "layer_count",
    "weight_count_offset": "weight_count",
    "timestep_count_offset": "timestep_count",
}

#: Keys the ``register_map`` carries that are *not* derived from the hardware.
#: They come from the overlay contract
#: (``neurochip/contracts/pynq_runtime_artifact_contract.py``, ``DEFAULT_REGISTER_MAP``)
#: and the launcher validates them
#: (``nmtk/launcher_control/server.py``, ``_validate_pynq_overlay_manifest``).
#:
#: ``--write`` used to assign a freshly built map over the top of the existing
#: one, which deleted these — the v2 overlay shipped with no ``dma_channel``, so
#: every board reported "Overlay Missing" while the bitstream was fine. They are
#: listed here so both the merge and ``--check`` know the offsets are the only
#: part of this object the hardware owns.
CONTRACT_REGISTER_KEYS: tuple[str, ...] = ("dma_channel", "timestep_us")

DEFAULT_INSTANCE = "snn_engine_0"


class ManifestSyncError(RuntimeError):
    """Raised when the manifest and the hardware handoff cannot be reconciled."""


def _register_offsets(hwh_path: Path, instance: str) -> dict[str, int]:
    """Return ``{register_name: byte_offset}`` for one IP instance."""
    root = ET.parse(hwh_path).getroot()

    for module in root.iter("MODULE"):
        if module.get("FULLNAME") != f"/{instance}":
            continue

        offsets: dict[str, int] = {}
        for register in module.iter("REGISTER"):
            name = register.get("NAME")
            if not name:
                continue
            # Only direct PROPERTY children — a REGISTER also contains FIELD
            # elements whose own properties reuse the ADDRESS_OFFSET name.
            for prop in register.findall("PROPERTY"):
                if prop.get("NAME") == "ADDRESS_OFFSET":
                    offsets[name] = int(str(prop.get("VALUE")), 0)
                    break
        return offsets

    raise ManifestSyncError(
        f"{hwh_path} contains no module named '/{instance}'. "
        "The Vivado block design did not instantiate the engine under the "
        "name the manifest expects."
    )


def _base_address(hwh_path: Path, instance: str) -> int:
    root = ET.parse(hwh_path).getroot()
    for memrange in root.iter("MEMRANGE"):
        if memrange.get("INSTANCE") == instance:
            return int(str(memrange.get("BASEVALUE")), 0)
    raise ManifestSyncError(f"{hwh_path} has no address range for '{instance}'.")


def _match_register(offsets: dict[str, int], argument: str) -> int:
    """Find the register Vitis generated for an HLS argument.

    Vitis names scalar arguments after the argument itself, and pointer
    arguments after the port with a suffix (``weights``, ``weights_r``,
    ``weights_1``), so accept those shapes rather than only an exact match.
    """
    if argument in offsets:
        return offsets[argument]

    candidates = sorted(
        name for name in offsets if name == f"{argument}_r" or name.startswith(f"{argument}_")
    )
    if candidates:
        return offsets[candidates[0]]

    raise ManifestSyncError(
        f"The built overlay has no AXI-Lite register for argument "
        f"'{argument}'. Registers present: {', '.join(sorted(offsets)) or 'none'}. "
        "The host cannot drive an argument the hardware does not expose — this "
        "is the overlay-v1 failure mode, so the build stops here."
    )


def build_register_map(hwh_path: Path, instance: str) -> dict[str, object]:
    """Build the manifest's ``register_map`` from a hardware handoff."""
    offsets = _register_offsets(hwh_path, instance)

    register_map: dict[str, object] = {
        "base_address": _base_address(hwh_path, instance),
        "resolved_from_hwh": True,
    }
    for manifest_key, register_name in CONTROL_REGISTERS.items():
        if register_name not in offsets:
            raise ManifestSyncError(
                f"The built overlay has no '{register_name}' register. Every "
                "Vitis HLS kernel with an s_axilite control bundle exposes one."
            )
        register_map[manifest_key] = offsets[register_name]

    for manifest_key, argument in ARGUMENT_REGISTERS.items():
        register_map[manifest_key] = _match_register(offsets, argument)

    return register_map


def _load_manifest(path: Path) -> dict[str, Any]:
    try:
        result: dict[str, Any] = json.loads(path.read_text())
        return result
    except FileNotFoundError as exc:
        raise ManifestSyncError(f"Manifest not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ManifestSyncError(f"Manifest is not valid JSON: {path}: {exc}") from exc


def write_manifest(manifest_path: Path, hwh_path: Path, instance: str) -> dict[str, Any]:
    manifest = _load_manifest(manifest_path)

    # Merge, never replace. The hardware owns the offsets and the base address;
    # everything else in register_map belongs to the overlay contract and must
    # survive a rebuild. See CONTRACT_REGISTER_KEYS.
    existing = manifest.get("register_map")
    merged: dict[str, object] = dict(existing) if isinstance(existing, dict) else {}
    merged.update(build_register_map(hwh_path, instance))

    manifest["register_map"] = merged
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    return merged


def check_manifest(manifest_path: Path, hwh_path: Path, instance: str) -> list[str]:
    """Return a list of human-readable mismatches; empty means they agree."""
    manifest = _load_manifest(manifest_path)
    expected = build_register_map(hwh_path, instance)
    actual = manifest.get("register_map")

    if not isinstance(actual, dict):
        return ["The manifest has no register_map object."]

    if not actual.get("resolved_from_hwh"):
        return [
            "The manifest's register_map was never resolved from a built "
            "overlay. Run this script with --write after the Vivado build; "
            "hand-written offsets are how overlay-v1 shipped a register map "
            "that pointed at nothing."
        ]

    problems: list[str] = []
    for key, expected_value in expected.items():
        if key == "resolved_from_hwh":
            continue
        actual_value = actual.get(key)
        if actual_value != expected_value:
            problems.append(
                f"{key}: manifest says {actual_value!r}, hardware says {expected_value!r}"
            )

    # A rebuild that drops a contract key leaves offsets that agree with the
    # hardware and a manifest the launcher still refuses, which reads to the
    # user as "Overlay Missing" on a board carrying a perfectly good bitstream.
    for key in CONTRACT_REGISTER_KEYS:
        if key not in actual:
            problems.append(
                f"{key}: missing from register_map. It is part of the overlay "
                "contract, not something --write derives from the .hwh, so a "
                "rebuild must preserve it."
            )
    return problems


def main(argv: list[str] | None = None) -> int:
    here = Path(__file__).resolve().parent
    root = here.parent

    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--write",
        action="store_true",
        help="Rewrite the manifest's register_map from the hardware handoff.",
    )
    mode.add_argument(
        "--check",
        action="store_true",
        help="Fail if the manifest and the hardware handoff disagree.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=root / "overlay_manifest.json",
        help="Path to overlay_manifest.json.",
    )
    parser.add_argument(
        "--hwh",
        type=Path,
        default=root / "build" / "out" / "snn_overlay.hwh",
        help="Path to the generated snn_overlay.hwh.",
    )
    parser.add_argument(
        "--instance",
        default=DEFAULT_INSTANCE,
        help=f"Block-design instance name of the engine (default: {DEFAULT_INSTANCE}).",
    )
    args = parser.parse_args(argv)

    try:
        if args.write:
            register_map = write_manifest(args.manifest, args.hwh, args.instance)
            print(f"[pynq_z2] register map written to {args.manifest}")
            for key, value in register_map.items():
                if isinstance(value, int):
                    print(f"  {key}: {value} (0x{value:X})")
            return 0

        problems = check_manifest(args.manifest, args.hwh, args.instance)
    except ManifestSyncError as exc:
        print(f"[pynq_z2] {exc}", file=sys.stderr)
        return 2

    if problems:
        print(
            "[pynq_z2] the manifest does not match the built overlay:",
            file=sys.stderr,
        )
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    print("[pynq_z2] manifest register map matches the built overlay")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
