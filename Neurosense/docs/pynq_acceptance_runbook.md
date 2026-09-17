# PYNQ Z2 Acceptance Runbook

This runbook prepares and executes PYNQ edge-sensor validation on the NeuroSense
backend. It does not claim that PYNQ has already been validated on real hardware
until a real-board run passes.

Current support label for PYNQ: `prototype`

## What This Script Covers

The acceptance script validates the edge-sensor path:

`discover PYNQ node -> start NDJSON stream -> verify spike payloads -> stop stream`

Checklist performed by `python -m neurosense.tests.validate_pynq`:

- discover devices via `GET /sense/pynq/devices`
- resolve the target `device_id`
- start the NDJSON stream (`POST /sense/pynq/stream/start`)
- verify each frame includes `spikes`
- stop the stream (`POST /sense/pynq/stream/stop`)

For real-board runs, the script also probes the documented WebSocket URI
(`ws://{device_id}.local:8000/stream`) before starting the stream.

## Prerequisites

- NeuroSense backend running for real-board validation (default `http://127.0.0.1:8004/api/neurosense`)
- PYNQ Z2 board on the network with the spike-stream service reachable
- For rehearsal without hardware or a running backend: use `--simulated`

## Commands

Simulated rehearsal (in-process, no backend required):

```bash
cd Neurosense
PYTHONPATH=neurosense:../nmtk_contracts python -m neurosense.tests.validate_pynq --simulated
```

Real-board validation against a running backend:

```bash
PYTHONPATH=neurosense:../nmtk_contracts python -m neurosense.tests.validate_pynq \
  --base-url http://192.168.2.90:8004/api/neurosense
```

Explicit device override:

```bash
PYTHONPATH=neurosense:../nmtk_contracts python -m neurosense.tests.validate_pynq \
  --base-url http://192.168.2.90:8004/api/neurosense \
  --device-id pynq_board_01
```

## Expected Output

The script prints pass/fail for each checklist step and writes evidence JSON:

- simulated rehearsal: `pynq_acceptance_simulated.json`
- real-board execution: `pynq_acceptance_real.json`

## Troubleshooting

| Symptom | Likely Cause | Action |
| --- | --- | --- |
| Connection refused on default URL | Backend not running | Start NeuroSense or pass `--base-url` |
| Only simulated stub devices exposed | No real PYNQ registered | Register the board or use `--simulated` for rehearsal |
| WebSocket probe failed | Board offline or wrong hostname | Verify `{device_id}.local` resolves and port 8000 is open |
| Stream returned no NDJSON frames | Stream service hung | Restart the PYNQ spike service and retry |
| Frames still marked `simulated=true` | Real path hit stub | Pass explicit `--device-id` for a registered real board |
