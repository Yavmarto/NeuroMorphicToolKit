# PYNQ-Z2 Deploy Troubleshoot — April 2026
Summary of the multi-day effort to fix `PynqDeployException: Overlay loading failed: No Devices Found` when triggering **Provision Runtime / Deploy** from the Pynq Deployment screen against board `192.168.2.99` (Pynq-Z2, `fe37de70-55ce-4357-8a28-ae941b5aba1d`).
Outcome: **deploy returns HTTP 200**. Full MMIO write succeeds via the isolated-interpreter subprocess worker running under `/usr/local/share/pynq-venv/bin/python`.
## Initial failure

```text
PynqDeployException: Deploy failed
HTTP 500 from POST http://192.168.2.99:8002/hardware/pynq/deploy
body: {"detail":{"detail":"Overlay loading failed: No Devices Found",
        "error_code":"OVERLAY_LOAD_FAILED"}}
```

The failure turned out to be **five stacked problems** that all had to be fixed before deploy could succeed. Each layer was masking the next.

## Layer 1 — `zocl` kernel module cached a stale "no device" enumeration
Symptom: `xbutil examine` reported no devices, even with XRT 2.17 present under `/usr/lib/libxrt_*` and the `pynq-venv` intact.
Root cause: the board had dropped SSH mid-deploy; on recovery `zocl` was loaded but its enumeration state was stale. The userspace pynq process inherited an empty `Device.devices` cache.
Fix (applied manually on the board):

```bash
sudo rmmod zocl 2>/dev/null || true
sudo modprobe zocl
ls -l /dev/dri/             # /dev/dri/card0 + renderD128 reappear
xbutil examine              # Pynq-Z2 now listed, Device Ready: Yes
```

After this, an interactive `/usr/local/share/pynq-venv/bin/python -c "import pynq; print(pynq.Device.devices)"` returned `[<EmbeddedDevice ...>]`. But the agent service still returned HTTP 500 — because the agent's own Python process had already been launched before the reload and cached the empty device list.

Restarting the agent was required:
```bash
sudo systemctl restart neurochip-pynq-agent.service
```

## Layer 2 — Agent was loading `Overlay()` in-process using the wrong pynq
After restart, deploy still failed with `OVERLAY_LOAD_FAILED: No Devices Found`. The journal traceback:

```text
File ".../neurochip-pynq-agent/venv/lib/python3.10/site-packages/neurochip/
      app/services/pynq_backend.py", line 115, in load_overlay
    self.overlay = Overlay(str(path))
  File ".../pynq/pl_server/device.py", line 71, in active_device
    raise RuntimeError("No Devices Found")
```

Two compounding issues:

