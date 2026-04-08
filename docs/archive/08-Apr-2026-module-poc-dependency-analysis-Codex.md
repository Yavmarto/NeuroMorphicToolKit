# Module PoC and Dependency Analysis - 08-Apr-2026

**Analysis Date:** 08-Apr-2026
**Agent Assessor:** Codex
**Companion Audit:** `docs/archive/08-Apr-2026-status-Codex.md`

---

## 1. Executive Answer

### Easiest module to get to PoC
**Neurobench**

Why:
- The 08-Apr-2026 audit rates it at **90% readiness**, the highest among the audited modules.
- The audit explicitly calls it the **best current module**.
- Its backend is real rather than stub-only.
- `mypy --strict` passes cleanly, which reduces cleanup overhead before demoing or extending it.

### Best module to carry beyond PoC with the least runtime coupling
**Neurohub**

Why:
- The 08-Apr-2026 audit rates it at **88% readiness**.
- Its README states that it has **no runtime dependency on other NMTK services**.
- Other modules may call Neurohub to import or publish artefacts, but Neurohub does not depend on them to function.

### Most strategically central module
**neurocnl**

Why:
- It is not the absolute easiest path to a standalone PoC, but it is the most important dependency hub.
- Multiple modules rely on it for parsing, validation, simulation, export, or spike-pipeline integration.
- If the goal is to unlock several other modules rather than land the fastest standalone demo, `neurocnl` is the highest-leverage choice.

---

## 2. Recommended Ranking

### Best for fastest credible PoC
1. **Neurobench**
2. **Neurohub**
3. **Neurosim**
4. **neurocnl**

### Best for long-term strategic leverage
1. **neurocnl**
2. **Neurohub**
3. **Neurobench**
4. **Neurochip**

### Not recommended as the first PoC target right now
- **Neurosense**: blocked by unresolved merge conflicts in runtime code and tests.
- **Neurochip**: large typing debt and partial `501` behavior when the Akida SDK is absent.

---

## 3. Module-by-Module Read

### Neurobench
**Assessment:** Best immediate PoC target.

Signals:
- Audit readiness: **90%**
- Backend is implemented and not stub-only.
- Frontend is analyzer-clean.
- Strict mypy passes.

Interpretation:
- This is the cleanest path to a demoable, defensible module with low stabilization effort.

### Neurohub
**Assessment:** Best independent product candidate beyond PoC.

Signals:
- Audit readiness: **88%**
- Explicitly independent at runtime.
- Other modules consume it; it does not consume them.

Interpretation:
- This is the safest module to mature in parallel without waiting on the rest of the suite.

### neurocnl
**Assessment:** Strong module and the key dependency hub.

Signals:
- Audit readiness: **86%**
- Real mixed backend/frontend implementation.
- Used directly or indirectly by several other modules.

Interpretation:
- Best target if the goal is platform leverage rather than the fastest isolated PoC.

### Neurosim
**Assessment:** Close to ready, but somewhat dependent on `neurocnl`.

Signals:
- Audit readiness: **84%**
- Only 2 strict-mypy errors remain.
- Spec states that the backend imports `neurocnl` directly for simulation.

Interpretation:
- Good second-wave target after `neurocnl` or alongside it, but not as independent.

### Neuro-Dream-Hand
**Assessment:** Strong domain module, but more environment-heavy.

Signals:
- Audit readiness: **81%**
- Good implementation depth.
- Depends on `neurocnl` and also requires MuJoCo, which increases setup and demo friction.

Interpretation:
- Good for a compelling demo in a robotics context, but not the easiest general PoC path.

### Neurochip
**Assessment:** Valuable integrator, but not the easiest path.

Signals:
- Audit readiness: **70%**
- Broad API surface is real.
- Akida routes can still return `501` when the SDK is unavailable.
- Repo audit reports **370 strict-mypy errors**.

Interpretation:
- Important long-term, but too much quality debt remains for it to be the easiest first PoC.

### Neurosense
**Assessment:** Not the first target right now.

Signals:
- Audit readiness: **52%**
- Merge conflicts are present in live runtime code and tests.
- The audit treats this as a hard blocker.

Interpretation:
- It has promising integration value, but current branch trust is too low for first-choice PoC work.

