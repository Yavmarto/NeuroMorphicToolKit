# PYNQ and Akida Deployment Explained

This note explains, in simple terms, what the toolkit actually does when you click deploy for PYNQ or Akida, and how you can verify that yourself with `semble`.

## Short version

PYNQ deploy and Akida deploy do **not** mean the same thing.

- **PYNQ deploy** means: the toolkit prepares a board-specific payload, contacts a PYNQ runtime, loads the FPGA overlay, and writes the network weights/config into the runtime.
- **Akida deploy** usually means: the toolkit generates an Akida ZIP package and then optionally checks whether the Akida SDK can map that model in the current runtime.

So if PYNQ deploy succeeds, something was actually configured on the board runtime.

If Akida deploy succeeds in the default path, it often means the package was created successfully, not that a physical Akida chip was programmed.

## How to verify this with `semble`

Start with these searches from the repo root:

```bash
semble search "PYNQ deployment flow exportability deploy overlay board status" .
semble search "Akida deployment flow scaffold package verify SDK status" .
```

Then inspect the key files:

```bash
semble search "POST /api/deploy/pynq/network" .
semble search "POST /api/deploy/akida/network" .
semble search "/hardware/pynq/deploy" .
semble search "/api/neurochip/akida/deploy/mapped" .
semble search "load_overlay configure weights MMIO" .
semble search "generate_package akida_deploy/model.json weights.bin manifest.json" .
```

The main files to read are:

- `neurocnl/backend/app/routers/deploy.py`
- `neurocnl/neurocnl/contracts/pynq_deployment_contract.py`
- `neurocnl/neurocnl/contracts/pynq_runtime_artifact_contract.py`
- `Neurochip/frontend/lib/services/pynq_deploy_service.dart`
- `Neurochip/neurochip/app/routers/pynq.py`
- `Neurochip/neurochip/app/services/pynq_backend.py`
- `Neurochip/frontend/lib/services/akida_deploy_service.dart`
- `Neurochip/neurochip/app/routers/akida.py`
- `Neurochip/neurochip/app/services/akida_backend.py`
- `Neurochip/neurochip/contracts/akida_runtime_contract.py`

## What PYNQ deploy does

### Step 1: NeuroCNL checks whether the network can fit the PYNQ target

The frontend calls:

- `POST /api/deploy/pynq/network`

That route lives in `neurocnl/backend/app/routers/deploy.py`.

What it does:

1. Parses your CNL spec.
2. Lowers it into the internal network representation.
3. Runs `plan_pynq_exportability(...)`.
4. If the network is exportable, it also generates a deploy payload.

This is the important distinction:

- **exportable** means the toolkit can produce the PYNQ artifact offline
- **deployable** means a real board runtime accepted and loaded it

The PYNQ contract says this explicitly.

### Step 2: NeuroCNL builds a deploy payload

If exportability passes, NeuroCNL generates a PYNQ artifact and turns it into a deploy payload.

The artifact contract requires files like:

- `pynq_deploy/overlay_config.json`
- `pynq_deploy/weights.bin`
- `pynq_deploy/register_map.json`
- `pynq_deploy/overlay_manifest.json`
- `pynq_deploy/manifest.json`

So at this point the toolkit has created the data needed to configure the overlay.

### Step 3: The frontend sends that payload to the selected board runtime

The frontend service in `Neurochip/frontend/lib/services/pynq_deploy_service.dart`:

- checks exportability through NeuroCNL
- then sends the deploy payload to the board runtime through the control API

That ends up at:

- `POST /hardware/pynq/deploy`

in `Neurochip/neurochip/app/routers/pynq.py`.

### Step 4: The PYNQ runtime loads the overlay and writes the network into it

This is the part that answers "what happened?" when deploy succeeds.

The PYNQ backend does this:

1. Validates the overlay request against the installed manifest.
2. Creates a `PYNQBackend`.
3. Calls `load_overlay()`.
4. Calls `configure(weights, config, register_map)`.

Inside `load_overlay()` and `configure()` in `Neurochip/neurochip/app/services/pynq_backend.py`, the runtime:

- checks that the `.bit` file exists
- checks that the `.hwh` file exists
- checks that the overlay manifest exists and is valid
- loads the FPGA overlay
- finds the DMA and SNN IP blocks
- writes control values
- writes threshold/config values
- writes the quantized weights into the mapped registers

So a successful PYNQ deploy means:

- the overlay assets were accepted
- the runtime loaded the overlay
- the network weights/config were written into the runtime

It does **not** mean inference has run yet.

Inference is a later step:

- `POST /hardware/pynq/run`

