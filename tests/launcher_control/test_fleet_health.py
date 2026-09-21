"""Unit tests for scripts/fleet_health.py.

The SSH transport is replaced with a fake ``ssh`` executable that prints a
canned JSON fact payload, so no real rig is contacted.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "fleet_health.py"

OVERLAY_FILES = (
    "docker-compose.yml,docker-compose.dev.yml,docker-compose.akida-native.yml"
)


def container(service, health="healthy", state="running", config_files=OVERLAY_FILES):
    status = "Up 5 minutes"
    if health != "none":
        status += f" ({health})"
    return {
        "name": f"nmtk-{service}-1",
        "service": service,
        "project": "nmtk",
        "configFiles": config_files,
        "image": f"nmtk/{service}:dev",
        "state": state,
        "status": status,
        "health": health,
    }


def facts(
    containers=None,
    akida_present=True,
    neurochip_service="active",
    lsusb=None,
    akida_driver="akida",
    dkms_status="",
):
    if containers is None:
        containers = [
            container("suite_api"),
            container("launcher-control"),
        ]
    if lsusb is None:
        lsusb = "Bus 001 Device 002: ID 1d43:0001 Prophesee EVK\n"
    return {
        "hostname": "rigtest",
        "kernel": "Linux 6.0.0-test",
        "lsusb": lsusb,
        "lspci": "",
        "devNodes": [],
        "akidaPci": {
            "present": akida_present,
            "bdf": "0000:01:00.0" if akida_present else "",
            "driver": akida_driver if akida_present else "",
            "memorySpaceEnabled": True if akida_present else None,
        },
        "neurochipService": neurochip_service,
        "akidaDriverHelper": "/usr/local/libexec/nmtk-akida-driver-rebuild",
        "dkmsStatus": dkms_status,
        "containerEngine": "docker",
        "containers": containers,
    }


def inventory(include_pynq=False):
    hardware = [
        {
            "id": "akida",
            "kind": "pci",
            "pciVendor": "0x1e7c",
            "pciDevice": "0xbca1",
            "required": True,
            "description": "Akida",
        },
        {
            "id": "akida-service",
            "kind": "systemd",
            "unit": "neurochip.service",
            "required": True,
            "description": "Akida service",
        },
        {
            "id": "prophesee",
            "kind": "usb",
            "usbVendor": "1d43",
            "required": False,
            "description": "Prophesee EVK",
        },
    ]
    if include_pynq:
        hardware.append(
            {
                "id": "pynq",
                "kind": "tcp",
                "host": "127.0.0.1",
                "port": 1,
                "required": False,
                "description": "PYNQ",
            }
        )
    return {
        "version": 1,
        "githubRepo": "example/repo",
        "defaults": {"sshTimeoutSeconds": 2},
        "compose": {
            "base": ["docker-compose.yml", "docker-compose.dev.yml"],
            "overlays": {
                "akida-native": "docker-compose.akida-native.yml",
                "prophesee": "docker-compose.prophesee.yml",
            },
        },
        "rigs": [
            {
                "id": "rigtest",
                "name": "test rig",
                "kind": "hardware-rig",
                "target": "tester@10.0.0.1",
                "expectedOverlays": ["akida-native"],
                "optionalOverlays": ["prophesee"],
                "expectedServices": ["suite_api", "launcher-control"],
                "expectedStoppedServices": ["neurochip-hw-worker"],
                "optionalServices": ["neurosense-hw-worker"],
                "expectedHardware": hardware,
            }
        ],
    }


def write_inventory(tmp_path: Path, data: dict) -> Path:
    path = tmp_path / "inventory.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


def write_fake_ssh(tmp_path: Path, payload: dict | None, exit_code: int = 0) -> Path:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir(exist_ok=True)
    fake = fake_bin / "fake-ssh"
    body = f"#!/bin/sh\nexit {exit_code}\n"
    if payload is not None:
        body = f"#!/bin/sh\ncat >/dev/null\nprintf '%s\\n' '{json.dumps(payload)}'\n"
    fake.write_text(body, encoding="utf-8")
    fake.chmod(0o755)
    return fake


def run_script(
    *flags,
    inventory_path: Path | None = None,
    ssh_bin: Path | None = None,
    args: tuple = (),
):
    command = [sys.executable, str(SCRIPT)]
    if inventory_path is not None:
        command += ["--inventory", str(inventory_path)]
    if ssh_bin is not None:
        command += ["--ssh-bin", str(ssh_bin)]
    command += ["--no-runner-api"]
    command += list(flags)
    command += list(args)
    return subprocess.run(command, capture_output=True, text=True, check=False)


def test_list_rigs_default():
    res = run_script("--list-rigs")
    assert res.returncode == 0
    for rig_id in ("moosebun2", "hp-prodesk", "runner-win-wsl2", "runner-macos"):
        assert rig_id in res.stdout


def test_print_target_resolves_default_rig():
    res = run_script("--print-target", "moosebun2")
    assert res.returncode == 0
    assert res.stdout.strip() == "moosebun2@192.168.2.90"


def test_print_target_unknown_rig_fails():
    res = run_script("--print-target", "nope")
    assert res.returncode != 0


def test_check_doc_lists_every_rig():
    res = run_script("--check-doc")
    assert res.returncode == 0
    assert "all" in res.stdout


def test_check_doc_detects_drift(tmp_path: Path):
    data = inventory()
    data["rigs"][0]["id"] = "rigtest-undocumented"
    path = write_inventory(tmp_path, data)
    res = run_script("--check-doc", inventory_path=path)
    assert res.returncode == 1
    assert "rigtest-undocumented" in res.stdout


def test_healthy_rig_reports_ok(tmp_path: Path):
    path = write_inventory(tmp_path, inventory())
    fake = write_fake_ssh(tmp_path, facts())
    res = run_script(inventory_path=path, ssh_bin=fake)
    assert res.returncode == 0, res.stdout
    assert "rigtest" in res.stdout
    assert "[OK]" in res.stdout
    assert "DEGRADED" not in res.stdout.split("Summary")[-1]


def test_optional_hardware_missing_degrades(tmp_path: Path):
    path = write_inventory(tmp_path, inventory(include_pynq=True))
    fake = write_fake_ssh(tmp_path, facts())
    res = run_script(inventory_path=path, ssh_bin=fake)
    assert res.returncode == 0, res.stdout
    assert "DEGRADED" in res.stdout
    assert "pynq" in res.stdout

    strict = run_script(inventory_path=path, ssh_bin=fake, args=("--strict",))
    assert strict.returncode == 3


def test_missing_required_hardware_fails(tmp_path: Path):
    path = write_inventory(tmp_path, inventory())
    fake = write_fake_ssh(tmp_path, facts(akida_present=False))
    res = run_script(inventory_path=path, ssh_bin=fake)
    assert res.returncode == 1
    assert "UNHEALTHY" in res.stdout
    assert "akida missing" in res.stdout


def test_unhealthy_service_fails(tmp_path: Path):
    containers = [
        container("suite_api", health="unhealthy"),
        container("launcher-control"),
    ]
    path = write_inventory(tmp_path, inventory())
    fake = write_fake_ssh(tmp_path, facts(containers=containers))
    res = run_script(inventory_path=path, ssh_bin=fake)
    assert res.returncode == 1
    assert "UNHEALTHY" in res.stdout


def test_expected_stopped_service_running_fails(tmp_path: Path):
    containers = [
        container("suite_api"),
        container("launcher-control"),
        container("neurochip-hw-worker"),
    ]
    path = write_inventory(tmp_path, inventory())
    fake = write_fake_ssh(tmp_path, facts(containers=containers))
    res = run_script(inventory_path=path, ssh_bin=fake)
    assert res.returncode == 1
    assert "neurochip-hw-worker is running but should be stopped" in res.stdout


def test_missing_overlay_fails(tmp_path: Path):
    containers = [
        container(
            "suite_api", config_files="docker-compose.yml,docker-compose.dev.yml"
        ),
        container(
            "launcher-control", config_files="docker-compose.yml,docker-compose.dev.yml"
        ),
    ]
    path = write_inventory(tmp_path, inventory())
    fake = write_fake_ssh(
        tmp_path, facts(containers=containers, neurochip_service="inactive")
    )
    res = run_script(inventory_path=path, ssh_bin=fake)
    assert res.returncode == 1
    assert "overlay akida-native is not active" in res.stdout


def test_unreachable_rig_is_down(tmp_path: Path):
    path = write_inventory(tmp_path, inventory())
    fake = write_fake_ssh(tmp_path, payload=None, exit_code=255)
    res = run_script(inventory_path=path, ssh_bin=fake)
    assert res.returncode == 1
    assert "DOWN" in res.stdout


def test_json_output_is_machine_readable(tmp_path: Path):
    path = write_inventory(tmp_path, inventory())
    fake = write_fake_ssh(tmp_path, facts())
    res = run_script(inventory_path=path, ssh_bin=fake, args=("--json",))
    assert res.returncode == 0, res.stdout
    payload = json.loads(res.stdout)
    assert isinstance(payload, list)
    assert payload[0]["id"] == "rigtest"
    assert payload[0]["status"] in ("OK", "DEGRADED", "UNHEALTHY")
    assert payload[0]["reachable"] is True


def test_single_rig_filter(tmp_path: Path):
    path = write_inventory(tmp_path, inventory())
    fake = write_fake_ssh(tmp_path, facts())
    res = run_script(inventory_path=path, ssh_bin=fake, args=("--rig", "rigtest"))
    assert res.returncode == 0


def test_dkms_installed_reported_in_hardware_detail(tmp_path: Path):
    path = write_inventory(tmp_path, inventory())
    payload = facts(dkms_status="akida-dw-edma/1.0, 6.0.0-test, x86_64: installed")
    fake = write_fake_ssh(tmp_path, payload)
    res = run_script(inventory_path=path, ssh_bin=fake)
    assert res.returncode == 0, res.stdout
    assert "DKMS installed" in res.stdout
    assert "DKMS module is not installed" not in res.stdout


def test_missing_akida_dkms_warns_without_failing(tmp_path: Path):
    path = write_inventory(tmp_path, inventory())
    payload = facts(dkms_status="akida-dw-edma/1.0, 6.0.0-test, x86_64: built")
    fake = write_fake_ssh(tmp_path, payload)
    res = run_script(inventory_path=path, ssh_bin=fake)
    assert res.returncode == 0, res.stdout
    assert "DKMS NOT installed" in res.stdout
    assert "akida-dw-edma DKMS module is not installed" in res.stdout


def _write_repair_ssh(tmp_path: Path, unbound: dict, bound: dict, subdir: str) -> Path:
    """Fake ssh: first probe is unbound, the repair runs the helper, next probe is bound."""
    base = tmp_path / subdir
    fake_bin = base / "bin"
    fake_bin.mkdir(parents=True, exist_ok=True)
    counter = base / "probe-count"
    fake = fake_bin / "fake-repair-ssh"
    fake.write_text(
        f"""#!/bin/sh
