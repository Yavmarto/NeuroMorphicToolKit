#!/usr/bin/env python3
"""Fleet health report for the NMTK edge test rigs.

The inventory in ``config/edge_test_rigs.json`` is the single source of truth
for which rigs exist and what each one must expose. This script reads it and
reports, per rig:

* SSH reachability,
* Compose service health,
* expected hardware presence (Akida PCIe, Prophesee USB, PYNQ endpoint),
* which Compose overlay is active.

Rigs whose ``kind`` is ``ci-runner`` are checked against the GitHub Actions
runners API instead of SSH, because they are reached through labels, not a
fixed host login.

Examples:
    python3 scripts/fleet_health.py
    python3 scripts/fleet_health.py --rig moosebun2
    python3 scripts/fleet_health.py --json
    python3 scripts/fleet_health.py --check-doc
    python3 scripts/fleet_health.py --print-target moosebun2

Exit codes:
    0  every checked rig is OK or only optionally degraded
    1  at least one rig is unreachable or has a required failure; or --check-doc
       found inventory drift
    2  usage or inventory error
    3  --strict was set and at least one rig is DEGRADED
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INVENTORY = ROOT / "config" / "edge_test_rigs.json"
DOC_PATH = ROOT / "docs" / "edge-test-rigs.md"

STATUS_OK = "OK"
STATUS_DEGRADED = "DEGRADED"
STATUS_UNHEALTHY = "UNHEALTHY"
STATUS_DOWN = "DOWN"
STATUS_UNKNOWN = "UNKNOWN"

# Runs on the rig via `ssh <target> python3 -`. Prints one JSON object to
# stdout. Standard library only, and every probe is best-effort so a missing
# tool degrades the report instead of failing the whole collection.
REMOTE_PROBE = r"""
import glob
import json
import os
import shutil
import subprocess
import sys


def run(command):
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=20, check=False
        )
    except Exception:
        return ""
    if result.returncode != 0:
        return (result.stdout or result.stderr or "").strip()
    return (result.stdout or "").strip()


def probe_akida_pci(vendor, device):
    probe = {"present": False, "bdf": "", "driver": "", "memorySpaceEnabled": None}
    root = "/sys/bus/pci/devices"
    try:
        entries = sorted(os.listdir(root))
    except OSError:
        return probe
    for name in entries:
        base = os.path.join(root, name)
        try:
            with open(os.path.join(base, "vendor"), encoding="utf-8") as handle:
                found_vendor = handle.read().strip().lower()
            with open(os.path.join(base, "device"), encoding="utf-8") as handle:
                found_device = handle.read().strip().lower()
        except OSError:
            continue
        if found_vendor != vendor or found_device != device:
            continue
        probe["present"] = True
        probe["bdf"] = name
        driver_path = os.path.join(base, "driver")
        if os.path.exists(driver_path):
            probe["driver"] = os.path.basename(os.path.realpath(driver_path))
        try:
            with open(os.path.join(base, "config"), "rb") as handle:
                header = handle.read(6)
            if len(header) >= 6:
                command = int.from_bytes(header[4:6], "little")
                probe["memorySpaceEnabled"] = bool(command & 0x2)
        except OSError:
            pass
        break
    return probe


def collect_containers(engine):
    containers = []
    if not engine:
        return containers
    raw = run([engine, "ps", "--format", "{{json .}}"])
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except ValueError:
            continue
        labels = {}
        for pair in (item.get("Labels") or "").split(","):
            key, sep, value = pair.partition("=")
            if sep:
                labels[key.strip()] = value.strip()
        status = item.get("Status") or ""
        health = "none"
        if "(healthy)" in status:
            health = "healthy"
        elif "(unhealthy)" in status:
            health = "unhealthy"
        elif "(health: starting)" in status:
            health = "starting"
        containers.append(
            {
                "name": item.get("Names") or "",
                "service": labels.get("com.docker.compose.service", ""),
                "project": labels.get("com.docker.compose.project", ""),
                "configFiles": labels.get("com.docker.compose.project.config_files", ""),
                "image": item.get("Image") or "",
                "state": (item.get("State") or "").lower(),
                "status": status,
                "health": health,
            }
        )
    return containers


