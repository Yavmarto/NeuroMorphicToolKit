# CEL-238: Voyager SDK Phase 3 — Metis AIPU Hardware Runbook

**Date:** 2026-09-14  
**Parent:** [CEL-234](/CEL/issues/CEL-234) — Integrate Axelera Voyager SDK  
**Depends on:** [CEL-237](/CEL/issues/CEL-237) (Phase 2 compile — **done**), Metis board procurement (**blocked**)

## Status

| Gate | State |
|------|-------|
| Phase 1 CPU path ([CEL-236](/CEL/issues/CEL-236)) | Done — `op.onnx_model(provider='cpu')` |
| Phase 2 compile ([CEL-237](/CEL/issues/CEL-237)) | **Done** — `make voyager-compile-spike` → `yolov8n.axm` (~19 MB) |
| Metis hardware on a Linux host | **Blocked** — no board procured |
| Phase 3 AIPU inference | Waiting on hardware |

**Handoff artifact:** compile output from Phase 2 (`voyager-compile-out/yolov8n_axelera_model/yolov8n.axm`).

---

## Host Requirements

- Ubuntu 22.04+ native Linux (not macOS; not a plain Docker container)
- Python 3.10–3.13
- Metis board installed (PCIe or M.2), powered, visible in `lspci`
- `sudo` for `metis-dkms` driver install
- Network access to `software.axelera.ai` (PyPI + apt)

**Recommended target:** dev host `192.168.2.90` once a Metis card is installed — same box as Akida native service, but Metis uses its own driver/port space.

---

## Step 1 — Confirm hardware

```bash
lspci | grep -i axelera || lspci | grep -i metis
axdevice --pcie-scan
```

If nothing appears: check physical install, power, BIOS PCIe slot, then `axdevice --refresh` (up to 3 times).

---

## Step 2 — Install runtime + driver

### Option A — pip runtime then axdevice driver (recommended for SDK 1.6+)

```bash
python3 -m venv /opt/voyager-venv && source /opt/voyager-venv/bin/activate
pip install --no-cache-dir \
  --extra-index-url https://software.axelera.ai/artifactory/api/pypi/axelera-pypi/simple \
  axelera-rt axelera-devkit opencv-python-headless ultralytics

# Pin driver version to match SDK docs for your release
axdevice driver --install
```

### Option B — apt metis-dkms

```bash
sudo sh -c "curl -fsSL https://software.axelera.ai/artifactory/api/security/keypair/axelera/public | gpg --dearmor -o /etc/apt/keyrings/axelera.gpg"
sudo sh -c "echo 'deb [signed-by=/etc/apt/keyrings/axelera.gpg] https://software.axelera.ai/artifactory/axelera-apt-source ubuntu22 main' > /etc/apt/sources.list.d/axelera.list"
sudo apt-get update
sudo apt-get install -y linux-headers-$(uname -r) metis-dkms
sudo modprobe metis
```

Verify:

```bash
axdevice
```

Expected: at least one Metis device with firmware version listed.

---

## Step 3 — Compile artifact (if not already present)

On any Linux box with Docker:

```bash
make voyager-compile-spike
ls -lh voyager-compile-out/yolov8n_axelera_model/yolov8n.axm
```

---

## Step 4 — Run AIPU validation spike

On the **native Linux host with the board attached**:

```bash
make voyager-aipu-spike
# or: bash scripts/voyager_aipu_spike.sh ./voyager-compile-out
```

The script:

1. Fails fast with exit code 2 if no Metis device in `lspci`
2. Runs `op.load('.axm')` inference on `bus.jpg`
3. Runs the Phase 1 CPU ONNX baseline on the same image
4. Prints detection counts and wall-clock times for both paths

---

## Step 5 — Benchmark + decision

Record in this issue:

| Metric | CPU ONNX (Phase 1) | AIPU `.axm` (Phase 3) |
|--------|--------------------|------------------------|
| Wall time (ms) | | |
| Detections (bus.jpg) | 5 expected | |
| Throughput note | alpha CPU path | production target |

**Decision gate for [CEL-234](/CEL/issues/CEL-234):** wire `op.load` / `create_inference_stream()` into `workers/neurochip_hw/` only if AIPU speedup justifies the Linux-only runtime dependency.

---

## NMTK integration sketch (after benchmark)

1. Add optional `axelera` extra to `workers/neurochip_hw/pyproject.toml`
2. New route: load `.axm` from model registry, run Pipeline Builder or YAML pipeline
3. Do **not** bake Voyager into default `suite_api` image until decision gate passes
4. Keep compiler in CI (`make voyager-compile-spike`); runtime only on Metis-equipped hosts

---

## References

- [CEL-235 findings](./CEL-235-voyager-sdk-spike-findings.md) — CPU path + hardware blockers
- [CEL-237 findings](./CEL-237-voyager-compiler-phase2-findings.md) — `.axm` compile path
- Voyager SDK install: https://github.com/axelera-ai-hub/voyager-sdk/blob/latest/docs/user-guides/sdk-install.md
- `axdevice` reference: https://github.com/axelera-ai-hub/voyager-sdk/blob/latest/docs/reference/tools/axdevice.md
