# Prophesee EVK Acceptance Runbook

This runbook prepares and executes Prophesee EVK validation on the NeuroSense
hardware worker. It does not claim that Prophesee has already been validated on
real hardware until a real-board run passes.

Current support label for Prophesee: `prototype`

## What This Script Covers

The acceptance script validates the event-camera path:

`discover EVK -> open live stream -> capture one event batch -> encode -> close`

For deployed workers, `--api-base` additionally checks the HTTP surface:

- `GET /api/neurosense/sense/prophesee/devices`
- `POST /api/neurosense/sense/prophesee/stream/start` with `mode=live`
- `POST /api/neurosense/sense/prophesee/stream/stop`

## Prerequisites

- Metavision SDK installed where validation runs
- Prophesee EVK connected for real-board validation
- `neurosense-hw-worker` running on the test rig for API mode

## Commands

Mock rehearsal (no SDK or camera required):

```bash
cd Neurosense
PYTHONPATH=neurosense python -m neurosense.tests.validate_prophesee --mock
```

Real-board in-process validation:

```bash
PYTHONPATH=neurosense python -m neurosense.tests.validate_prophesee
```

Deployed worker API validation:

```bash
PYTHONPATH=neurosense python -m neurosense.tests.validate_prophesee \
  --api-base http://<dev-host>:8004
```

## Expected Output

The script prints pass/fail for each checklist step and writes evidence JSON:

- mock rehearsal: `prophesee_acceptance_mock.json`
- real-board execution: `prophesee_acceptance_real.json`
- API probe: `prophesee_acceptance_api.json`

## Troubleshooting

| Symptom | Likely Cause | Action |
| --- | --- | --- |
| `metavision-sdk not installed` | SDK missing in hw worker image | Install Metavision in worker or run on host with SDK |
| No devices returned | EVK not connected | Connect EVK over USB3 and retry discovery |
| Stream start fails | Camera busy or permissions | Close other Metavision clients and retry |
| Capture returned zero events | Lens cap on or scene too static | Point camera at motion and retry |
