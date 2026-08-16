# PYNQ-Z2 "Restart runtime" killed the agent and never started it again

2026-08-15. Fixed, deployed, and verified against the live board (`192.168.2.103`).

## What was wrong

Two defects in `_restart_user_space_agent`, both invisible in the terminal panel.

**1. The restart command killed its own shell.** Stop and start were sent as one SSH command:

```
pkill -f "<venv>/bin/neurochip-pynq-agent" …; sleep 1; <setsid … launch …>
```

`ssh` runs that as `sh -c '<string>'`, so the remote shell's own command line contained the agent
path — as the pkill pattern *and* inside the launch command. `pkill -f` matches command lines, so it
killed the agent and the shell that was about to restart it. Proof: the launch redirects with
`>runtime.log`, which truncates on the spot, and the log fetched afterwards still ended with the old
process shutting down. The install script does the same `pkill` safely because it lives in a file —
its argv is just the script path.

**2. The restart downgraded the board to simulator.** The install script launches with
`$EFFECTIVE_PYNQ_PYTHON` (here the canonical `/usr/local/share/pynq-venv/bin/python`); the restart
hardcoded `<installRoot>/pynq-venv/bin/python`, the *isolated* venv the install only builds when the
canonical interpreter is absent. It was never created, so the restarted agent pointed at a missing
python, `pynq_runtime_available()` returned False, and preflight reported "Simulator fallback active".