cmd="$*"
if echo "$cmd" | grep -q "nmtk-akida-driver-rebuild"; then
  echo "==> akida-pcie bound for kernel 6.0.0-test"
  exit 0
fi
cat >/dev/null
count=$(cat "{counter}" 2>/dev/null || echo 0)
if [ "$count" -eq 0 ]; then
  printf '%s\\n' '{json.dumps(unbound)}'
  echo 1 > "{counter}"
else
  printf '%s\\n' '{json.dumps(bound)}'
fi
""",
        encoding="utf-8",
    )
    fake.chmod(0o755)
    return fake


def test_repair_runs_helper_and_recovers_unbound_driver(tmp_path: Path):
    path = write_inventory(tmp_path, inventory())
    unbound = facts(akida_driver="")
    bound = facts(akida_driver="akida-pcie")

    without = run_script(
        inventory_path=path,
        ssh_bin=_write_repair_ssh(tmp_path, unbound, bound, subdir="without"),
    )
    assert without.returncode == 1
    assert "no driver bound" in without.stdout

    healed = run_script(
        inventory_path=path,
        ssh_bin=_write_repair_ssh(tmp_path, unbound, bound, subdir="healed"),
        args=("--repair",),
    )
    assert healed.returncode == 0, healed.stdout
    assert "repair akida-pcie-driver" in healed.stdout
    assert "bound to akida-pcie" in healed.stdout


def test_repair_reports_failure_when_helper_missing(tmp_path: Path):
    path = write_inventory(tmp_path, inventory())
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir(exist_ok=True)
    fake = fake_bin / "fake-fail-ssh"
    fake.write_text(
        f"""#!/bin/sh
cmd="$*"
if echo "$cmd" | grep -q "nmtk-akida-driver-rebuild"; then
  echo "nmtk-akida-driver-rebuild is not installed" >&2
  exit 127
fi
cat >/dev/null
printf '%s\\n' '{json.dumps(facts(akida_driver=""))}'
""",
        encoding="utf-8",
    )
    fake.chmod(0o755)
    res = run_script(inventory_path=path, ssh_bin=fake, args=("--repair",))
    assert res.returncode == 1
    assert "repair akida-pcie-driver" in res.stdout
    assert "driver repair failed" in res.stdout
