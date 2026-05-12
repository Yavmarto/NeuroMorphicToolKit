# Teensy 4.1 Deployment — Release Readiness

**Date**: 2026-04-07
**Status**: Release-ready (backend pipeline complete, UI integrated, E2E tested)

---

## Pipeline Overview

The Teensy 4.1 deployment workflow is a 7-stage pipeline spanning three modules:

```
NeuroCNL (port 8000)          Neurochip (port 8002)         Dream-Hand (optional)
┌──────────────────┐          ┌──────────────────┐          ┌──────────────────┐
│ 1. Parse CNL     │          │ 5. Contract      │          │ 8. Protocol      │
│ 2. Lower → IR    │    ──►   │    validation    │    ──►   │    smoke check   │
│ 3. Plan verdict  │          │ 6. Firmware gen  │          │ 9. Hardware demo │
│ 4. Handoff       │          │ 7. Serial flash  │          │ 10. HITL bench   │
└──────────────────┘          └──────────────────┘          └──────────────────┘
```

## Hardware Constraints (Teensy 4.1)

| Parameter | Limit |
|---|---|
| Max neurons | 4,096 |
| Memory budget | 1,024 KB |
| Max I/O pins | 55 GPIO |
| Clock speed | 600 MHz (ARM Cortex-M7) |
| Power envelope | 100 mW |
| Supported neuron models | LIF only |
| Weight bit-widths | 8, 16, 32 |
| Topology | Feedforward only (no recurrent) |
| Learning rules | None (static weights only) |
| Axonal delays | Not supported |

Source of truth: `Neurochip/neurochip/targets/teensy41.json`

## API Endpoints

### NeuroCNL — Deploy Gate

**POST `/api/deploy/teensy/network`**

Request:
```json
{"spec": "<CNL text>", "weight_bit_width": 8}
```

Response (200):
```json
{
  "verdict": "faithful|approximate",
  "warnings": [],
  "rejection_reasons": [],
  "payload": { "num_neurons": 2, "num_synapses": 1, ... }
}
```

Rejection (422):
```json
{
  "detail": {
    "error": "not_deployable",
    "rejection_reasons": ["Network exceeds Teensy neuron capacity..."],
    "warnings": []
  }
}
```

### Neurochip — Firmware Export

**POST `/api/neurochip/export/teensy?bit_width=8`**

- Input: NetworkInput JSON payload (from deploy endpoint above)
- Output: `application/zip` containing `main.ino`, `network_params.h`, `lif_engine.h`, `platformio.ini`

### Neurochip — Serial Flash

- **GET `/api/neurochip/serial/ports`** — List serial devices (Teensy auto-detected)
- **POST `/api/neurochip/serial/flash`** — Start flash job (multipart: firmware zip + port)
- **GET `/api/neurochip/serial/flash/{job_id}`** — Poll job status
- **POST `/api/neurochip/serial/flash/{job_id}/verify`** — Trigger Dream-Hand post-flash verification

### Flash Job Lifecycle

```
PENDING → COMPILING → UPLOADING → VERIFYING → DONE
                                             → FAILED
```

## UI Workflow

The Teensy Deploy screen (`/deploy/teensy`) provides a guided stepper:

1. **CNL Input** — Enter specification text, select weight bit-width (8/16/32)
2. **Verdict Panel** — Color-coded deployment readiness (green/yellow/red)
3. **Firmware Ready** — Confirmation card with zip size
4. **Serial Port Selection** — Auto-detects Teensy devices, manual refresh
5. **Flash Progress** — Real-time progress bar with status polling
6. **Verification Results** — Dream-Hand smoke check, demo results, latency

## Test Coverage

### Unit Tests (per-module)