1. The **installed `neurochip` wheel on the board was old** (line 115 vs the current source tree's ~line 276). The installed copy predated the `NEUROCHIP_PYNQ_PYTHON` / isolated-worker feature entirely, so it always imported `pynq` into the agent's own Python and called `Overlay()` in-process.
2. The **agent venv's `pynq` came from plain `pip install pynq`** on PyPI, which does not include the Xilinx-specific `pyxrt` / device-tree glue required on a real Zynq board.

Even if we set `NEUROCHIP_PYNQ_PYTHON=/usr/local/share/pynq-venv/bin/python` via a systemd drop-in, the old wheel ignored it. So the environment variable was inert.

## Layer 3 — Installing into the canonical pynq-venv broke pynqmetadata

First attempt at a workaround: install the `neurochip` wheel *into* `/usr/local/share/pynq-venv` and point `ExecStart` there so the agent itself ran under the canonical pynq Python.

This **contaminated the canonical venv**:

```text
pynqmetadata 0.1.8 requires pydantic==1.9.1,
but you have pydantic 2.13.2 which is incompatible.
```

`neurochip` depends on `fastapi` which forces `pydantic >=2`, while `pynqmetadata` (used by pynq's `Overlay()` to parse HWH files) hard-pins `pydantic==1.9.1`. **The two dependency sets are fundamentally incompatible** — they cannot share a venv. The SSH session also dropped immediately after the `pip install`, because pydantic/anyio/typing-extensions were swapped under other live processes.

Recovery (ran on the board):

```bash
sudo /usr/local/share/pynq-venv/bin/pip uninstall -y \
  neurochip fastapi fastapi-cli fastapi-cloud-cli starlette \
  pydantic pydantic-core pydantic-extra-types pydantic-settings \
  anyio typing-inspection
sudo /usr/local/share/pynq-venv/bin/pip install \
  'pydantic==1.9.1' 'anyio<4' --force-reinstall --no-deps
```

Verification after recovery:

```text
pynq 3.1.1 - pynqmetadata 0.1.8
devices: [<pynq.pl_server.embedded_device.EmbeddedDevice object at 0xb67a62e0>]
```

Canonical venv restored.
Architectural conclusion: the agent's FastAPI stack and the canonical pynq stack **must live in separate venvs**. That is exactly what the `NEUROCHIP_PYNQ_PYTHON` subprocess-worker pattern exists for. The correct fix is to install an agent wheel that honors that env var into the agent venv only.

## Layer 4 — Force-reinstall fresh agent wheel, correct systemd drop-in

```bash
cd /NeuroMorphicToolKit/Neurochip
poetry build -f wheel
scp dist/neurochip-0.6.0-py3-none-any.whl xilinx@192.168.2.99:/tmp/
```

On the board:

```bash
sudo /home/xilinx/.local/share/neurochip-pynq-agent/venv/bin/pip install \
  --force-reinstall --no-deps /tmp/neurochip-0.6.0-py3-none-any.whl

# Confirm the new wheel actually has the subprocess-worker codepath
grep -n "_pynq_python is not None" \
  /home/xilinx/.local/share/neurochip-pynq-agent/venv/lib/python3.10/\
site-packages/neurochip/app/services/pynq_backend.py
# -> prints matches at lines 267, 320, 384
```

Systemd drop-in (only the env var — keep `ExecStart` pointing at the agent venv):

```ini
# /etc/systemd/system/neurochip-pynq-agent.service.d/override.conf
[Service]
Environment=NEUROCHIP_PYNQ_PYTHON=/usr/local/share/pynq-venv/bin/python
```

Restart + preflight returned `HTTP 200`. Deploy still failed, but the traceback changed — the subprocess worker was now spawned. Progress:

```text
Overlay assets validated for isolated PYNQ runtime at
  /usr/local/share/pynq-venv/bin/python
...
PynqRuntimeError: PYNQ device probe failed: no programmable devices found
```

The subprocess was running but `Device.devices` was empty inside it.

## Layer 5 — Subprocess worker missing XRT / BOARD / LD_LIBRARY_PATH env

`systemd` does not source `/etc/profile.d/*.sh`, so the agent service (and the worker subprocess it spawns) never inherited what an interactive `xilinx` login shell gets. On this PYNQ image:

```text
/etc/profile.d/xrt_setup.sh  -> export XILINX_XRT=/usr
/etc/profile.d/pynq_venv.sh  -> source /usr/local/share/pynq-venv/bin/activate
/etc/profile.d/boardname.sh  -> export BOARD=Pynq-Z2
```

Critically, `XILINX_XRT=/usr` (not `/opt/xilinx/xrt`). XRT libs live at `/usr/lib/libxrt_core.so*`. I initially guessed `/opt/xilinx/xrt` which does not exist on this image, producing:

```text
PYNQ device probe failed: No such library '/opt/xilinx/xrt/lib/libxrt_core.so.2'
```

After correcting the override:

```ini
# /etc/systemd/system/neurochip-pynq-agent.service.d/override.conf
[Service]
Environment=NEUROCHIP_PYNQ_PYTHON=/usr/local/share/pynq-venv/bin/python
Environment=XILINX_XRT=/usr
Environment=LD_LIBRARY_PATH=/usr/lib:/usr/local/lib
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=BOARD=Pynq-Z2
```

The subprocess worker now saw the device and `Overlay(path)` returned successfully. Deploy failure changed again — this time a real runtime error at the MMIO stage.

## Layer 6 — Register map off-by-one vs SNN IP window

```text
MMIO write failed: index 16384 is out of bounds for axis 0 with size 16384
```

Probed the HWH with:

```bash
sudo env XILINX_XRT=/usr LD_LIBRARY_PATH=/usr/lib:/usr/local/lib BOARD=Pynq-Z2 \
  /usr/local/share/pynq-venv/bin/python /tmp/probe_ip.py
```

Result:

```text
snn_engine_0   phys=0x40000000  range=0x00010000
axi_dma_0      phys=0x41e00000  range=0x00010000
```

The SNN IP's MMIO window is exactly `0x10000` bytes = 16384 uint32 words (valid byte offsets `0x0000 … 0xFFFC`). The default `weight_base_offset = 0x1_0000` is **one byte past** the window. The first weight write landed at `array[16384]` on an array of size 16384.

The deploy router validates the request's `register_map` against the installed overlay manifest and rejects any mismatch:

```python
# neurochip/app/routers/pynq.py:252-260
resolved_register_map = _resolved_register_map(request)
if resolved_register_map != manifest.register_map.model_dump():
    raise ConfigurationError(
        "register_map does not match the installed overlay contract",
        error_code="OVERLAY_REGISTER_MAP_MISMATCH",
    )
```

So overriding via the request alone is impossible — the manifest on the board is authoritative. Patched the board manifest in place (original saved to `.bak`):

```bash
sudo cp /home/xilinx/.local/share/neurochip-pynq-agent/overlays/\
overlay_manifest.json{,.bak}

sudo /usr/local/share/pynq-venv/bin/python - <<'PY'
import json, pathlib
p = pathlib.Path('/home/xilinx/.local/share/neurochip-pynq-agent/overlays/overlay_manifest.json')
m = json.loads(p.read_text())
m['register_map']['weight_base_offset'] = 0x1000
if 'weight_layout' in m and 'base_offset' in m['weight_layout']:
    m['weight_layout']['base_offset'] = 0x1000
p.write_text(json.dumps(m, indent=2, sort_keys=True))
PY

sudo systemctl restart neurochip-pynq-agent.service
```

Deploy:

```text
POST /hardware/pynq/deploy
{"status":"success","message":"Overlay loaded and configured successfully."}
HTTP 200  duration=25.1376s
```

**Pipeline is end-to-end green.** The Pynq Deployment screen in the desktop app now succeeds against this board.

## Side patch landed in source (Neurochip branch `dev`)
While investigating Layer 2, a preventative patch was added so future provisions auto-detect the canonical PYNQ runtime instead of re-creating a broken isolated venv with `pip install pynq`:
- `Neurochip/neurochip/provisioning/pynq_agent_bundle.py` — install script now probes `CANONICAL_PYNQ_PYTHON=/usr/local/share/pynq-venv/bin/python` via `import pynq; import pyxrt` and uses it directly; falls back to isolated venv otherwise. `EFFECTIVE_PYNQ_PYTHON` + `PYNQ_RUNTIME_SOURCE` are recorded in `install-status.json`. The systemd unit's `NEUROCHIP_PYNQ_PYTHON` is rewritten via `sed` to the effective interpreter before install.
- `Neurochip/neurochip/tests/test_pynq_agent_bundle.py` — assertions for the new install-script blocks.
- `Neurochip/docs/neurochip/pynq_z2_deployment_guide.md` — documented the detection and the `CANONICAL_PYNQ_PYTHON` override env.

`poetry run pytest neurochip/tests/test_pynq_agent_bundle.py`, `ruff check`, `mypy` are clean on the files touched.

This patch alone is not sufficient — see follow-ups #2 and #3 below.

## Final known-good state on the board
- systemd unit: `/etc/systemd/system/neurochip-pynq-agent.service` (unchanged base) + drop-in `override.conf` with `NEUROCHIP_PYNQ_PYTHON`, `XILINX_XRT=/usr`, `LD_LIBRARY_PATH`, `PATH`, `BOARD=Pynq-Z2`.
- Agent wheel `neurochip-0.6.0` installed into `/home/xilinx/.local/share/neurochip-pynq-agent/venv`; has `_pynq_python is not None` subprocess-worker branches at lines 267 / 320 / 384 of `pynq_backend.py`.
- Canonical venv `/usr/local/share/pynq-venv` restored (`pydantic==1.9.1`, `anyio==3.7.1`, `pynq 3.1.1`, `pynqmetadata 0.1.8`). No fastapi pollution.
- Overlay manifest `/home/xilinx/.local/share/neurochip-pynq-agent/overlays/overlay_manifest.json` patched: `register_map.weight_base_offset = 0x1000`, `weight_layout.base_offset = 0x1000`. Original preserved as `.bak`.
- `zocl` loaded, `/dev/dri/card0` and `/dev/dri/renderD128` present.
# Permanent follow-ups
These exist because the fix on the board is manual. A future **Provision Runtime** / **Install Overlay** click from the app *will revert* several of these unless the underlying code is updated. They are ordered by risk: items 1–3 must be done before the next provision, item 4 is the correctness fix, item 5 is cleanup.

## Follow-up 1 — Restart the Mac launcher control process so the canonical-PYNQ-detection patch is actually used
Why: The launcher (`nmtk/launcher_control/server.py`, the process that handles `/api/launcher/pynq/boards/.../deploy` and the **Provision Runtime** action) imports `neurochip.provisioning.build_pynq_agent_bundle` once at startup and caches it. My patch to `Neurochip/neurochip/provisioning/pynq_agent_bundle.py` is therefore **not live** in any running launcher process. Any `Provision Runtime` click today still generates the *old* install script.
How to execute:
1. Stop the launcher. Depending on how it was started:
   ```bash
   pkill -f launcher_control_service || true
   # or, if started via a systemd/launchd/tab-config manager, stop it through that surface
   ```
2. Restart it through the normal dev flow. The dev script is `scripts/run_dev.sh`; the launcher-only entry point is `scripts/launcher_control_service.py`. After restart, `python3 scripts/launcher_control_service.py --doctor --json` should confirm it is live.
3. Sanity test: call **Provision Runtime** against a fresh test board (or a cloned VM image) and confirm `/tmp/pynq-agent-bundle-*/install-pynq-agent.sh` on the board contains the `detect_pynq_runtime` function and `CANONICAL_PYNQ_PYTHON=${CANONICAL_PYNQ_PYTHON:-/usr/local/share/pynq-venv/bin/python}` line. If those are absent, the wrong launcher is still running.
No code changes required for this follow-up. It is purely operational.
## Follow-up 2 — Add XRT / BOARD / LD_LIBRARY_PATH environment to the systemd unit emitted during provisioning
Why: Follow-up 1 makes the install script pick the right Python. It does **not** fix the `systemd` environment problem from Layer 5. The emitted unit currently only sets `NEUROCHIP_PYNQ_PYTHON` and a handful of `NEUROCHIP_PYNQ_*` vars. Without `XILINX_XRT`, `LD_LIBRARY_PATH`, `PATH`, `BOARD`, the worker subprocess cannot open the device. A fresh provision on a fresh board will hit `PYNQ_DEVICE_PROBE_FAILED` again.
How to execute:
1. Edit `Neurochip/neurochip/provisioning/pynq_agent_bundle.py` in `_systemd_unit_text(...)`. After the existing `Environment=NEUROCHIP_PYNQ_PYTHON=...` line, add four more lines **above** `ExecStart=`:
   ```python
   (f"Environment=XILINX_XRT={xilinx_xrt_path}",)
   (f"Environment=LD_LIBRARY_PATH={xilinx_xrt_path}/lib:/usr/lib:/usr/local/lib",)
   (
       f"Environment=PATH={xilinx_xrt_path}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
   )
   (f"Environment=BOARD={board_name}",)
   ```
2. Plumb `xilinx_xrt_path` and `board_name` through `_systemd_unit_text` and `build_pynq_agent_bundle`. Defaults:
   - `DEFAULT_XILINX_XRT_PATH = "/usr"` (this PYNQ image puts libs in `/usr/lib`).
   - `DEFAULT_BOARD = "Pynq-Z2"`.
   Expose both as kwargs on `build_pynq_agent_bundle(...)` so the launcher can override per board record. The `PynqBoard` record already carries board metadata; plumb it through `nmtk/launcher_control/server.py::_build_local_pynq_bundle` similarly to how `overlay_dir` is passed today.
3. Inside `_install_script_text` add a runtime detection step before `Staging systemd unit` so the `XILINX_XRT` default is only committed if the path actually exists; if it does not, fall back to sourcing `/etc/profile.d/xrt_setup.sh` at agent start via a wrapper `ExecStart=/bin/bash -lc 'exec $AGENT_VENV_PATH/bin/neurochip-pynq-agent'`. This is defensive against SD-card image drift.
4. Update the test `neurochip/tests/test_pynq_agent_bundle.py::test_build_pynq_agent_bundle_writes_expected_files`:
   - `assert "Environment=XILINX_XRT=/usr" in systemd_unit`
   - `assert "Environment=BOARD=Pynq-Z2" in systemd_unit`
   - `assert "Environment=LD_LIBRARY_PATH=/usr/lib" in systemd_unit`
5. Validate: `cd Neurochip && PYTHONPATH=.. poetry run pytest neurochip/tests/test_pynq_agent_bundle.py && poetry run ruff check . && poetry run mypy .` must stay green.
6. After merging, execute follow-up 1 again so the new code is live in the launcher.
Acceptance: on a clean provision, `systemctl show neurochip-pynq-agent.service -p Environment` lists `XILINX_XRT`, `LD_LIBRARY_PATH`, `BOARD`, and the hands-off `/hardware/pynq/deploy` round-trip succeeds with zero manual overrides.

## Follow-up 3 — Fix the overlay register-map contract so the staged manifest is not born broken
Why: The manifest patched in place on the board (`weight_base_offset: 0x10000 -> 0x1000`) is what made deploy work. `DEFAULT_REGISTER_MAP` in `Neurochip/neurochip/contracts/pynq_runtime_artifact_contract.py` still has `0x1_0000`. Any future `Install Overlay` action that re-stages an upstream manifest generated from this constant, or any fresh provision of a new board, will overwrite `overlay_manifest.json` and re-break the deploy at the MMIO stage. **The board-side `.bak` file does not protect against this.**

Constraint from `Neurochip/AGENTS.md`: *"Any change to deploy manifests, exported artefacts, serial-flash behavior, or target metadata requires reading the consumer first: neurocnl, Neuro-Dream-Hand, or Neurohub."* This follow-up touches `MAX_SYNAPSES` which is consumed by all three.

How to execute:
1. Read the consumers first. Grep in order and record in the PR description what you found:
   - `neurocnl` — search for `MAX_SYNAPSES`, `weight_base_offset`, `DEFAULT_REGISTER_MAP`, `PynqRegisterMapContract`, `weight_layout`, and the generator that writes `pynq_deploy/register_map.json`. Confirm whether the generator assumes 1-byte stride (the current `weight_layout.format = "int8_dense_row_major"`, `stride_bytes = 1`) or 4-byte stride (the current runtime worker in `pynq_worker.py` writes `struct.pack("<f", weight)` — float32). These disagree **today**, regardless of this follow-up.
   - `Neuro-Dream-Hand` — search for any synapse-count validation against `MAX_SYNAPSES`.
   - `Neurohub` — search for any contract replication of `pynq_runtime_artifact_contract.py` (e.g. `docs/Opus-dev-pipeline/neurohub/contracts/orchestration_contracts.py` already mentions overlay payloads).
2. Decide stride + size. Two consistent options; pick one and update **all** of code, contract, generator, and manifest generator:
   - **Option A (float32 stride=4)**: keep the runtime worker as-is, set `weight_layout.format = "float32_dense_row_major"`, `weight_layout.stride_bytes = 4`. With SNN IP window = `0x10000` and a non-zero `weight_base_offset`, `MAX_SYNAPSES <= (0x10000 - weight_base_offset) / 4`. For `weight_base_offset = 0x1000`, max fits 15360 weights. Recommend `MAX_SYNAPSES = 15360`.
   - **Option B (int8 stride=1)**: keep the contract as-is, change the runtime worker in `Neurochip/neurochip/app/services/pynq_worker.py::_configure_hardware` and the in-process path in `Neurochip/neurochip/app/services/pynq_backend.py::configure` to write a single byte per weight. With `weight_base_offset = 0x1000`, `MAX_SYNAPSES <= 0x10000 - 0x1000 = 61440`. Recommend `MAX_SYNAPSES = 61440`.
   Option A is the smaller code change but reduces the neuron/synapse budget. Option B preserves the advertised capacity but changes serialization for every consumer that writes `weights.bin` today. Choose in consultation with the `neurocnl` maintainer; document the decision as a new ADR under `Neurochip/docs/ADR-claude/` (per AGENTS.md: ADRs are append-only).
3. Apply the contract edit in `Neurochip/neurochip/contracts/pynq_runtime_artifact_contract.py`:
   - `DEFAULT_REGISTER_MAP["weight_base_offset"]` from `0x1_0000` to `0x1000`.
   - `DEFAULT_WEIGHT_LAYOUT["base_offset"]` from `0x1_0000` to `0x1000`.
   - `DEFAULT_WEIGHT_LAYOUT["format"]` and `stride_bytes` per the chosen option.
   - `MAX_SYNAPSES` per the chosen option. **Also** update `DEFAULT_WEIGHT_LAYOUT["max_entries"]` because it references `MAX_SYNAPSES`.
   - If changing `PynqRegisterMapContract` field defaults, also adjust the validator if needed. The 4-byte alignment validator stays valid for both options.
4. Update the contract tests. Search for `MAX_SYNAPSES`, `weight_base_offset`, `0x1_0000`, `0x10000`, `65536` across `Neurochip/neurochip/tests/` and fix every assertion.
5. Update the consumer sides identified in step 1. In `neurocnl`, the `PynqNetworkPayloadContract.validate_pynq_limits` already delegates to `MAX_SYNAPSES`, so most validations adjust automatically — but any test that hard-codes `65536` must change.
6. Regenerate the staged overlay manifest:
   - Source of truth: `Neurochip/overlay_staging/pynq_z2/overlay_manifest.json`. If this file is checked in and contains the broken register_map, update it in the same PR. If it is externally produced (Vivado flow), update the tool that produces it and re-run; commit the regenerated JSON.
   - Whoever builds the overlay: verify against the HWH using the probe `for name, ip in ol.ip_dict.items(): print(name, hex(ip['phys_addr']), hex(ip['addr_range']))` — `weight_base_offset` must satisfy `0 < weight_base_offset` and `weight_base_offset + stride * max_entries <= addr_range` for the SNN IP.
7. Validate locally:
   - `cd Neurochip && PYTHONPATH=.. poetry run pytest tests/`
   - `poetry run ruff check .`
   - `poetry run mypy .`
   - `cd frontend && flutter test` (per Neurochip/AGENTS.md, hardware-affecting changes need verification)
   - From repo root: `python3 -m pytest tests/integration/test_cross_module.py` and `python3 -m pytest tests/integration/test_teensy_e2e.py` per CODING_STYLE_GUIDE.md.
8. Post-merge: on the Pynq-Z2 board, remove the board-local hack once a fresh `Install Overlay` has landed the corrected manifest:
   ```bash
   sudo diff /home/xilinx/.local/share/neurochip-pynq-agent/overlays/overlay_manifest.json \
             /home/xilinx/.local/share/neurochip-pynq-agent/overlays/overlay_manifest.json.bak
   # Once the staged manifest has the correct 0x1000 offset,
   # the in-place patch is no longer needed. Delete the .bak only after verification.
   ```

Acceptance: provisioning a fresh board + installing overlay from the staged package + deploying with an empty request body returns HTTP 200 with no manifest hand-patching, and none of `neurocnl`'s or `Neuro-Dream-Hand`'s synapse-bound validators reject previously-valid networks without an intentional size bump.

## Follow-up 4 — Make the deploy router surface the underlying XRT/worker error distinctly
Why: Throughout this investigation the single string `Overlay loading failed: No Devices Found` masked at least four *different* failure modes (stale zocl, missing wheel feature, wrong venv's pynq, missing XRT env, register-map off-by-one). The router collapses the subprocess worker's error_code into a generic `OVERLAY_LOAD_FAILED` 500. We can decompose.

How to execute:
1. In `Neurochip/neurochip/app/services/pynq_worker.py::_load_hardware`, the `Device.devices` probe already raises `PYNQ_DEVICE_NOT_FOUND` / `PYNQ_DEVICE_PROBE_FAILED` *before* calling `Overlay`. Keep that structure. But when `Overlay(path)` itself raises with the literal text `No Devices Found`, re-classify to `PYNQ_DEVICE_PROBE_FAILED` rather than `OVERLAY_LOAD_FAILED`, because semantically the device was not found — the overlay file was fine.
2. In `Neurochip/neurochip/app/services/pynq_backend.py::_run_worker`, preserve the worker's `error_code` verbatim instead of remapping based on string prefix. The current prefix-matching throws away information.
3. In `Neurochip/neurochip/app/routers/pynq.py::_pynq_error_to_http`, add an explicit HTTP status mapping: `PYNQ_DEVICE_NOT_FOUND` → 503 (service unavailable), `OVERLAY_REGISTER_MAP_MISMATCH` → 422 (already), `MMIO_WEIGHT_OVERFLOW` → 413, `MMIO_WRITE_FAILED` → 500, etc.
4. Add tests in `Neurochip/neurochip/tests/test_pynq_backend.py::TestPynqRouter` that a worker error with `error_code="PYNQ_DEVICE_NOT_FOUND"` propagates as HTTP 503 with the original detail text intact.
5. Update the Dart-side error taxonomy in `nmtk_ui_core/lib/models/pynq_deployment_model.dart` and `nmtk/neuro_toolkit/lib/providers/pynq_deploy_provider.dart` to distinguish `PYNQ_DEVICE_NOT_FOUND` (operator can re-run `zocl`/restart agent) from `OVERLAY_LOAD_FAILED` (operator must re-check the bitstream / HWH).

Acceptance: a future occurrence of stale `zocl` / missing XRT env yields a distinct error code + suggested remediation in the launcher UI, so a subsequent debugging session does not spend a day ruling out overlay-asset problems.

## Follow-up 5 — Clean up board-local workarounds after follow-ups 1–3 land
Why: The `overlay_manifest.json.bak` and the hand-written `override.conf` on `192.168.2.99` will start to drift from source of truth the moment follow-ups 1–3 are live in provisioning. Keep the board clean.

How to execute (on the Pynq-Z2 board, after verifying follow-up 3 landed and a fresh provision works):
```bash
# 1. Confirm the new provisioning flow wrote identical env + manifest
sudo systemctl show neurochip-pynq-agent.service -p Environment --no-pager
sudo diff /home/xilinx/.local/share/neurochip-pynq-agent/overlays/overlay_manifest.json \
          /home/xilinx/.local/share/neurochip-pynq-agent/overlays/overlay_manifest.json.bak

# 2. Drop the local override only if the base unit now contains the same values
sudo rm /etc/systemd/system/neurochip-pynq-agent.service.d/override.conf
sudo rmdir /etc/systemd/system/neurochip-pynq-agent.service.d 2>/dev/null || true
sudo systemctl daemon-reload
sudo systemctl restart neurochip-pynq-agent.service

# 3. Remove the manifest backup once deploy still passes with the staged manifest
sudo rm /home/xilinx/.local/share/neurochip-pynq-agent/overlays/overlay_manifest.json.bak

# 4. Final smoke test
curl -sS -X POST http://127.0.0.1:8002/hardware/pynq/deploy \
  -H 'Content-Type: application/json' \
  -d '{"weights":[0.1,0.2,0.3,0.4],"config":{"threshold":1.0}}' \
  -w "\nHTTP %{http_code}\n"
```

Acceptance: the board has zero local modifications, and `POST /hardware/pynq/deploy` still returns HTTP 200.
