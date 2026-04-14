# PYNQ Z2 Plug-and-Play Checklist

Date: 2026-04-14

Companion to:

- `docs/2026-04-14-pynq-plug-and-play-deployment-plan.md`

## Key Conclusion

Real PYNQ inference still needs **some software on the board** because the
local `pynq` library, overlay load, MMIO, and DMA are board-local operations.

What should change is **what** we deploy:

- not the full Neurochip module
- yes to a thin `neurochip-pynq-agent`

## Current Limitation

Today the user is effectively expected to provide a running remote
Neurochip-compatible endpoint manually.

The current UI and handoff logic do not provision the board for them.

## Target UX

Desired user path:

1. Power and network the board
2. Open launcher
3. Pair board
4. Click `Provision`
5. Wait for `Ready`
6. Click `Deploy`
7. Click `Infer`

No manual terminal steps.

## Ordered Work

### 1. Extract the board runtime agent

Done when:

- a minimal `neurochip-pynq-agent` package exists
- it owns only PYNQ runtime routes
- it can load the overlay and run inference locally

### 2. Add board provisioning to launcher control

Done when:

- launcher control can connect to the board
- upload the runtime bundle
- upload overlay assets
- install or update the service
- start and restart the service
- read preflight and status

### 3. Add paired-board state to the launcher

Done when:

- launcher stores paired board metadata
- board selection uses a paired device, not a raw URL field
- users can reprovision and repair from UI

### 4. Add appliance-image support

Done when:

- a prebuilt image path exists
- first-boot pairing works
- stock-user setup is simpler than SSH provisioning

### 5. Integrate with deploy and inference flows

Done when:

- NeuroCNL deploy flow targets a paired board
- launcher exposes provisioning and readiness
- real-board inference can be started without manual board setup

## Write Sets

### Launcher

- paired board model
- provisioning provider
- control-plane actions
- PYNQ UI flow
- preflight and doctor coverage

### Neurochip

- runtime agent package
- shared PYNQ runtime contracts
- install bundle generation
- service unit template
- overlay asset installer

### NeuroCNL

- consume paired-board configuration instead of manual board URL
- keep truthful support claims until real flow is complete

## Acceptance Gate

Do not call it plug-and-play until:

- no manual SSH session is required
- no manual package install is required
- no manual `uvicorn` launch is required
- no manual `.bit/.hwh` copy is required
- launcher preflight reports board readiness correctly
- real-board inference succeeds from the guided flow

## First Recommended Implementation Step

Start by extracting the board-side `neurochip-pynq-agent`.

That is the dependency that determines the rest of the provisioning and UI
shape.
