# NeuroSense API Documentation

This page documents the human-facing NeuroSense HTTP and WebSocket API. The
live OpenAPI schema at `/openapi.json` is authoritative for exact HTTP request
and response models.

Default base URL: `http://127.0.0.1:8004`

Live docs:

- Swagger UI: `http://127.0.0.1:8004/docs`
- OpenAPI JSON: `http://127.0.0.1:8004/openapi.json`
- Health: `http://127.0.0.1:8004/health`

## Authentication

API-key authentication is optional. When `NEUROSENSE_AUTH_ENABLED=true`, most
routes require either:

```http
X-API-Key: <NEUROSENSE_API_KEY>
```

or:

```text
?api_key=<NEUROSENSE_API_KEY>
```

The query form is useful for WebSocket clients. Prophesee routes are currently
registered without the shared API-key dependency.

## Operational Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Service health check. |
| `GET` | `/docs` | FastAPI Swagger UI. |
| `GET` | `/openapi.json` | Canonical generated OpenAPI schema. |
| `GET` | `/` | Frontend mount or fallback API message. |

## Devices

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurosense/devices` | Scan/list available biosignal devices. |
| `POST` | `/api/neurosense/devices/{device_id}/connect` | Connect to a device. |
| `POST` | `/api/neurosense/devices/{device_id}/disconnect` | Disconnect a device. |
| `GET` | `/api/neurosense/devices/{device_id}/impedance` | Run an impedance check. |

Current support caveats:

- The synthetic board is always available for no-hardware development.
- The Cyton path is the current real-board acceptance target when configured.
- Ganglion, Muse, BITalino, and generic paths should not be claimed as equally
  validated unless their own no-mock acceptance evidence exists.

Optional connect body:

```json
{
  "serial_port": "/dev/cu.usbserial-DM0258P6"
}
```

## Presets and Signal Quality

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurosense/presets` | List acquisition/encoding presets. |
| `GET` | `/api/neurosense/presets/{preset_id}` | Fetch one preset. |
| `POST` | `/api/neurosense/presets` | Save a custom preset. |
| `GET` | `/api/neurosense/quality` | Fetch signal-quality metrics for the connected device. |

## Encoding and Export

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurosense/encode` | Encode analog samples into spike output. |
| `POST` | `/api/neurosense/export` | Export spike-encoded data or session windows. |
| `POST` | `/api/neurosense/nir/import` | Import NIR data into an encoding configuration. |

Example encode request shape:

```json
{
  "channels": [[0.1, 0.2, 0.3]],
  "sampling_rate_hz": 250,
  "encoding_config": {
    "method": "rate",
    "rate_max_hz": 200
  }
}
```

Verify exact field names through `/openapi.json`, because encoding schemas are
owned by NeuroSense contracts.

## Streaming

| Method | Path | Purpose |
| --- | --- | --- |
| `WS` | `/api/neurosense/stream/raw` | Stream raw analog frames. |
| `WS` | `/api/neurosense/stream/filtered` | Stream filtered analog frames. |
| `WS` | `/api/neurosense/stream/spikes` | Stream spike-encoded frames. |

WebSocket auth, when enabled, can use `?api_key=...` because many clients do
not support custom headers during WebSocket setup.

Example spike frame:

```json
{
  "timestamp": 1678901234.56,
  "spike_trains": [[0.01, 0.05], [0.02, 0.08]],
  "spike_counts": [2, 2],
  "method": "rate",
  "sampling_rate_hz": 250
}
```

## Recording and Sessions

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurosense/recording/start` | Start a recording session. |
| `POST` | `/api/neurosense/recording/stop` | Stop recording and return session metadata. |
| `POST` | `/api/neurosense/recording/marker` | Add an event marker to the active recording. |
| `GET` | `/api/neurosense/sessions` | List recorded sessions. |
| `GET` | `/api/neurosense/sessions/{session_id}` | Fetch one session's metadata. |
| `GET` | `/api/neurosense/sessions/{session_id}/download` | Download session data. |
| `POST` | `/api/neurosense/sessions/{session_id}/replay` | Start replaying a session. |
| `POST` | `/api/neurosense/sessions/{session_id}/replay/stop` | Stop an active replay. |

Example marker request:

```json
{
  "label": "subject_flexed_wrist"
}
```

## Event-Camera and PYNQ Routes

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurosense/sense/prophesee/devices` | List Prophesee/event-camera candidates. |
| `POST` | `/api/neurosense/sense/prophesee/stream/start` | Start event-camera stream flow. |
| `POST` | `/api/neurosense/sense/prophesee/stream/stop` | Stop event-camera stream flow. |
| `GET` | `/api/neurosense/sense/pynq/devices` | List PYNQ sensor-node candidates. |
| `POST` | `/api/neurosense/sense/pynq/stream/start` | Start PYNQ sensor stream. |
| `POST` | `/api/neurosense/sense/pynq/stream/stop` | Stop PYNQ sensor stream. |

These routes are hardware-adjacent and may use simulated or placeholder paths
unless a real device and acceptance evidence are present.

## Related Docs

- [`../neurosense_spec.md`](../neurosense_spec.md) describes product-level API intent.
- [`user_guide_connecting_device.md`](user_guide_connecting_device.md) covers user setup.
- [`developer_guide_adding_device.md`](developer_guide_adding_device.md) covers device integration.
- [`integration_guide_neurosense_to_toolkit.md`](integration_guide_neurosense_to_toolkit.md) covers suite integration.