| Test File | Coverage |
|---|---|
| `neurocnl/neurocnl/tests/test_teensy_deployment_contract.py` | Contract violations, verdicts |
| `neurocnl/neurocnl/tests/properties/test_teensy_deployment_properties.py` | Hypothesis PBT for rejections |
| `neurocnl/neurocnl/layers/test_teensy_validator.py` | L1 invariant checks |
| `neurocnl/neurocnl/handoff/test_neurochip_teensy_mapper.py` | Handoff mapper happy/fail paths |
| `Neurochip/neurochip/tests/test_teensy_generator.py` | Jinja2 template rendering |
| `Neurochip/neurochip/tests/test_teensy_deployment_contract.py` | Contract ↔ JSON drift detection |
| `Neurochip/neurochip/tests/test_flash_service.py` | Flash job lifecycle |

### Integration Tests (cross-module)

| Test File | Coverage |
|---|---|
| `tests/integration/test_teensy_e2e.py` | Happy path (CNL → firmware zip) |
| | Rejected networks (oversized, recurrent, STDP) |
| | Post-flash verification API contract |
| | Cross-module payload schema consistency |
| | Serial port listing |

### Running Tests

```bash
# Unit tests
pytest neurocnl/neurocnl/tests/test_teensy_*.py -v
pytest Neurochip/neurochip/tests/test_teensy_*.py -v

# Integration tests (requires docker-compose up)
pytest tests/integration/test_teensy_e2e.py -v

# Contract drift check
pytest Neurochip/neurochip/tests/test_teensy_deployment_contract.py -k test_match_hardware_profile_json
```

## Deployment Contract Sync

Both modules maintain mirrored contracts with identical limits:

| Constant | neurocnl | Neurochip | teensy41.json |
|---|---|---|---|
| MAX_NEURONS | 4096 | 4096 | 4096 |
| MAX_IO_PINS | 55 | 55 | 55 |
| MEMORY_BUDGET_KB | 1024 | 1024 | 1024 |
| SUPPORTED_NEURON_MODELS | ("LIF",) | ("LIF",) | ["LIF"] |
| WEIGHT_BIT_WIDTHS | (8, 16, 32) | (8, 16, 32) | [8, 16, 32] |

The property test `test_match_hardware_profile_json` ensures these never drift.

## Known Limitations

1. **LIF only** — AdaptiveLIF is not supported in the firmware engine
2. **Feedforward only** — No recurrent connections, lateral inhibition, or spatial connectivity
3. **Static weights** — No on-chip learning (STDP, PES, BCM, Oja)
4. **No axonal delays** — Firmware has no delay buffer
5. **Serial flash requires PlatformIO** — Installed on the Neurochip server
6. **Dream-Hand verification requires hardware** — Serial smoke check needs a connected Teensy
7. **neurodreamhand is an optional dependency** — Verification returns 503 if not installed

## Dependencies

| Dependency | Required | Purpose |
|---|---|---|
| PlatformIO | Yes (Neurochip server) | Compile and upload firmware |
| pyserial | Yes (Neurochip server) | Serial port communication |
| neurodreamhand | Optional | Post-flash runtime verification |
| Jinja2 | Yes (Neurochip server) | Firmware template rendering |
| httpx / pytest-asyncio | Dev only | Integration testing |

## Files Modified in This Review

- `Neurochip/neurochip/targets/teensy41.json` — Fixed AdaptiveLIF → LIF only
- `Neurochip/neurochip/contracts/teensy_deployment_contract.py` — Synced SUPPORTED_NEURON_MODELS
- `tests/integration/test_teensy_e2e.py` — New E2E integration tests
- `nmtk_ui_core/lib/models/teensy_deployment_model.dart` — New data models
- `nmtk/neuro_toolkit/lib/services/teensy_deploy_service.dart` — New REST service
- `nmtk/neuro_toolkit/lib/providers/teensy_deploy_provider.dart` — New state provider
- `nmtk/neuro_toolkit/lib/screens/teensy_deploy_screen.dart` — New deploy UI
- `nmtk/neuro_toolkit/lib/routing/router.dart` — Added `/deploy/teensy` route
- `nmtk/neuro_toolkit/lib/main.dart` — Registered TeensyDeployProvider
- `nmtk/neuro_toolkit/lib/screens/dashboard.dart` — Added Teensy Deploy button
