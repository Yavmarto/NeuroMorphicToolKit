#!/usr/bin/env python3
"""Prove the Akida runtime package manifest can actually be installed.

`akidaRuntime.requiredPackages` in modules.json is baked into every backend
release image and handed to `pip install` on the end user's paired Akida host.
Nothing else in the suite resolves it: the launcher tests only assert that the
literal strings round-trip through the bundle builder, so a mutually
incompatible pin set ships green and then fails on every user's host at once,
with no in-app way out — the only fix is a new backend release.

That is not hypothetical. `quantizeml==0.19.0` was correct when it was written
and rotted when `cnn2snn` 2.19 moved to `quantizeml~=1.2.2`; every Akida update
then died with `ResolutionImpossible` at the dependency step.

This script resolves the manifest the way the host will: `pip install
--dry-run` on linux, once per Python minor the manifest claims to support,
inside the matching `python:<minor>-slim` image. It downloads nothing and
installs nothing — it only asks pip whether a consistent set exists.

Usage:
    python3 scripts/verify_akida_package_manifest.py
    python3 scripts/verify_akida_package_manifest.py --python 3.12
    python3 scripts/verify_akida_package_manifest.py --module Neurochip

Exits non-zero if any supported interpreter cannot resolve the set.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from nmtk.launcher_control.module_environment import (  # noqa: E402
    _version_matches_range,
)

MODULES_JSON = REPO_ROOT / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
JUPYTER_REQUIREMENTS = REPO_ROOT / "workers" / "jupyter_server" / "requirements.txt"

# Packages that must name the SAME version in modules.json (what the paired
# Akida host installs) and in the jupyter-server image (what writes the bundle).
# A `.fbz` is a version-gated flatbuffer, so a skew between writer and reader
# makes `akida.Model(path)` refuse a bundle that validated cleanly, and the
# resulting error names no version. Drift here is silent until a user's card
# rejects their model, which is exactly the failure mode this file exists for.
WRITER_READER_LOCKSTEP = ("akida", "cnn2snn")

# Every CPython minor a paired host could plausibly run. Filtered against each
# manifest's own pythonRange, so widening this list only adds coverage once a
# manifest opts in.
CANDIDATE_PYTHONS = ("3.10", "3.11", "3.12", "3.13")

# Resolution pulls a lot of metadata (tensorflow, akida, the whole MetaTF
# tree). Generous, but bounded so a wedged runner fails loudly.
RESOLVE_TIMEOUT_SECONDS = 900


def _akida_manifests(module_filter: str) -> list[tuple[str, dict[str, Any]]]:
    """Return (module id, akidaRuntime) for each module declaring a manifest."""
    document = json.loads(MODULES_JSON.read_text(encoding="utf-8"))
    # modules.json is a bare list today; tolerate the wrapped forms so a future
    # schema change surfaces as a resolve failure rather than a traceback.
    if isinstance(document, dict):
        document = document.get("modules", [])
    modules = list(document.values()) if isinstance(document, dict) else document
    found: list[tuple[str, dict[str, Any]]] = []
    for module in modules:
        if not isinstance(module, dict):
            continue
        runtime = module.get("akidaRuntime")
        if not isinstance(runtime, dict) or not runtime.get("requiredPackages"):
            continue
        module_id = str(module.get("id") or module.get("name") or "?")
        if module_filter and module_id != module_filter:
            continue
        found.append((module_id, runtime))
    return found


def _pinned_versions(requirement_lines: list[str]) -> dict[str, str]:
    """Map package name to its `==` pin, ignoring comments and non-pins."""
    pins: dict[str, str] = {}
    for raw in requirement_lines:
        line = raw.split("#", 1)[0].strip()
        if "==" not in line:
            continue
        # Drop environment markers/extras: "akida==2.19.2; python_version<'3.13'"
        name, _, rest = line.partition("==")
        pins[name.strip().lower()] = rest.split(";", 1)[0].strip()
    return pins


def _lockstep_failures(runtime: dict[str, Any]) -> list[str]:
    """Report any WRITER_READER_LOCKSTEP package whose two pins disagree."""
    if not JUPYTER_REQUIREMENTS.is_file():
        return [f"{JUPYTER_REQUIREMENTS} is missing, so the writer pin is unknown"]
    host_pins = _pinned_versions([str(p) for p in runtime["requiredPackages"]])
    writer_pins = _pinned_versions(
        JUPYTER_REQUIREMENTS.read_text(encoding="utf-8").splitlines()
    )
    failures: list[str] = []
    for package in WRITER_READER_LOCKSTEP:
        host = host_pins.get(package)
        writer = writer_pins.get(package)
        if host is None:
            failures.append(f"{package}: modules.json does not pin it with '=='")
            continue
        if writer is None:
            failures.append(
                f"{package}: {JUPYTER_REQUIREMENTS.name} does not pin it with '==' "
                f"(modules.json pins {host}). An unpinned writer floats forward "
                "and will eventually stop matching the host."
            )
            continue
        if host != writer:
            failures.append(
                f"{package}: host installs {host} but the jupyter-server image "
                f"installs {writer}. A .fbz written by one cannot be reopened by "
                "the other — pin both to the same version."
            )
    return failures


def _supported_pythons(python_range: str) -> list[str]:
    return [
        version
        for version in CANDIDATE_PYTHONS
        if _version_matches_range(version, python_range)
    ]


def _resolve(python_version: str, packages: list[str]) -> tuple[bool, str]:
    """Ask pip whether `packages` has a consistent solution on one interpreter.

    `--dry-run` reports the resolution without installing, and `--quiet` keeps
    the happy path to the single "Would install ..." line.
    """
    command = [
        "docker",
        "run",
        "--rm",
        f"python:{python_version}-slim",
        "pip",
        "install",
        "--dry-run",
        "--quiet",
        "--disable-pip-version-check",
        *packages,
    ]
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=RESOLVE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        return False, f"pip did not finish within {RESOLVE_TIMEOUT_SECONDS}s"
    output = (completed.stdout + completed.stderr).strip()
    if completed.returncode != 0:
        return False, output or f"pip exited {completed.returncode}"
    return True, output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--module",
        default="",
        help="Only check this module id (default: every module with a manifest)",
    )
    parser.add_argument(
        "--python",
        default="",
        help="Only check this Python minor, e.g. 3.12 (default: every supported minor)",
    )
    parser.add_argument(
        "--pins-only",
        action="store_true",
        help=(
            "Only check that the host and jupyter-server pins agree. Needs no "
            "docker and no network, so it is cheap enough for every commit."
        ),
    )
    arguments = parser.parse_args()

    # Writer/reader pin agreement first: it needs neither docker nor network, so
    # it should still run (and still fail) on a machine where resolution can't.
    pin_failures: list[str] = []
    for module_id, runtime in _akida_manifests(arguments.module):
        pin_failures.extend(
            f"{module_id}: {failure}" for failure in _lockstep_failures(runtime)
        )
    print("\n== Writer/reader pin agreement ==")
    if pin_failures:
        for failure in pin_failures:
            print(f"   FAIL  {failure}")
    else:
        names = ", ".join(WRITER_READER_LOCKSTEP)
        print(f"   OK  {names} pinned identically in modules.json and")
        print(f"       {JUPYTER_REQUIREMENTS.relative_to(REPO_ROOT)}")

    if arguments.pins_only:
        return 1 if pin_failures else 0

    # Both of these exit 2, never 1. An unusable docker is an inconclusive run,
    # not evidence against the manifest — reporting it as a resolve failure
    # would be the same false accusation this script exists to prevent.
    if shutil.which("docker") is None:
        print(
            "error: docker is required — the manifest has to resolve the way a "
            "linux host will, not the way this machine would.",
            file=sys.stderr,
        )
        return 2
    daemon = subprocess.run(
        ["docker", "info", "--format", "{{.ServerVersion}}"],
        capture_output=True,
        text=True,
    )
    if daemon.returncode != 0:
        print(
            "error: the docker daemon is not reachable, so the manifest was "
            "never checked. Start docker, or point DOCKER_HOST at a linux "
            "daemon (e.g. DOCKER_HOST=ssh://user@host).\n"
            f"{daemon.stderr.strip()}",
            file=sys.stderr,
        )
        return 2

    manifests = _akida_manifests(arguments.module)
    if not manifests:
        target = arguments.module or "any module"
        print(f"error: no akidaRuntime manifest found for {target}", file=sys.stderr)
        return 2

    failures: list[str] = list(pin_failures)
    for module_id, runtime in manifests:
        packages = [str(item) for item in runtime["requiredPackages"]]
        python_range = str(runtime.get("pythonRange") or ">=3.10,<3.13")
        versions = _supported_pythons(python_range)
        if arguments.python:
            versions = [v for v in versions if v == arguments.python]
            if not versions:
                print(
                    f"error: {module_id} does not support Python "
                    f"{arguments.python} (pythonRange {python_range})",
                    file=sys.stderr,
                )
                return 2
        if not versions:
            failures.append(
                f"{module_id}: pythonRange {python_range} matches no known CPython minor"
            )
            continue

        print(f"\n== {module_id} (pythonRange {python_range}) ==")
        for package in packages:
            print(f"   {package}")
        for version in versions:
            print(f"\n-- resolving on Python {version} --")
            resolved, output = _resolve(version, packages)
            if resolved:
                print(f"   OK  {module_id} resolves on Python {version}")
                continue
            # stdout, not stderr: the two streams interleave unpredictably once
            # a CI log redirects them, and pip's diagnosis is only useful
            # directly under the header naming the interpreter it came from.
            print(output)
            failures.append(f"{module_id} does not resolve on Python {version}")

    print("\n== Akida package manifest ==")
    if failures:
        for failure in failures:
            print(f"  FAIL  {failure}")
        print(
            "\nA release carrying this manifest would break the Akida update on "
            "every paired host, and no in-app action can recover it. Correct the "
            "pins in nmtk/neuro_toolkit/assets/modules.json before publishing.",
        )
        return 1
    print("  PASS  every supported interpreter can install the pinned set")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