---

## 4. Dependency Map

### Core dependency hub
**neurocnl**

Relationships:
- `Neurosim` depends on `neurocnl` for parsing, validation, generation, and simulation.
- `Neurobench` depends on `neurocnl` for simulation work.
- `Neuro-Dream-Hand` depends on `neurocnl` for compiling CNL specs into validated Nengo networks.
- `Neurochip` depends on `neurocnl` for CNL parsing, validation, and Nengo generation.
- `Neurosense` depends on `neurocnl` for spike encoding and pipeline integration.

Interpretation:
- `neurocnl` is the main technical substrate for the suite.

### Secondary dependency / domain support module
**Neuro-Dream-Hand**

Relationships:
- `nmtk/neuro_toolkit/assets/modules.json` declares `Neuro-Dream-Hand/` as a `localDeps` dependency of `neurocnl`.
- `Neurochip` spec lists `neurodreamhand` as a shared dependency for crossbar export, fault injection, and power profiling.

Interpretation:
- `Neuro-Dream-Hand` is not the center of the suite, but it contributes concrete hardware-adjacent logic used elsewhere.

### Mostly independent but downstream-facing module
**Neurohub**

Relationships:
- Other modules may import artefacts from Neurohub.
- Neurohub has no runtime dependency on the other modules.

Interpretation:
- It is a spoke, not a hub.

---

## 5. Concrete Inter-Module Coupling

### Strong coupling
- **Neurosim -> neurocnl**
  The NeuroSim spec says its backend imports the `neurocnl` core library directly for lower-latency preview simulations.

- **Neurobench -> neurocnl**
  Neurobench guidance says the benchmark runner interacts with `neurocnl` to execute real SNN simulations.

- **Neurochip -> neurocnl**
  Neurochip spec lists `neurocnl` as a shared dependency for parsing, validation, and Nengo generation.

### Moderate coupling
- **Neurochip -> Neuro-Dream-Hand**
  Neurochip spec also lists `neurodreamhand` as a shared dependency for crossbar export, fault injection, and power profiling.

- **Neuro-Dream-Hand -> neurocnl**
  Neuro-Dream-Hand uses `neurocnl` to compile CNL behavioral specs.

### Emerging or partial coupling
- **Neurosense -> neurocnl**
  NeuroSense contains a real pipeline bridge aimed at `neurocnl /api/simulate`.

- **Neurosense -> Neurobench**
  NeuroSense contains a `neurobench_bridge` for ingesting canonical HDF5 session artifacts, but its README still describes the full handoff as future work.

- **neurocnl frontend -> Neurochip**
  The `neurocnl` Flutter frontend contains a `NeurochipClient` for export and flash workflows, so some real cross-app integration already exists here.

### Loose coupling / optional infrastructure
- **All modules -> Neurohub**
  Modules can use Neurohub as a registry and artefact source, but they do not require it for runtime correctness.

---

## 6. Practical Rollout Advice

If the goal is **one fast, credible PoC**, choose:
1. **Neurobench**

If the goal is **an independently shippable product that can keep maturing cleanly**, choose:
1. **Neurohub**

If the goal is **maximum leverage across the suite**, choose:
1. **neurocnl**

If the goal is **a realistic sequence**, use:
1. **Neurobench** for the first visible PoC
2. **neurocnl** for shared capability leverage
3. **Neurosim** and **Neurochip** for integration value
4. **Neurohub** as the shared registry layer
5. **Neurosense** only after conflict resolution

---

## 7. Key Evidence

- `docs/archive/08-Apr-2026-status-Codex.md`
- `nmtk/neuro_toolkit/assets/modules.json`
- `Neurohub/README.md`
- `Neuro-Dream-Hand/README.md`
- `Neurosim/neurosim_spec.md`
- `Neurochip/neurochip_spec.md`
- `Neurobench/neurobench/AGENTS.md`
- `Neurosense/README.md`
- `Neurosense/neurosense/app/services/pipeline_bridge.py`
- `Neurosense/neurobench/backend/app/services/neurobench_bridge.py`
- `neurocnl/frontend/lib/services/neurochip_client.dart`

---

*End of Analysis*