def main():
    engine = ""
    if shutil.which("docker"):
        engine = "docker"
    elif shutil.which("podman"):
        engine = "podman"

    facts = {
        "hostname": run(["hostname"]) or os.uname().nodename,
        "kernel": run(["uname", "-sr"]),
        "lsusb": run(["lsusb"]),
        "lspci": run(["lspci"]),
        "devNodes": sorted(glob.glob("/dev/akida*")),
        "akidaPci": probe_akida_pci("0x1e7c", "0xbca1"),
        "neurochipService": run(["systemctl", "is-active", "neurochip.service"]),
        "containerEngine": engine,
        "containers": collect_containers(engine),
    }
    json.dump(facts, sys.stdout)
    sys.stdout.write("\n")


main()
"""


def color(text: str, code: str) -> str:
    """Wrap text in an ANSI code when stdout is a terminal."""
    if not sys.stdout.isatty():
        return text
    return f"\033[{code}m{text}\033[0m"


def status_color(status: str) -> str:
    return {
        STATUS_OK: "32",
        STATUS_DEGRADED: "33",
        STATUS_UNHEALTHY: "31",
        STATUS_DOWN: "31",
        STATUS_UNKNOWN: "33",
    }.get(status, "0")


def load_inventory(path: Path) -> dict[str, Any]:
    """Read and minimally validate the rig inventory."""
    if not path.exists():
        raise SystemExit(f"inventory not found: {path}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except ValueError as exc:
        raise SystemExit(f"inventory is not valid JSON: {path}: {exc}")
    if not isinstance(data.get("rigs"), list) or not data["rigs"]:
        raise SystemExit(f"inventory has no rigs: {path}")
    seen: set[str] = set()
    for rig in data["rigs"]:
        rig_id = rig.get("id")
        if not rig_id:
            raise SystemExit(f"inventory rig without an id: {path}")
        if rig_id in seen:
            raise SystemExit(f"inventory has a duplicate rig id: {rig_id}")
        seen.add(rig_id)
    return data


def rig_by_id(inventory: dict[str, Any], rig_id: str) -> dict[str, Any]:
    for rig in inventory["rigs"]:
        if rig.get("id") == rig_id:
            return rig
    raise SystemExit(f"unknown rig: {rig_id}")


def resolve_target(rig: dict[str, Any], inventory: dict[str, Any]) -> str:
    """Return the SSH target for a rig, adding a rig-level user to bare hosts.

    The login name is per rig, never global: the dev host uses ``moosebun2`` but
    a secondary rig may use a different account, so a bare host is left alone
    unless the rig sets ``sshUser``.
    """
    target = rig.get("target")
    if not target:
        return ""
    user = rig.get("sshUser")
    if user and "@" not in target:
        return f"{user}@{target}"
    return target


def run_remote_probe(
    rig: dict[str, Any], inventory: dict[str, Any], ssh_bin: str, timeout: int
) -> tuple[bool, dict[str, Any] | None, str]:
    """Collect facts from a rig over SSH. Returns (reachable, facts, error)."""
    target = resolve_target(rig, inventory)
    if not target:
        return False, None, "no SSH target configured"
    command = [
        ssh_bin,
        "-o",
        "BatchMode=yes",
        "-o",
        f"ConnectTimeout={timeout}",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "ControlMaster=auto",
        "-o",
        "ControlPersist=30s",
        target,
        "python3",
        "-",
    ]
    try:
        result = subprocess.run(
            command,
            input=REMOTE_PROBE,
            capture_output=True,
            text=True,
            timeout=timeout + 30,
            check=False,
        )
    except FileNotFoundError:
        return False, None, f"{ssh_bin} not found"
    except subprocess.TimeoutExpired:
        return False, None, "SSH probe timed out"
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip().splitlines()
        return False, None, detail[-1] if detail else f"ssh exited {result.returncode}"
    try:
        facts = json.loads(result.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return True, None, "host reachable but the probe returned no JSON"
    if not isinstance(facts, dict):
        return True, None, "host reachable but the probe returned unexpected data"
    return True, facts, ""


def tcp_reachable(host: str, port: int, timeout: float = 2.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def check_hardware(item: dict[str, Any], facts: dict[str, Any]) -> tuple[bool, str]:
    """Evaluate one hardware expectation against a rig's collected facts."""
    kind = item.get("kind")
    if kind == "usb":
        vendor = str(item.get("usbVendor", "")).lower()
        lsusb = str(facts.get("lsusb") or "").lower()
        found = any(f"id {vendor}:" in line for line in lsusb.splitlines())
        return found, f"USB device {vendor} {'present' if found else 'not found'}"
    if kind == "pci":
        probe = facts.get("akidaPci") or {}
        if not probe.get("present"):
            return False, "no matching PCI device"
        if not probe.get("driver"):
            return False, f"PCI {probe.get('bdf')} present but no driver bound"
        if probe.get("memorySpaceEnabled") is False:
            return False, f"PCI {probe.get('bdf')} is wedged (memory space disabled)"
        return True, f"PCI {probe.get('bdf')} bound to {probe.get('driver')}"
    if kind == "char_device":
        nodes = facts.get("devNodes") or []
        pattern = item.get("pattern", "/dev/akida*")
        if nodes:
            return True, ", ".join(nodes)
        return False, f"no {pattern} nodes"
    if kind == "systemd":
        unit = str(item.get("unit", ""))
        state = str(facts.get("neurochipService") or "").strip() or "unknown"
        return state == "active", f"{unit} is {state}"
    if kind == "tcp":
        host = str(item.get("host", ""))
        port = int(item.get("port", 0))
        reachable = tcp_reachable(host, port)
        return reachable, f"{host}:{port} {'reachable' if reachable else 'unreachable'}"
    return False, f"unknown hardware check kind: {kind}"


