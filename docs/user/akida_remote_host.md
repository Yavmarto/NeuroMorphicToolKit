# Akida Remote Host Runbook

Use this runbook when the machine running NMTK cannot satisfy the local BrainChip SDK requirements but you still want truthful Akida SDK verification through Neurochip.

## When To Use A Remote Host

Use a remote Akida host when any of the following is true:

- The launcher machine is macOS.
- The local Neurochip environment is not running Python `3.10` to `3.12`.
- You want the BrainChip MetaTF stack isolated on a dedicated Linux or Windows workstation.

The remote host should run both:

- the launcher control API on port `8091`
- the Neurochip backend on port `8002`

## Remote Host Requirements

- Linux or Windows
- Python `3.10` to `3.12`
- BrainChip MetaTF packages:
  `tensorflow==2.19.*`, `akida==2.19.1`, `cnn2snn==2.19.1`, `akida-models==1.13.1`
- On Windows, the current Visual C++ redistributable installed before the MetaTF packages

## Start The Remote Host

1. Clone the full `NeuroMorphicToolKit` repository on the Linux or Windows host.

2. Install the Neurochip environment with the Akida MetaTF extras:

```bash
cd NeuroMorphicToolKit/Neurochip
poetry install --extras "akida-metatf"
```

3. Start the launcher control API from the repository root:

```bash
cd /path/to/NeuroMorphicToolKit
python3 scripts/launcher_control_service.py --host 0.0.0.0 --port 8091
```

4. Start the Neurochip backend from the `Neurochip/` repository:

```bash
cd /path/to/NeuroMorphicToolKit/Neurochip
poetry run uvicorn neurochip.app.main:app --host 0.0.0.0 --port 8002
```

5. Confirm the remote endpoints respond before opening NMTK:

- `http://<host>:8091/health`
- `http://<host>:8002/api/neurochip/akida/status`

## Pair The Host From NMTK

Run the launcher with the remote control and Neurochip base URLs:

```bash
cd /path/to/NeuroMorphicToolKit/nmtk/neuro_toolkit
flutter run \
  --dart-define=NMTK_CONTROL_API_BASE_URL=http://<host>:8091 \
  --dart-define=NMTK_NEUROCHIP_BASE_URL=http://<host>:8002
```

Notes:

- If Neurochip is reachable on the same host at the default port `8002`, `NMTK_CONTROL_API_BASE_URL` is enough for Akida deploy; `NMTK_NEUROCHIP_BASE_URL` is only required when the Neurochip URL differs.
- Keep the launcher on the local machine where you want the UI, but point the Akida runtime work at the remote Linux or Windows host.

## Verify The Pairing In The UI

1. Open **Akida Deploy** in NMTK.
2. Click **Check Readiness** with a known-good Akida spec.
3. Confirm the runtime setup card no longer tells you to prepare the local host when the local environment is incompatible.
4. Confirm the SDK status card reports the remote-host guidance rather than pretending the local machine can run the SDK.
5. Download the scaffold package, then check that Neurochip reports `sdk_status`, `runtime_target`, and `device_info` from the remote host.

## Common Failure Modes

- Control API responds but Akida deploy still uses localhost:
  set `NMTK_NEUROCHIP_BASE_URL` explicitly.
- Remote host reports unsupported Python:
  rebuild the Neurochip environment on Python `3.10`, `3.11`, or `3.12`.
- Akida packages are missing:
  rerun `poetry install --extras "akida-metatf"` or use the local **Prepare Akida Runtime** action only on a supported Linux or Windows host.
