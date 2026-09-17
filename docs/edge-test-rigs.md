# Edge test-rig fleet inventory

Developer-only document. This is the human-readable companion to
[`config/edge_test_rigs.json`](../config/edge_test_rigs.json), which is the
machine-readable single source of truth. `scripts/fleet_health.py` reads the
JSON; this page explains each rig and how to bring its hardware up.

`make check-devices` runs the fleet health report. `python3
scripts/fleet_health.py --check-doc` fails when a rig exists in the JSON but is
not listed here, so the two stay in step.

## Quick reference

```bash
make check-devices                       # fleet report for every rig
make check-fleet ARGS='--json'           # same, machine-readable
make rig-verify RIG=moosebun2            # report one rig
make rig-provision RIG=moosebun2         # sync + bring the rig up, then verify
python3 scripts/fleet_health.py --list-rigs
python3 scripts/fleet_health.py --print-target moosebun2
```

`make check-flutter-devices` still lists local Flutter devices. That is what the
`dev-*` and `docker-*` targets call before launching a UI; `check-devices` no
longer does, because a fleet report is not a Flutter device check.

## Inventory

| Rig id | Kind | Address | Roles |
| --- | --- | --- | --- |
| `moosebun2` | hardware-rig | `moosebun2@192.168.2.90` | dev backend, CI-runner host, Akida, Prophesee, PYNQ |
| `hp-prodesk` | hardware-rig | `192.168.2.51` | secondary test rig (profile not recorded yet) |
| `runner-win-wsl2` | ci-runner | `192.168.2.91` | Windows + WSL2 self-hosted CI runner |
| `runner-macos` | ci-runner | not recorded | macOS self-hosted CI runner |

CI runners are checked through the GitHub Actions runners API by label, so they
need no SSH login. See [`docs/ci-runners.md`](ci-runners.md) for the runner
labels, wake-on-LAN setup, and required secrets.

## What the report checks

For each hardware rig, one SSH call collects raw facts, then the report
evaluates them:

| Column | Meaning |
| --- | --- |
| reachable | The rig answered SSH and its probe returned JSON. |
| overlays | Active Compose overlay files, read from the running containers' labels, plus the expected set. |
| services | Each expected Compose service: running and healthy, unhealthy, or missing. Services listed as `expectedStoppedServices` must not be running. |
| hardware | Each expected hardware item: present or missing. Optional items only degrade the rig, they do not fail it. |

Overall status per rig:

- `OK` — reachable, every expected service healthy, every required hardware item present.
- `DEGRADED` — reachable, only optional items are missing or down.
- `UNHEALTHY` — reachable, but a required service, overlay, or hardware item failed.
- `DOWN` — SSH did not reach the rig.

`make check-devices` exits non-zero on `DOWN` or `UNHEALTHY`. Add
`ARGS='--strict'` to fail on `DEGRADED` too.

The probe is standard-library Python on the rig. It reads `lsusb`, the PCI
sysfs tree, `systemctl is-active neurochip.service`, `/dev/akida*`, and the
Compose container list. It never writes and never restarts anything.

## Compose overlay matrix

`make rig-provision` and `make dev-update` apply overlays automatically, so QA
and Engineer do not need to remember the matrix. The detection rules live in
`scripts/dev_update.sh`:

| Overlay | Applied when | Why |
| --- | --- | --- |
| `docker-compose.yml` + `docker-compose.dev.yml` | always | base topology and dev bind mounts |
| `docker-compose.akida-native.yml` | `systemctl is-active neurochip.service` is `active`, or port 8002 answers with no container publishing it | the native Akida service owns port 8002; the SDK-less containerized worker must stay stopped |
| `docker-compose.prophesee.yml` | `lsusb` shows vendor `1d43` | builds the OpenEB worker and passes `/dev/bus/usb` through |

Force a choice with `AKIDA_NATIVE=1` / `=0` or `ARGS='--prophesee'` /
`ARGS='--no-prophesee'`.

## Hardware bring-up per device

### BrainChip AKD1000 (PCIe) — `moosebun2`

1. Confirm the card is visible: `lspci -nn | grep -i 1e7c:0xbca1` (PCI vendor
   `0x1e7c`, device `0xbca1`).
2. Confirm the driver is bound and memory space is enabled. The probe reads
   `/sys/bus/pci/devices/<bdf>/`; the same logic is in
   `Neurochip/neurochip/provisioning/akida_host_bundle.py`.
3. Confirm the runtime: `systemctl is-active neurochip.service` must be
   `active`, and `curl http://192.168.2.90:8002/health` must answer.
4. The containerized `neurochip-hw-worker` must stay stopped on this rig.

Never run `sudo fuser -k 8002/tcp` on `moosebun2`: that kills the service the
box exists to provide.

### Prophesee EVK (USB3) — `moosebun2`

1. Plug the EVK into a USB3 port.
2. Confirm the bus sees it: `lsusb | grep 1d43`.
3. Apply the overlay and verify:
   `make rig-provision RIG=moosebun2 ARGS='--prophesee'`.
4. Run the acceptance script:
   `PYTHONPATH=neurosense python3 -m neurosense.tests.validate_prophesee --api-base http://192.168.2.90:8004`.

As of 2026-09-17 the EVK is not connected, so `stream/start` returns
`Failed to open camera !` (CEL-294, CEL-299). The report shows this as an
optional missing item, which is why `moosebun2` can still be `OK` without it.

### PYNQ Z2 — `moosebun2` / network

The simulated PYNQ path works today. The real board is expected at
`ws://pynq.local:8000/stream`; the report probes `pynq.local:8000` as an
optional TCP check. A real board was not on the network as of 2026-09-17
(CEL-284).

## Provisioning and verification

- `make rig-verify RIG=<id>` runs the read-only report for one rig.
- `make rig-provision RIG=<id>` resolves the rig's SSH target from the JSON,
  runs `scripts/dev_update.sh` against it (tests, sync, minimum rebuild, overlay
  auto-detection), then verifies. It is idempotent: a second run finds the stack
  already up and makes no changes.
- `make check-server` remains the deeper dev-host check that restarts failed
  services. The fleet report is the read-only, fleet-wide view.

## Adding or changing a rig

1. Edit `config/edge_test_rigs.json`: add the rig, its target, roles, expected
   services, overlays, and hardware.
2. Add a row to the inventory table above. `--check-doc` fails until you do.
3. Run `make check-devices` and confirm the rig reports the status you expect.

## Known gaps

- **Prophesee EVK is not connected.** SDK provisioning is done (CEL-291, CEL-294);
  the camera is missing (CEL-299). The report flags it as an optional missing item.
- **`hp-prodesk` profile is not recorded.** Its SSH user, expected services, and
  attached hardware are unknown, so the entry is reachability-only until filled in.
- **PYNQ real board is unconfirmed.** Only the simulated stream is validated.
- **macOS runner host is not recorded.** Set `RELEASE_RUNNER_MACOS` and register
  the runner before it can be reported, per [`docs/ci-runners.md`](ci-runners.md).
