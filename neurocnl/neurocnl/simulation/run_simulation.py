"""End-to-End Simulation Runner.

Executes the full pipeline from CNL spec to Nengo simulation
and produces a validation report.

Usage:
    neurocnl reflex_arc.cnl
    neurocnl reflex_arc.cnl --backend loihi --verbose
"""

import json
import logging
import os
import sys
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

# Ensure neurocnl root is on sys.path when this script is run directly.
# Avoid adding subdirectories directly to sys.path to prevent import conflicts
# and redundant module loading.
_neurocnl_root = Path(__file__).resolve().parent.parent.parent
if str(_neurocnl_root) not in sys.path:
    sys.path.insert(0, str(_neurocnl_root))
else:
    # If already in sys.path, move to front to ensure local version is used
    sys.path.remove(str(_neurocnl_root))
    sys.path.insert(0, str(_neurocnl_root))

import numpy as np

from neurocnl.pipeline import run_pipeline as core_run_pipeline
from neurocnl.runtime_dependencies import ensure_runtime_dependency


def run_pipeline(spec_path: str, backend: str = "nengo") -> dict[str, Any]:
    """Execute the full simulation pipeline.

    Parameters
    ----------
    spec_path : str
        Path to a .cnl spec file.
    backend : str
        Simulation backend: "nengo" (default) or "loihi" (NengoLoihi emulator).

    Returns
    -------
    dict
        Simulation report.
    """
    with open(spec_path) as f:
        spec_text = f.read()

    result = core_run_pipeline(spec_text, backend=backend)

    report = {
        "spec_file": spec_path,
        "backend": backend,
        "layer1_validation": result.validation.get("layer1", {}).get("raw"),
        "layer2_validation": result.validation.get("layer2", {}).get("raw"),
        "simulation_duration": result.simulation.get("wall_time_seconds", 0.0),
        "mujoco_steps": 0,
        "assertions_passed": result.assertions.get("passed", 0),
        "assertions_failed": result.assertions.get("failed", 0),
        "overall_pass": result.overall_pass,
    }

    if result.errors:
        report["error"] = "; ".join(result.errors)
        return report

    # Extract motor output for MuJoCo
    motor_output = np.array(result.simulation.get("motor_output", []))

    # Step 6-7: MuJoCo integration
    # Use direct MuJoCo API since gymnasium may not be installed
    mujoco_steps = 0
    try:
        ensure_runtime_dependency("mujoco")
        import mujoco

        # Create a simple inverted pendulum model
        xml = """
        <mujoco>
          <worldbody>
            <body name="cart" pos="0 0 0">
              <joint name="slide" type="slide" axis="1 0 0"/>
              <geom type="box" size="0.2 0.1 0.05" mass="1"/>
              <body name="pole" pos="0 0 0.6">
                <joint name="hinge" type="hinge" axis="0 1 0"/>
                <geom type="capsule" fromto="0 0 0 0 0 0.6" size="0.02" mass="0.1"/>
              </body>
            </body>
          </worldbody>
          <actuator>
            <motor joint="slide" gear="100"/>
          </actuator>
        </mujoco>
        """
        model = mujoco.MjModel.from_xml_string(xml)
        data = mujoco.MjData(model)

        # Run 200 steps using motor output as control signal
        for step_i in range(200):
            # Map simulation output to action
            t_idx = min(step_i, len(motor_output) - 1)
            action = float(np.clip(motor_output[t_idx, 0], -1.0, 1.0))
            data.ctrl[0] = action
            mujoco.mj_step(model, data)
            mujoco_steps += 1

            # Check termination (pole angle)
            pole_angle = data.qpos[1] if len(data.qpos) > 1 else 0.0
            if abs(pole_angle) > 0.2:
                break

    except Exception as e:
        # MuJoCo is optional; record what we got
        report["mujoco_note"] = f"MuJoCo integration: {e}"

    report["mujoco_steps"] = mujoco_steps

    return report


def _format_report_table(report: dict[str, Any]) -> str:
    """Format a validation report as a human-readable table."""
    lines = []
    spec = report.get("spec_file", "?")
    backend = report.get("backend", "nengo")
    lines.append(f"\n{'─' * 60}")
    lines.append(f"  Spec: {spec}  |  Backend: {backend}")
    lines.append(f"{'─' * 60}")

    # Layer 1
    l1 = report.get("layer1_validation")
    if l1:
        n_pass = len(l1.get("passed", []))
        n_fail = len(l1.get("failed", []))
        status = "\033[32m✓\033[0m" if l1.get("overall") else "\033[31m✗\033[0m"
        lines.append(f"  Layer 1 {status}  {n_pass} passed, {n_fail} failed")
        for name in l1.get("passed", []):
            lines.append(f"    \033[32m✓\033[0m {name}")
        for f in l1.get("failed", []):
            lines.append(f"    \033[31m✗\033[0m {f['name']}: {f['reason']}")

    # Layer 2
    l2 = report.get("layer2_validation")
    if l2:
        n_pass = len(l2.get("checks_passed", []))
        n_fail = len(l2.get("checks_failed", []))
        status = "\033[32m✓\033[0m" if l2.get("overall") else "\033[31m✗\033[0m"
        lines.append(f"  Layer 2 {status}  {n_pass} passed, {n_fail} failed")
        for name in l2.get("checks_passed", []):
            lines.append(f"    \033[32m✓\033[0m {name}")
        for f in l2.get("checks_failed", []):
            lines.append(f"    \033[31m✗\033[0m {f['check']}: {f['detail']}")

    # Simulation
    dur = report.get("simulation_duration", 0)
    if dur > 0:
        lines.append(f"  Simulation  {dur:.3f}s")

    # Assertions
    a_pass = report.get("assertions_passed", 0)
    a_fail = report.get("assertions_failed", 0)
    if a_pass or a_fail:
        status = "\033[32m✓\033[0m" if a_fail == 0 else "\033[31m✗\033[0m"
        lines.append(f"  Assertions {status}  {a_pass} passed, {a_fail} failed")

    # Overall
    overall = report.get("overall_pass", False)
    if overall:
        lines.append("\n  \033[32m✓ OVERALL PASS\033[0m")
    else:
        error = report.get("error", "")
        lines.append(
            "\n  \033[31m✗ OVERALL FAIL\033[0m" + (f" — {error}" if error else "")
        )

    lines.append(f"{'─' * 60}\n")
    return "\n".join(lines)