Verification is another later step:

- `POST /hardware/pynq/verify`

### What a successful PYNQ deploy really means

In plain terms:

> The toolkit turned your CNL network into a board payload, connected to the PYNQ runtime, loaded the FPGA design, and programmed that runtime with your network settings.

That is why PYNQ deploy feels like a real deployment. It is.

## What Akida deploy does

### Step 1: NeuroCNL checks whether the network is Akida-compatible

The frontend calls:

- `POST /api/deploy/akida/network`

That route also lives in `neurocnl/backend/app/routers/deploy.py`.

What it does:

1. Parses the CNL spec.
2. Lowers it into the internal representation.
3. Runs `plan_akida_exportability(...)`.
4. If supported, builds a `mapped_network` payload.

The route description is explicit:

- it proves **exportability**
- it does **not** prove SDK runtime deployability

### Step 2: Neurochip builds an Akida model and package

The frontend then calls:

- `POST /api/neurochip/akida/deploy/mapped`

That route lives in `Neurochip/neurochip/app/routers/akida.py`.

What it does:

1. Creates an `AkidaBackend`.
2. Calls `construct_model(mapped_network, bit_width=...)`.
3. Tries `map_to_device()`.
4. Generates a ZIP package with `generate_package(...)`.

The generated package contains:

- `akida_deploy/model.json`
- `akida_deploy/weights.bin`
- `akida_deploy/manifest.json`
- `akida_deploy/README.md`

### Step 3: SDK mapping is attempted, but not always required

This is the crucial difference from PYNQ.

In the default deployment mode, the backend is allowed to continue even if SDK mapping fails.

The code in `Neurochip/neurochip/app/routers/akida.py` says:

- `scaffold`: just return the ZIP package
- `on_device`: require successful SDK mapping
- `remote_server`: send the ZIP to another runtime server

So most of the time, "deploy Akida" means:

- build the mapped model structure
- try the SDK path if available
- generate a truthful ZIP package
- return that package

It does **not** automatically mean a real Akida chip was programmed.

### Step 4: Verification is a separate runtime check

The Akida runtime proof is done through:

- `GET /api/neurochip/akida/status`
- `POST /api/neurochip/akida/verify`

Those endpoints tell you things like:

- whether the SDK is available
- whether mapping succeeded
- what runtime target was used
- whether the system is using simulator fallback

### What a successful Akida deploy really means

In plain terms:

> The toolkit converted your network into an Akida-shaped package and, if possible, tried to map it through the Akida SDK. In the normal scaffold path, success mainly means "package created successfully."

If you want proof that the current runtime can actually use Akida, look at `status` or `verify`, not just `deploy`.

## The easiest mental model

Use this rule:

- **PYNQ deploy** = "load and configure a board runtime"
- **Akida deploy** = "generate a deployment package, then maybe verify SDK runtime support"

That is why they feel different in practice.

## How to confirm this in the code

If you only want the shortest possible verification trail, inspect these exact codepaths:

### PYNQ

```bash
semble search "POST /api/deploy/pynq/network plan_pynq_exportability export_pynq_artifact" .
semble search "POST /hardware/pynq/deploy load_overlay configure" .
semble search "overlay loaded and configured successfully" .
```

Read the results and look for:

- parse -> lower -> `plan_pynq_exportability`
- artifact creation
- `load_overlay()`
- `configure(...)`
- MMIO or worker-based weight/config writes

### Akida

```bash
semble search "POST /api/deploy/akida/network plan_akida_exportability mapped_network" .
semble search "POST /api/neurochip/akida/deploy/mapped construct_model map_to_device generate_package" .
semble search "deployment_mode scaffold on_device remote_server" .
semble search "GET /api/neurochip/akida/status POST /api/neurochip/akida/verify" .
```

Read the results and look for:

- parse -> lower -> `plan_akida_exportability`
- `mapped_network`
- `construct_model(...)`
- optional `map_to_device()`
- `generate_package(...)`
- separate runtime verification

## Final answer to your example

If you deployed to PYNQ successfully, the most likely meaning is:

1. Your CNL network passed the offline exportability checks.
2. NeuroCNL generated a valid deploy payload.
3. The runtime on the selected PYNQ target accepted that payload.
4. The overlay was loaded.
5. The weights/config were written into the runtime.

So something real did happen.

If you do the same for Akida and it succeeds in the default mode, the most likely meaning is narrower:

1. Your network passed the offline Akida compatibility checks.
2. The toolkit generated a valid Akida package.
3. The runtime may also have verified SDK support, but package generation itself does not guarantee physical-device deployment.