Neither surfaced because `_run_ssh_detached` reported a non-zero exit with empty streams as success
(a SIGTERM'd shell exits 143 silently), leaving only a 120 s health timeout plus three 45 s retries
that read as a slow board.

## What changed

- `nmtk/launcher_control/pynq_service.py` — stop and start as two SSH calls; interpreter resolved
  from `install_status["effectivePynqPython"]`; a `pgrep` check after launch that fails in seconds
  when nothing started; `_run_ssh_detached` now names the exit code.
- `nmtk/launcher_control/provisioning_helpers.py` — new `build_pynq_agent_match_pattern` /
  `build_pynq_agent_stop_command`, which bracket the first character of the executable name so the
  pattern cannot match the text carrying it. The install script now uses the same helper. Mirrored
  in `Neurochip/neurochip/provisioning/pynq_agent_launch.py` for that module's own bundle builder.
- Corrected the user-space wording in the install status and the board-side preflight: the launcher
  *can* restart a user-space runtime; only surviving a board reboot needs privileges.

## State

Verified live after deploy — the launcher log now reads stop → launch → `running` → `agent health
check passed`, `curl http://192.168.2.103:8002/health` returns `{"status":"healthy"}`, and the board
reports `runtime_mode: hardware` where it previously reported simulator.

`tests/launcher_control/` 292 passed (was 289; four restart tests added, one updated). Neurochip
suite unchanged at 15 pre-existing failures.

## Follow-on: "no programmable devices found" — fixed in the same round

Once the agent came back, preflight failed further in with `PYNQ device probe failed: no
programmable devices found`. Not stale `zocl` (it was loaded). Two gaps in the user-space path,
found by probing the board:

1. **No XRT environment.** Unset, `pynq` warned *"No devices found, is the XRT environment
   sourced?"* and enumerated nothing. With `XILINX_XRT=/usr` it saw the device immediately. The
   systemd unit has always injected `XILINX_XRT`/`LD_LIBRARY_PATH`/`BOARD`; the stock image sets
   them in `/etc/profile.d/xrt_setup.sh`, which a detached `setsid sh -c` never sources, and the
   user-space launch command injected none of them. Now it does.
2. **No device-node permissions.** `/dev/dri/card0` is `root:video` and `renderD128` is
   `root:render`, both 0660; `xilinx` was in neither, so with XRT set the probe got as far as
   `RuntimeError: Could not open device with index '0'`. Nobody hit this while everything ran as
   root. `_ensure_pynq_device_group_access` now checks `id -nG` and, when needed, runs
   `sudo -S usermod -aG video,render <user>` using the board's stored password — which already
   authenticates every SSH call, so no new secret, and it travels on stdin rather than argv. It runs
   before the launch (membership only reaches new login sessions), during both provisioning and
   restart, and a failure warns rather than blocking the restart.

Verified: `id -nG` → `xilinx adm sudo video render`, `/dev/dri/renderD128` readable, and preflight
now clears the hardware probe.

## Still open: user-space always reports "degraded"

With the device working, preflight returns `degraded` purely because `install_mode == "user-space"`
([routers/pynq.py:462-467](Neurochip/neurochip/app/routers/pynq.py:462)), and
[setup_step.dart:1476-1478](neurocnl/frontend/lib/screens/studio/steps/setup_step.dart:1476) answers
that state with "Choose Restart runtime, then Check readiness" — a loop, because restarting cannot
change the install mode. `degraded` also covers simulator fallback, which genuinely cannot deploy, so
the two must not share a verdict: a user-space install whose hardware probe passes should report
`ok`, with the reboot caveat in the message. Needs a board-side change, so it reaches a board only on
reprovision.

## Follow-on 2: "does not fit the overlay" was a contract mismatch, not the network

The MNIST 784→256→10 network fits overlay-v2 comfortably (1050 neurons of 4096, 203k synapses of
262k, 3 layers of 4). `POST /api/neurocnl/deploy/pynq/network` was returning HTTP 500:

```
register_map must match the overlay manifest register map
```

`PynqRuntimeArtifact.validate_target` requires the artifact's `register_map` to equal the overlay
manifest's. The exporter built the artifact's from bare model defaults
(`PynqRegisterMap()` — `resolved_from_hwh: false`, every offset `None`) while the manifest carries
the offsets resolved from the built `.hwh`. The two matched only while the overlay was unbuilt; the
moment v2 supplied real offsets, every network was rejected. `_default_register_map()` in
`neurocnl/neurocnl/export/pynq_exporter.py` now derives from the manifest, which also makes the
artifact honest — the board drives the engine through those offsets, so shipping `None` could never
have run. Verified against the live backend: `support_state: exportable`, payload present.

The Neurochip-side twin (`test_pynq_compile.py`, `PYNQ_COMPILE_MANIFEST_MISMATCH`) is the same shape
in the opposite direction — the `DEFAULT_OVERLAY_MANIFEST` literal is unresolved while the exported
artifact reads the real file. That path is the Vivado compile service, not the deploy path, so it is
left to the separate task already filed.

## Follow-on 3: user-space no longer blocks Deploy

`canDeploy` requires `selectedBoard.isReady`, i.e. board state `ready`, but the board-side preflight
returned `degraded` for any user-space install even with a passing hardware probe — so Deploy could
never enable, and the app's advice for `degraded` ("Restart runtime, then Check readiness") could
never change the install mode. The probe passing is what "ready" means, so a user-space install whose
probe passes now returns `ok` with the reboot caveat in the message. Simulator fallback still returns
`degraded`. This runs on the board, so it reaches a board only via Install board runtime.

## Follow-on 4: the real blocker was the trained NIR, not the network

The app always passes the workspace's trained NIR to `/deploy/pynq/network` (`validate()` fetches it
first), which is why the endpoint succeeded under curl and failed in the app. With the artifact
attached it returned:

```
The trained NIR file could not be read as a NIR graph:
Type inference error: type mismatch: nir.Input_1.output: [[784]] -> nir.LIF_1.input: [[1]]
```

Decoding `model.nir` shows why: `Linear_1.weight (256,784)` and `Linear_2.weight (10,256)` are
correct trained tensors, but every LIF carries `tau`/`v_threshold`/`r`/`v_leak` of shape `(1,)`. CNL
states a neuron's parameters once for the layer, the NIR Exporter cell copies only `weight`/`bias`
onto the CNL-compiled graph and writes it, and NIR infers a layer's width from those arrays — so
each LIF reads back as one neuron wide and the graph fails its own type check on the first edge.