def check_services(
    rig: dict[str, Any], facts: dict[str, Any]
) -> tuple[list[dict[str, Any]], list[str]]:
    """Compare running containers with the rig's expectations."""
    containers = [c for c in (facts.get("containers") or []) if c.get("service")]
    running = {c["service"]: c for c in containers}
    findings: list[dict[str, Any]] = []
    failures: list[str] = []

    expected = list(rig.get("expectedServices") or [])
    optional = list(rig.get("optionalServices") or [])
    for service in expected:
        container = running.get(service)
        if not container:
            findings.append(
                {
                    "service": service,
                    "state": "missing",
                    "detail": "not running",
                    "required": True,
                }
            )
            failures.append(f"{service} is not running")
            continue
        findings.append(_service_finding(container, required=True))
        if (
            container.get("health") == "unhealthy"
            or container.get("state") != "running"
        ):
            failures.append(
                f"{service} is {container.get('state') or 'unknown'} ({container.get('health')})"
            )
    for service in optional:
        container = running.get(service)
        if container:
            findings.append(_service_finding(container, required=False))
        else:
            findings.append(
                {
                    "service": service,
                    "state": "missing",
                    "detail": "not running (optional)",
                    "required": False,
                }
            )

    # A rig with no fixed service list still gets its running containers audited.
    if not expected:
        for container in containers:
            findings.append(_service_finding(container, required=True))
            if container.get("health") == "unhealthy":
                failures.append(f"{container['service']} is unhealthy")

    for service in rig.get("expectedStoppedServices") or []:
        container = running.get(service)
        if container:
            findings.append(
                {
                    "service": service,
                    "state": "running",
                    "detail": "should be stopped on this rig",
                    "required": True,
                }
            )
            failures.append(f"{service} is running but should be stopped")

    for container in containers:
        if container.get("health") == "unhealthy" and not any(
            f.get("service") == container["service"] for f in findings
        ):
            findings.append(_service_finding(container, required=True))
            failures.append(f"{container['service']} is unhealthy")
    return findings, failures


def _service_finding(container: dict[str, Any], required: bool) -> dict[str, Any]:
    state = container.get("state") or "unknown"
    health = container.get("health") or "none"
    detail = health if health != "none" else state
    return {
        "service": container.get("service", ""),
        "state": state,
        "detail": detail,
        "required": required,
    }


