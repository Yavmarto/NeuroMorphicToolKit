# Akida Workflow — Release Readiness Notes

Status: **Early usable** (scaffold export + optional SDK deployment via simulator)

---

## What this workflow does today

| Capability | Status |
|---|---|
| Parse and validate a CNL spec for Akida constraints | ✅ |
| Report exportability verdict (scaffold / unsupported + reasons) | ✅ |
| Generate a MetaTF scaffold ZIP (weights, model config, manifest, README) | ✅ |
| Map via Akida SDK on real hardware (AKD1000 or attached device) | ✅ when SDK installed |
| Fallback to in-process LIF simulator when SDK is absent (CI / local dev) | ✅ |
| Show topology verdict (faithful / approximate) and constraint warnings | ✅ |
| Colour-coded UI (indigo = scaffold, green = SDK-deployed, red = unsupported) | ✅ |
| Reject unsupported networks with machine-readable rejection codes | ✅ |

---

## What it does NOT do yet

| Capability | Note |
|---|---|
| Neurobench benchmark verification | UI toggle exists but is disabled — requires Neurobench service on port 8003 |
| Akida 2 block-type hints in generated script | Validator + mapper support Akida 2 semantics; generator emits `FullyConnected` only |
| Recurrent / branching topology support | Validator correctly rejects these; `mapped_network` will be null in the response |

---

## Known limitations

- **Topology must be faithful feed-forward.** The mapper requires a strict sequential path. Branching or recurrent networks are correctly rejected and the deploy button is disabled.
- **Hardware limits (Akida 1):** ≤ 1 200 000 total neurons; ≤ 256 neurons per neuronal package (NP); ≤ 80 cores; weight bit-width must be 1, 2, or 4.
- **macOS SDK:** The BrainChip Akida Python SDK is not available on macOS. The in-process simulator runs automatically when the SDK is absent. The generated ZIP package is valid for SDK use on Linux / Windows.

---

## Deployment tiers

```
UNSUPPORTED          — one or more hardware constraints violated
                       deploy button disabled, rejection list shown

EXPORTABLE_SCAFFOLD  — all constraints met (topology faithful)
                       ZIP generated without Akida SDK (offline)
                       mapped_network returned in NeuroCNL response

EXPORTABLE_SCAFFOLD  — constraints met but near capacity thresholds
_WITH_WARNINGS         or topology is approximate; amber warning shown

SDK_DEPLOYABLE       — scaffold succeeded AND model mapped via Akida
                       SDK (hardware or AKD1000 simulator)
```

---

## Manual acceptance — checkpoint A3

Run these steps to verify the end-to-end workflow before releasing:

1. Start backends:
   ```
   cd neurocnl && uvicorn backend.app.main:app --port 8000
   cd Neurochip && uvicorn neurochip.app.main:app --port 8002
   ```

2. **Unsupported case** — POST a spec with >1 200 000 neurons to
   `http://localhost:8000/api/deploy/akida/network`.
   Expected: `support_state=unsupported`, `rejections` non-empty,
   `mapped_network=null`.

3. **Scaffold case** — POST a valid small spec (e.g. two populations,
   one connection, 4-bit weights).
   Expected: `support_state=exportable_scaffold`,
   `mapped_network` dict present, `topology_verdict=faithful`.

4. **Package download** — in NMTK launcher open **Akida Deploy**, paste
   the valid spec, click **Check Readiness**, then **Download Scaffold Package**.
   Expected: `akida_deploy.zip` saved to Documents; no 422 errors.

5. **Unsupported deploy button** — paste a spec with recurrent connections.
   Expected: verdict shows unsupported, deploy button is disabled.

6. **Scaffold-only poll** — when running without Akida SDK, confirm the
   deployment status card resolves to done within ~5 seconds (poll terminates
   on `constructed` → mapped state).

7. **Neurobench toggle** — confirm the switch is visually disabled with the
   "not yet available" label.

---

## Running Python tests

```bash
cd neurocnl
pytest neurocnl/neurocnl/mapping/test_akida_mapper.py -v
pytest neurocnl/neurocnl/contracts/test_akida_deployment_contract.py -v
pytest neurocnl/neurocnl/layers/test_akida_validator.py -v
```
