# PYNQ Z2 Plug-and-Play Deployment Plan

Date: 2026-04-14

## Current Truth

The current implementation assumes a **remote Neurochip-compatible PYNQ
service** already exists somewhere on the network.

Evidence in the repo:

- `neurocnl/neurocnl/handoff/neurochip_pynq_handoff.py` sends the deploy
  payload to `POST /hardware/pynq/deploy` on a configured remote base URL.
- `neurocnl/backend/app/routers/deploy.py` only validates and builds a deploy
  payload; it does not provision a board or start a runtime there.
- `neurocnl/frontend/lib/widgets/pynq_deploy_panel.dart` currently exposes a
  `Board URL` field, but the flow is still operator-driven.
- `Neurochip/neurochip/app/services/pynq_backend.py` uses the local `pynq`
  library, local overlay assets, MMIO, and DMA. That means **real inference
  requires code running on the board or on a machine with direct local access
  to the board runtime**.

## Answer to the Architecture Question

### Is Neurochip currently required on the PYNQ board?

**Yes, in the current implementation the board-side target must run a
Neurochip-compatible service for real hardware inference.**

More precisely:

- the current design requires a process on the board that exposes
  `/hardware/pynq/deploy`, `/hardware/pynq/run`, `/hardware/pynq/status`, and
  `/hardware/pynq/preflight`
- that process must call the local `pynq` Python library and load the local
  overlay

### Can we avoid deploying full Neurochip to the board?

**Yes.**

We cannot avoid a **board-side runtime component**, because `pynq.Overlay`,
DMA, and MMIO are local board operations. But we **can and should avoid
deploying the full Neurochip module** if the goal is plug-and-play inference.

## Chosen Direction

For plug-and-play UX, use this split:

- **Host side**:
  - `neurocnl` remains responsible for parse, lower, plan, and artifact export
  - host-side orchestration remains in the launcher and control-plane surfaces
- **Board side**:
  - replace “full Neurochip install” with a **minimal PYNQ runtime agent**
  - the agent exposes only the runtime endpoints needed for deploy, run,
    verify, status, and preflight

Decision:

- do **not** require users to manually install and run the full Neurochip
  module on the PYNQ board
- do **require** a minimal board-side runtime agent
- provisioning and startup of that agent must be handled by the launcher or
  launcher control service, not by manual terminal steps

## Product Goal

The user flow should become:

1. Connect PYNQ Z2 to power and network
2. Open NMTK launcher
3. Pair the board once
4. Click `Provision Board`
5. Wait for readiness to turn green
6. Run `Deploy` and `Infer`

No manual SSH session, no manual Poetry install, no manual `uvicorn` command.

## Architecture

### Board-Side Runtime: `neurochip-pynq-agent`

Create a dedicated minimal service for the board:

- package name: `neurochip-pynq-agent`
- purpose: local FPGA runtime only
- contains:
  - overlay asset inspection
  - `pynq.Overlay` loading
  - MMIO configuration
  - DMA spike input and output
  - preflight and status reporting
  - optional SITL verify route
- excludes:
  - full Neurochip target catalog
  - Teensy, Akida, Lava, Loihi, and other non-PYNQ routes
  - host-side planning and export logic

The agent should be small enough to package as:

- a wheel or zipapp
- a board-side venv bundle
- or a prebuilt image payload

### Host-Side Orchestration

Keep orchestration off the board:

- `neurocnl` produces the validated PYNQ deploy payload
- launcher control service handles:
  - board discovery
  - provisioning
  - service start and stop
  - readiness polling
  - auth or key management
- UI surfaces in `nmtk` should never ask the user to run shell commands on the
  board

### Why This Split Is Correct

This keeps the unavoidable board-local hardware logic where it belongs, but
removes the unnecessary burden of a full board-side Neurochip install.

The board still needs software, but not the whole developer-oriented module.

## Provisioning Strategy

Use a two-tier provisioning model.

### Preferred Path: Appliance Image

Ship a PYNQ Z2 SD-card image or image overlay that already includes:

- Python runtime
- `pynq`
- `neurochip-pynq-agent`
- `systemd` unit for auto-start
- canonical overlay directory
- first-boot pairing endpoint or known bootstrap credentials

This is the most plug-and-play path.

### Fallback Path: Launcher-Driven Remote Provisioning

If users are on a stock PYNQ image, the launcher should provision the board by
itself over the network.

Provisioning sequence:

1. Discover board by mDNS, manual IP entry, or remembered host
2. Verify SSH reachability
3. Upload:
   - runtime agent package
   - overlay assets
   - overlay manifest
   - service unit file
4. Create venv on the board
5. Install the agent and dependencies
6. Enable and start the systemd service
7. Run `/hardware/pynq/preflight`
8. Save the board as a paired device in launcher settings

The user should see this as a single guided UI flow.

## Launcher UX Plan