def active_overlays(
    rig: dict[str, Any], facts: dict[str, Any], inventory: dict[str, Any]
) -> tuple[set[str], list[str], list[str]]:
    """Return (active, missing-required, active-optional)."""
    overlays = (inventory.get("compose") or {}).get("overlays") or {}
    filenames: set[str] = set()
    for container in facts.get("containers") or []:
        for raw in str(container.get("configFiles") or "").split(","):
            name = os.path.basename(raw.strip())
            if name:
                filenames.add(name)
    active: set[str] = set()
    for key, filename in overlays.items():
        if filename in filenames:
            active.add(key)
    # The akida-native overlay exists to route Akida traffic to the native
    # service; if the unit is active the overlay is required to be applied even
    # when the label has not been read back yet.
    if str(facts.get("neurochipService") or "").strip() == "active":
        active.add("akida-native")
    expected = list(rig.get("expectedOverlays") or [])
    optional = list(rig.get("optionalOverlays") or [])
    missing = [key for key in expected if key not in active]
    active_optional = [key for key in optional if key in active]
    return active, missing, active_optional


def evaluate_rig(
    rig: dict[str, Any], inventory: dict[str, Any], ssh_bin: str, timeout: int
) -> dict[str, Any]:
    report: dict[str, Any] = {
        "id": rig.get("id"),
        "name": rig.get("name"),
        "kind": rig.get("kind", "hardware-rig"),
        "target": resolve_target(rig, inventory),
        "reachable": False,
        "status": STATUS_DOWN,
        "services": [],
        "hardware": [],
        "overlays": {
            "active": [],
            "expected": rig.get("expectedOverlays") or [],
            "missing": [],
            "optional_active": [],
        },
        "failures": [],
        "warnings": [],
        "error": "",
    }
    reachable, facts, error = run_remote_probe(rig, inventory, ssh_bin, timeout)
    report["reachable"] = reachable
    report["error"] = error
    if not reachable:
        report["failures"].append(error or f"cannot reach {report['target']}")
        return report
    if facts is None:
        report["status"] = STATUS_UNHEALTHY
        report["failures"].append(error)
        return report

    report["hostname"] = facts.get("hostname", "")
    report["kernel"] = facts.get("kernel", "")
    report["containerEngine"] = facts.get("containerEngine", "")

    services, service_failures = check_services(rig, facts)
    report["services"] = services
    report["failures"].extend(service_failures)

    active, missing_overlays, active_optional = active_overlays(rig, facts, inventory)
    report["overlays"] = {
        "active": sorted(active),
        "expected": rig.get("expectedOverlays") or [],
        "missing": sorted(missing_overlays),
        "optional_active": sorted(active_optional),
    }
    report["failures"].extend(
        f"overlay {key} is not active" for key in missing_overlays
    )

    optional_missing = False
    for item in rig.get("expectedHardware") or []:
        present, detail = check_hardware(item, facts)
        entry = {
            "id": item.get("id"),
            "description": item.get("description", ""),
            "required": bool(item.get("required")),
            "present": present,
            "detail": detail,
        }
        report["hardware"].append(entry)
        if not present:
            if entry["required"]:
                report["failures"].append(f"{entry['id']} missing: {detail}")
            else:
                optional_missing = True
                report["warnings"].append(
                    f"{entry['id']} not present (optional): {detail}"
                )

    prophesee_present = any(
        item.get("id") == "prophesee-evk" and entry["present"]
        for item, entry in zip(rig.get("expectedHardware") or [], report["hardware"])
    )
    if (
        "prophesee" in (rig.get("optionalOverlays") or [])
        and prophesee_present
        and "prophesee" not in active
    ):
        report["warnings"].append(
            "Prophesee EVK is connected but the prophesee overlay is not active"
        )

    if report["failures"]:
        report["status"] = STATUS_UNHEALTHY
    elif optional_missing:
        report["status"] = STATUS_DEGRADED
    else:
        report["status"] = STATUS_OK
    return report


