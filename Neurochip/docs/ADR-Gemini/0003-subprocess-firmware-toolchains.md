# ADR 0003: Subprocess Firmware Toolchains

## Status
Accepted

## Context
Once compiled, SNNs must be structured into firmware binaries (e.g., `.ino`, `.hex`). Building pure C++ or Python firmware linkers internally inside Neurochip creates unmanageable technical debt.

## Decision
NeuroChip's API natively shells out executing commands via the Python `subprocess` module targeting established external toolchains (PlatformIO for teensy, NxSDK for Loihi). The user interacts with the UI, which calls `/export/teensy`, which internally generates `.ino` skeletons and issues a silent shell `pio run -t upload`.

## Consequences
- **Positive:** Massively decreases NMTK system technical debt; heavily leans on industry-standard device flashing packages.
- **Negative:** Mandates system-level installs of dependencies like PlatformIO natively on the host workstation running the backend Docker container or venv, significantly complicating the underlying container orchestration.

## Status Update (2026-07-16 audit)
The claim that `/export/teensy` itself shells out to PlatformIO is not accurate as currently implemented. The `/export/teensy` handler in `neurochip/app/routers/export.py` only validates the network payload and calls `teensy_generator.generate_teensy_project(...)` to build and return a downloadable `.zip` (`Content-Disposition: attachment; filename=neurochip_firmware.zip`); a grep of `export.py` for `subprocess` returns no matches. The actual `subprocess.run` calls (`["pio", "run"]` for build, `["pio", "run", "--target", "upload", "--upload-port", ...]` for upload) live in `neurochip/app/services/flash_service.py`, whose module docstring reads "Flash service — handles PlatformIO build and serial upload." That service is invoked from a different router than this ADR names: `neurochip/app/routers/serial.py`, via its `POST /flash` and `GET /flash/{job_id}` endpoints (plus a `POST /flash/{job_id}/verify` step for post-flash runtime verification), not from the export router. The core decision — shelling out to PlatformIO/NxSDK rather than building an in-house firmware linker — still holds; only the call site differs from what's described above.