def _validate_batch(spec_paths: list[str], backend: str = "nengo") -> int:
    """Validate multiple specs and print summary table.

    Returns exit code: 0 if all pass, 1 if any fail.
    """
    results: list[dict[str, Any]] = []
    for path in spec_paths:
        with open(path) as f:
            spec_text = f.read()

        result = core_run_pipeline(spec_text, backend=backend, skip_simulation=True)
        l1 = result.validation.get("layer1", {}).get(
            "raw", {"passed": [], "failed": []}
        )
        l2 = result.validation.get("layer2", {}).get(
            "raw", {"checks_passed": [], "checks_failed": []}
        )

        results.append(
            {
                "spec": path,
                "sentences": len(result.parsed),
                "l1_pass": len(l1["passed"]),
                "l1_fail": len(l1["failed"]),
                "l2_pass": len(l2["checks_passed"]),
                "l2_fail": len(l2["checks_failed"]),
                "overall": result.overall_pass,
                "error": "; ".join(result.errors) if result.errors else None,
            }
        )

    # Print summary table
    logger.info("\n%s", "─" * 78)
    logger.info("  %-35s %9s %5s %5s %8s", "Spec", "Sentences", "L1", "L2", "Result")
    logger.info("%s", "─" * 78)
    all_pass = True
    for r in results:
        status = "\033[32mPASS\033[0m" if r["overall"] else "\033[31mFAIL\033[0m"
        if not r["overall"]:
            all_pass = False
        l1_str = f"{r['l1_pass']}/{r['l1_pass'] + r['l1_fail']}"
        l2_str = f"{r['l2_pass']}/{r['l2_pass'] + r['l2_fail']}"
        name = os.path.basename(r["spec"])
        logger.info(
            "  %-35s %9s %5s %5s   %s", name, r["sentences"], l1_str, l2_str, status
        )
        if r["error"]:
            logger.info("    \033[31m%s\033[0m", r["error"])
    logger.info("%s", "─" * 78)
    total = len(results)
    passed = sum(1 for r in results if r["overall"])
    logger.info("  %d/%d specs passed\n", passed, total)

    return 0 if all_pass else 1


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(
        description="neurocnl — CNL simulation pipeline for neuromorphic computing.",
        usage="%(prog)s [options] spec_file\n       %(prog)s --validate spec1.cnl spec2.cnl ...",
    )
    parser.add_argument(
        "spec_files",
        nargs="+",
        help="One or more .cnl spec files.",
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate specs only (Layer 1 + Layer 2, no simulation).",
    )
    parser.add_argument(
        "--backend",
        choices=["nengo", "loihi"],
        default="nengo",
        help="Simulation backend (default: nengo). 'loihi' uses NengoLoihi emulator.",
    )
    parser.add_argument(
        "--format",
        choices=["json", "table"],
        default="json",
        help="Output format (default: json).",
    )
    verbosity = parser.add_mutually_exclusive_group()
    verbosity.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable verbose output (DEBUG level logging).",
    )
    verbosity.add_argument(
        "--quiet",
        "-q",
        action="store_true",
        help="Suppress informational output (WARNING level only).",
    )

    args = parser.parse_args()

    # Configure logging based on verbosity flags
    if args.verbose:
        level = logging.DEBUG
    elif args.quiet:
        level = logging.WARNING
    else:
        level = logging.INFO
    logging.basicConfig(level=level, format="%(message)s")

    # Batch validate mode
    if args.validate_only:
        exit_code = _validate_batch(args.spec_files, backend=args.backend)
        sys.exit(exit_code)

    # Single spec: run full simulation pipeline
    spec_file = args.spec_files[0]
    if len(args.spec_files) > 1:
        logger.warning(
            "Multiple spec files given without --validate-only; using first: %s",
            spec_file,
        )

    report = run_pipeline(spec_file, backend=args.backend)

    # Write report
    report_path = "simulation_report.json"
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2)

    logger.info("Report written to %s", report_path)

    if args.format == "table":
        logger.info("%s", _format_report_table(report))
    else:
        logger.info("%s", json.dumps(report, indent=2))

    if report["overall_pass"]:
        logger.info("\n✓ OVERALL PASS — report written to %s", report_path)
        sys.exit(0)
    else:
        logger.info("\n✗ OVERALL FAIL — report written to %s", report_path)
        sys.exit(1)


if __name__ == "__main__":
    main()