def gh_runner_status(
    repo: str, labels: list[str], use_gh: bool
) -> tuple[str, list[dict[str, Any]], str]:
    """Return (status, matching runners, error) from the GitHub Actions API."""
    if not labels:
        return STATUS_UNKNOWN, [], "no labels configured"
    if not use_gh or not shutil.which("gh"):
        return STATUS_UNKNOWN, [], "gh CLI unavailable; skipped runner API check"
    command = ["gh", "api", f"/repos/{repo}/actions/runners", "--paginate"]
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=30, check=False
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        return STATUS_UNKNOWN, [], f"runner API check failed: {exc}"
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip().splitlines()
        return STATUS_UNKNOWN, [], detail[-1] if detail else "runner API check failed"
    try:
        payload = json.loads(result.stdout or "{}")
    except ValueError:
        return STATUS_UNKNOWN, [], "runner API returned invalid JSON"
    matches = []
    for runner in payload.get("runners", []):
        names = {label.get("name") for label in runner.get("labels", [])}
        matched = sorted(set(labels) & names)
        if matched:
            matches.append(
                {
                    "name": runner.get("name", ""),
                    "status": runner.get("status", ""),
                    "busy": bool(runner.get("busy")),
                    "labels": matched,
                }
            )
    if not matches:
        return STATUS_DEGRADED, [], f"no registered runner matches {', '.join(labels)}"
    if any(str(m["status"]).lower() == "online" for m in matches):
        return STATUS_OK, matches, ""
    return STATUS_DEGRADED, matches, "matching runner(s) are offline"


def evaluate_runner(
    rig: dict[str, Any], inventory: dict[str, Any], use_gh: bool
) -> dict[str, Any]:
    repo = inventory.get("githubRepo", "")
    labels = list(rig.get("labels") or [])
    status, matches, error = gh_runner_status(repo, labels, use_gh)
    report: dict[str, Any] = {
        "id": rig.get("id"),
        "name": rig.get("name"),
        "kind": "ci-runner",
        "target": rig.get("address") or "",
        "labels": labels,
        "reachable": status != STATUS_DOWN,
        "status": status,
        "services": [],
        "hardware": [],
        "overlays": {
            "active": [],
            "expected": [],
            "missing": [],
            "optional_active": [],
        },
        "runners": matches,
        "failures": [],
        "warnings": [],
        "error": error,
    }
    if status == STATUS_UNKNOWN:
        report["warnings"].append(error)
    elif status != STATUS_OK:
        report["warnings"].append(error)
    return report


def evaluate_all(
    inventory: dict[str, Any],
    ssh_bin: str,
    timeout: int,
    rig_filter: str = "",
    use_gh: bool = True,
) -> list[dict[str, Any]]:
    reports = []
    for rig in inventory["rigs"]:
        if rig_filter and rig.get("id") != rig_filter:
            continue
        if rig.get("kind") == "ci-runner":
            reports.append(evaluate_runner(rig, inventory, use_gh))
        else:
            reports.append(evaluate_rig(rig, inventory, ssh_bin, timeout))
    return reports


def render_report(reports: list[dict[str, Any]]) -> None:
    for report in reports:
        status = report["status"]
        header = f"{report['id']} — {report.get('name', '')}"
        print(f"\n{color(header, '1')}  [{color(status, status_color(status))}]")
        if report.get("hostname"):
            print(f"  host        {report['hostname']} ({report.get('kernel', '')})")
        if report.get("target"):
            print(f"  target      {report['target']}")
        if report.get("labels"):
            print(f"  labels      {', '.join(report['labels'])}")
        if report["kind"] != "ci-runner":
            print(f"  reachable   {'yes' if report['reachable'] else 'no'}")
            overlays = report["overlays"]
            active = ", ".join(overlays["active"]) or "none"
            expected = ", ".join(overlays["expected"]) or "none"
            print(f"  overlays    active: {active} | expected: {expected}")
            if overlays["missing"]:
                print(
                    f"              {color('missing: ' + ', '.join(overlays['missing']), '31')}"
                )

        if report["services"]:
            healthy = sum(
                1
                for s in report["services"]
                if s["state"] == "running"
                and s["detail"] not in ("unhealthy", "starting")
            )
            print(f"  services    {healthy}/{len(report['services'])} healthy")
            for service in report["services"]:
                ok = service["state"] == "running" and service["detail"] not in (
                    "unhealthy",
                    "starting",
                )
                mark = color("[OK]  ", "32") if ok else color("[WARN]", "33")
                tag = "" if service.get("required") else " (optional)"
                print(f"    {mark}  {service['service']:<28} {service['detail']}{tag}")
        elif report["kind"] != "ci-runner":
            print("  services    none expected (auditing running containers only)")

        if report["hardware"]:
            present = sum(1 for h in report["hardware"] if h["present"])
            print(f"  hardware    {present}/{len(report['hardware'])} present")
            for item in report["hardware"]:
                mark = (
                    color("[OK]  ", "32")
                    if item["present"]
                    else color("[MISS]", "33" if not item["required"] else "31")
                )
                tag = "" if item["required"] else " (optional)"
                print(f"    {mark}  {item['id']:<20} {item['detail']}{tag}")

        for runner in report.get("runners", []):
            busy = "busy" if runner["busy"] else "idle"
            print(
                f"    {color('[OK]  ', '32')}  {runner['name']:<28} {runner['status']} ({busy})"
            )

        for failure in report["failures"]:
            print(f"    {color('[FAIL]', '31')}  {failure}")
        for warning in report["warnings"]:
            print(f"    {color('[WARN]', '33')}  {warning}")

    print("\n" + color("Summary", "1"))
    for report in reports:
        status = report["status"]
        print(f"  {report['id']:<18} {color(status, status_color(status))}")