### New User-Facing Flow

The launcher should add a dedicated PYNQ pairing and provisioning flow:

- `Pair Board`
- `Provision Runtime`
- `Install Overlay`
- `Check Readiness`
- `Deploy`
- `Run Inference`

### Required Launcher States

Per paired board:

- `unpaired`
- `reachable`
- `provisioning`
- `provision_failed`
- `runtime_installed`
- `overlay_missing`
- `ready`
- `degraded_optional_capability`
- `error`

The launcher must distinguish:

- **preflight failed**
- **degraded optional capability**

as required by the launcher guardrails.

### Board Configuration

The launcher should store:

- board display name
- IP or hostname
- SSH port
- username
- auth mode
  - password on first pairing only
  - SSH key preferred after pairing
- runtime API URL
- overlay version
- last preflight result

## Control-Plane Design

The launcher control service should own the mutating remote setup actions.

Add endpoints or control actions for:

- register paired board
- test SSH connectivity
- provision board runtime
- install overlay assets
- restart board runtime
- fetch board preflight
- fetch board status

This keeps the Flutter launcher thin and puts the operational logic in the
control plane where diagnostics, retries, and structured reporting belong.

## Board-Side Runtime Contract

The minimal board agent must expose:

- `GET /health`
- `GET /hardware/pynq/preflight`
- `GET /hardware/pynq/status`
- `POST /hardware/pynq/deploy`
- `POST /hardware/pynq/run`
- `POST /hardware/pynq/verify`

It should preserve the same request and response shapes already used by the
current Neurochip PYNQ runtime where possible so the host-side code can be
reused.

## Security and Pairing

### First Pairing

Accept one of:

- temporary SSH password entered into the launcher
- preinstalled bootstrap key
- first-boot one-time token shown by the board

### Post-Pairing

After successful provisioning:

- disable default credentials
- install a launcher-managed SSH key
- enable runtime API auth if configured
- store only the minimum needed launcher-side secret material

This should be designed for lab LAN use, not open internet exposure.

## Overlay Asset Handling

The user should not manually copy `.bit` and `.hwh` files.

The provisioning flow should:

- upload `.bit`
- upload `.hwh`
- upload `overlay_manifest.json`
- verify checksum
- place them in the canonical runtime directory
- rerun preflight automatically

If the board runtime and overlay version drift, the launcher should surface a
clear remediation action: `Reinstall Overlay`.

## Exact Write Sets

### `nmtk` / launcher

- `nmtk/neuro_toolkit/assets/modules.json`
- launcher control service files under `nmtk/launcher_control/` or
  `scripts/launcher_control_service.py`
- launcher models and provider logic for paired PYNQ boards
- PYNQ deployment UI in `nmtk/neuro_toolkit/lib/`
- launcher tests

### `Neurochip`

- extract a board-side `neurochip-pynq-agent` package from the existing PYNQ
  backend and router code
- shared runtime contract definitions
- overlay asset validation
- provisioning scripts or install bundle generation

### `neurocnl`

- remove assumptions that the user manually manages the board URL
- wire deploy flow to the paired-board abstraction once launcher control owns it
- preserve truthful support semantics until the plug-and-play path is actually
  complete

## Phases

### Phase 1. Extract the minimal board runtime

Deliverable:

- `neurochip-pynq-agent` package

Definition of done:

- board-side runtime works without shipping the full Neurochip module
- host-side payload shape remains compatible

### Phase 2. Add launcher-driven provisioning

Deliverable:

- one-click provisioning from the launcher

Definition of done:

- user can provision a stock board from UI
- no terminal access required
- control-plane surfaces structured preflight results

### Phase 3. Add appliance image path

Deliverable:

- prebuilt board image for easiest setup

Definition of done:

- fresh SD card boots directly into pairable runtime mode
- launcher can detect and finalize pairing

### Phase 4. Integrate deploy and inference UX

Deliverable:

- user-facing `Deploy` and `Infer` flow built on paired boards

Definition of done:

- board selection is launcher-managed, not manual URL entry
- deploy and run are one-click actions after provisioning

## Acceptance Criteria

The plug-and-play path is complete only when:

1. the user does not need to SSH manually
2. the user does not need to run `poetry` or `uvicorn` manually on the board
3. the user does not need to copy overlay files manually
4. the launcher can provision, start, and verify the board runtime
5. inference works on the real board after pairing
6. failures are reported as actionable preflight states, not generic errors

## Explicit Decisions

- **A board-side runtime is still required.**
- **The full Neurochip module is not required on the board.**
- **The recommended design is a thin board-side PYNQ agent plus host-side
  orchestration.**
- **Launcher-driven provisioning is the correct UX target.**

## Resume-Here Pointer

If work resumes later, start with:

1. extract `neurochip-pynq-agent`
2. design launcher control provisioning endpoints
3. replace manual board URL UX with paired-board UX