Fixed in `neurocnl/neurocnl/export/nir_shapes.py` (`neuron_widths` /
`broadcast_neuron_parameters`): widths come from the two shapes that really determine one — a port's
declared shape and a weight matrix's row count — and every one-element neuron parameter is repeated
to that width, with `input_type`/`output_type` refreshed so the type check sees it. Wired into both
ends: `load_trained_nir_graph` repairs and retries on a type mismatch (so artifacts already on disk
work without retraining), and the `nirExporter` notebook cell widens before `nir.write` so new
exports are well-formed. Five tests in `neurocnl/neurocnl/export/test_nir_shapes.py`.

Verified: the workspace's real `model.nir` now loads and type-checks.

## Still blocked: the deploy IR counts Linear nodes as layers

With the NIR readable, the same call now fails one step further on:

```
The trained NIR file holds 2 weight matrices but this network has 4 layers.
Deploying it needs 0×0 → 0×0 → 0×0 → 0×0; the file has:
nir.Linear_1 (256, 784), nir.Linear_2 (10, 256).
```

The network has two weight matrices. The workspace's own canonical IR folds `Linear` into the
connection (`lif_1 → lif_2`, `weights_shape (256, 784)`), but the IR the backend compiles from the
spec evidently does not: `_layer_connections` returns four population-to-population connections —
the `LIF → Linear` and `Linear → LIF` pairs — and `_expected_shape` reports `0×0` for each, meaning
those populations carry no size. Both halves need tracing: whether the deploy IR should fold Linear
into the connection weight, and why the populations come back sized 0.

## Follow-on 5: the deploy IR keyed populations by a name no connection uses

Traced. `_nir_native_records_to_deploy_ir` does fold `Linear` into a weighted connection — the IR was
never wrong about the topology. The dictionary key was:

```python
network.populations[name] = _build_nir_population_ir(record, sizes[name])   # name = "nir.LIF_1"
```

`PopulationIR.__post_init__` and `ConnectionIR.__post_init__` both run `normalize_identifier`, which
lower-cases. So connections carried `nir.lif_1` while the populations dict was keyed `nir.LIF_1`, and
every consumer reaches populations *through* a connection endpoint —
`ir.populations.get(connection.source)` returned `None` for all of them. Two consequences, both of
them the symptoms seen:

- `_is_port_population(None)` is false, so the input and output ports were never excluded and a
  two-matrix network was counted as **4 layers**.
- `_expected_shape` read `size` off `None`, so every layer measured **0×0**.

Fixed by keying on the built population's own normalised name
(`neurocnl/backend/app/services/neurocnl_bridge.py`). Three tests in
`neurocnl/backend/tests/test_deploy_ir_population_keys.py` pin it: every connection endpoint
resolves, ports are recognised through their connections, and layer shapes equal the declared weight
matrices.

## End state — the MNIST network deploys

`POST /api/neurocnl/deploy/pynq/network` with the workspace's spec and its trained NIR:

```
support_state : exportable_with_warnings
trained       : applied=true, 203264 non-zero from nir.Linear_1, nir.Linear_2 (2 layers)
summary       : 1050 neurons, 203264 synapses, 2 connections
payload layers: (784, 256), (256, 10)
warning       : 1421 of 203264 weights (0.7%) round to zero at 8-bit
```

The board reports `ready` / `ok` / `hardware`, so `canDeploy` is satisfied. The remaining warning is
genuine quantisation feedback, not a defect.

Suites: `tests/launcher_control/` 297 passed; `neurocnl/neurocnl/export/` 31 passed; the new
NIR-shape and deploy-IR tests pass. `neurocnl/neurocnl` has 11 failures that are red at HEAD
(nir_native_cnl round-trip, layer2 validator, sinabs runtime) and untouched by this work.