def check_doc(inventory: dict[str, Any]) -> int:
    """Fail when docs/edge-test-rigs.md does not list every inventory rig."""
    if not DOC_PATH.exists():
        print(f"missing documentation: {DOC_PATH}")
        return 1
    text = DOC_PATH.read_text(encoding="utf-8")
    missing = [rig["id"] for rig in inventory["rigs"] if rig["id"] not in text]
    if missing:
        print("docs/edge-test-rigs.md is missing rig ids: " + ", ".join(missing))
        return 1
    print(f"docs/edge-test-rigs.md lists all {len(inventory['rigs'])} rigs.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Fleet health report for the NMTK edge test rigs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--inventory",
        type=Path,
        default=DEFAULT_INVENTORY,
        help="path to the rig inventory JSON",
    )
    parser.add_argument("--rig", default="", help="report only this rig id")
    parser.add_argument("--json", action="store_true", help="print the report as JSON")
    parser.add_argument(
        "--strict", action="store_true", help="exit non-zero on a DEGRADED rig too"
    )
    parser.add_argument(
        "--check-doc",
        action="store_true",
        help="verify docs/edge-test-rigs.md lists every rig",
    )
    parser.add_argument(
        "--print-target",
        default="",
        metavar="RIG",
        help="print the SSH target for one rig and exit",
    )
    parser.add_argument(
        "--list-rigs", action="store_true", help="print rig ids and exit"
    )
    parser.add_argument(
        "--ssh-bin",
        default=os.environ.get("NMTK_SSH_BIN", "ssh"),
        help="ssh binary to use",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=0,
        help="SSH connect timeout in seconds (default: inventory)",
    )
    parser.add_argument(
        "--no-runner-api",
        action="store_true",
        help="skip the GitHub Actions runner API check",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    inventory = load_inventory(args.inventory)

    if args.list_rigs:
        for rig in inventory["rigs"]:
            print(
                f"{rig['id']:<18} {rig['kind']:<13} {resolve_target(rig, inventory) or rig.get('address') or ''}"
            )
        return 0

    if args.print_target:
        rig = rig_by_id(inventory, args.print_target)
        target = resolve_target(rig, inventory)
        if not target:
            print(f"rig {args.print_target} has no SSH target", file=sys.stderr)
            return 3
        print(target)
        return 0

    if args.check_doc:
        return check_doc(inventory)

    if args.rig:
        rig_by_id(inventory, args.rig)

    timeout = args.timeout or int(
        (inventory.get("defaults") or {}).get("sshTimeoutSeconds", 10)
    )
    reports = evaluate_all(
        inventory, args.ssh_bin, timeout, args.rig, not args.no_runner_api
    )

    if args.json:
        print(json.dumps(reports, indent=2, sort_keys=True))
    else:
        render_report(reports)

    fatal = any(
        report["status"] in (STATUS_DOWN, STATUS_UNHEALTHY) for report in reports
    )
    degraded = any(report["status"] == STATUS_DEGRADED for report in reports)
    if fatal:
        return 1
    if args.strict and degraded:
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
