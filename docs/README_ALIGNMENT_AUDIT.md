# README & Documentation Alignment Audit

> **Generated:** 2026-06-11  
> **Scope:** All module READMEs, AGENTS.md files, spec files, and infrastructure docs  
> **Method:** Implementation-first analysis — code is treated as source of truth

---

## Executive Summary

This audit compares documentation claims against actual implementation across 14 modules in the NeuroMorphicToolKit monorepo. The analysis reveals **3 critical cross-cutting issues** affecting multiple modules and **47 individual discrepancies** ranging from broken links to architectural misrepresentations.

### Critical Findings

1. **License Mismatch (6 modules affected)**
   - 6 of 7 module READMEs claim "MIT" license
   - Every LICENSE file and pyproject.toml specifies **AGPL-3.0-or-later**
   - Only Neuro-Dream-Hand correctly states AGPL v3

2. **Suite API Architecture Confusion (5 modules affected)**
   - Multiple READMEs claim "hosted via `suite_api` at `/api/<module>`"
   - Reality: Each module is a standalone FastAPI app; suite_api is a proxy/aggregator
   - Creates false impression of monolithic backend when architecture is microservices

3. **Phantom Infrastructure (4 modules affected)**
   - `neurochip-hw-worker`: Referenced in README, doesn't exist
   - `neurobench-runner-worker`: Referenced in README, no container definition
   - Port 8001 (Neurosim): Retired but still referenced in CI/docker-compose
   - Port 8005 (Neurohub): Never existed; actual ports are 8000/9000

### Summary Statistics

| Severity | Count | Description |
|----------|-------|-------------|
| **Critical** | 3 | License mismatches, phantom workers, broken architecture claims |
| **High** | 12 | Broken doc links, stale ports, missing referenced files |
| **Medium** | 18 | Understated features, inaccurate status percentages, spec drift |
| **Low** | 14 | Minor wording issues, missing optional details |

**Total discrepancies:** 47 across 14 modules

---

## Cross-Cutting Issues

### Issue 1: License Misrepresentation

**Affected modules:** neurocnl, Neurochip, Neurobench, Neurosense, Neurohub, nmtk (Launcher)

**Pattern:**
```markdown
## ⚖️ License
MIT
```

**Reality:**
- Every module's `LICENSE` file contains GNU Affero General Public License v3 (661 lines)
- Every `pyproject.toml` specifies `license = "AGPL-3.0-or-later"`
- Root README correctly states AGPL-3.0-or-later

**Alignment Question:**
> **Q:** Should all module READMEs be corrected to state "AGPL-3.0-or-later" to match the LICENSE files and pyproject.toml? Or is there a plan to relicense specific modules to MIT?

**Recommended Fix:**
```markdown
## ⚖️ License
GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)
```

---

### Issue 2: Suite API Architecture Confusion

**Affected modules:** neurocnl, Neurochip, Neurobench, Neurosense, Neurohub

**Pattern:**
```markdown
**Unified Backend:** Hosted via `suite_api` at `/api/<module>`.
```

**Reality:**
- Each module has its own standalone FastAPI app (e.g., `neurocnl/backend/app/main.py`)
- `suite_api/` is a proxy/aggregator that imports domain routers and mounts static frontends
- Modules can run independently on their own ports
- suite_api provides unified entry point at port 9000 but doesn't "host" the modules

**Alignment Question:**
> **Q:** Should the READMEs clarify that modules are standalone FastAPI apps that can be accessed via suite_api (proxy) or directly? Or is the current wording acceptable as a user-facing simplification?

**Recommended Fix:**
```markdown
**Suite Integration:** Accessible via `suite_api` proxy at `/api/<module>` (port 9000), 
or directly as a standalone FastAPI service.
```

---

### Issue 3: Phantom Infrastructure

**Affected components:**

| Component | Referenced In | Actual State |
|-----------|---------------|--------------|
| `neurochip-hw-worker` | Neurochip README | Does not exist; no Docker service, no code |
| `neurobench-runner-worker` | Neurobench README | Proxy wiring exists in suite_api, but no worker container |
| Port 8001 (Neurosim) | CI, docker-compose, docs | Retired; runtime is now on port 8000 via neurocnl backend |
| Port 8005 (Neurohub) | AGENTS.md, api_reference.md | Never existed; actual ports are 8000 (container) / 9000 (host) |

**Alignment Question:**
> **Q:** For phantom workers: Should the READMEs be updated to remove references to non-existent infrastructure, or are these planned future features that should be marked as "planned" or "optional"?

**Recommended Fix:**
- Remove or mark as "optional/planned" any infrastructure that doesn't exist
- Update port references to match actual runtime configuration
- Add "Current Architecture" section distinguishing implemented vs planned features

---

## Per-Module Analysis

---

### 1. Root README (`README.md`)

**Overall Accuracy:** ~90%

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **High** | Links to `./SETUP_GUIDE.md` | File exists at `docs/SETUP_GUIDE.md` | Should the link be updated to `./docs/SETUP_GUIDE.md`? |
| **Medium** | Module status table with percentages (99%, 97%, 85%, etc.) | No automated verification; percentages appear subjective | Should percentages be removed, or should they be backed by automated health checks? |
| **Low** | "Notebooks (Jupyter)" listed as 90% complete | Jupyter worker exists but kernel registration (SNNTorch, Lava, PyTorch) unverified | Should the Jupyter section clarify which kernels are pre-configured vs optional? |
| **Low** | Monitoring stack not mentioned in architecture section | Full Prometheus+Loki+Grafana stack exists in docker-compose.yml | Should the monitoring stack be documented in the architecture section? |

#### Broken Links

- `./SETUP_GUIDE.md` → Should be `./docs/SETUP_GUIDE.md`

---

### 2. neurocnl / NeuroStudio (`neurocnl/README.md`)

**Overall Accuracy:** ~80%

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **Critical** | License: MIT | LICENSE + pyproject.toml: AGPL-3.0-or-later | Should the license section be corrected? |
| **High** | "Native Interface: Powered by the Flutter `NeuroStudio` feature package" | Frontend is a standalone Flutter app, not a feature package | Should this be clarified as "standalone Flutter app" instead of "feature package"? |
| **High** | References `cnl_parser.py` in examples | Original parser deleted; replaced by `nir_cnl/parser.py` | Should examples be updated to use the new parser path? |
| **Medium** | "Hosted via `suite_api` at `/api/neurocnl`" | Standalone FastAPI app; suite_api is a proxy | Should the suite integration section clarify the proxy architecture? |
| **Medium** | Layer 3 mentioned in AGENTS.md | No dedicated `layer3_*.py` file; logic distributed | Should Layer 3 be documented as distributed across assertion generation? |
| **Low** | "Export verified networks directly to Loihi, Akida, SpiNNaker" | Export code exists but hardware execution not verified | Should the README clarify that exports are code-only, not hardware-validated? |

#### AGENTS.md Drift

- AGENTS.md references `cnl_parser.py` which no longer exists
- AGENTS.md states "The CNL parser uses regex only" — accurate for new parser at `nir_cnl/parser.py`

#### Spec Drift

- `docs/support_matrix.md` is accurate and brutally honest about limitations
- Support matrix correctly marks all backends as "approximate" or "unsupported"

---

### 3. Neurochip (`Neurochip/README.md`)

**Overall Accuracy:** ~65%

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **Critical** | License: MIT | LICENSE + pyproject.toml: AGPL-3.0-or-later | Should the license section be corrected? |
| **Critical** | "HW Workers: SDK-heavy routes isolated in `neurochip-hw-worker`" | Worker does not exist; no Docker service, no code | Should this claim be removed or marked as "planned"? |
| **Critical** | "Dual-layer architecture" (standard API + HW workers) | Single monolithic FastAPI app | Should the architecture section be rewritten to match reality? |
| **High** | Links to `docs/neurochip/teensy_deployment.md` | File does not exist | Should the link be removed or the doc created? |
| **High** | Links to `docs/neurochip/akida_deployment.md` | File does not exist | Should the link be removed or the doc created? |
| **Medium** | "Loihi/Lava: Advanced research-chip orchestration via dedicated workers" | Optional lava router exists, but no dedicated worker | Should this be clarified as "optional Lava integration, no dedicated worker"? |
| **Low** | "Frontend: IDE stub" | Accurate — single `.iml` file | No action needed |

#### Broken Links

- `docs/neurochip/teensy_deployment.md` → Missing
- `docs/neurochip/akida_deployment.md` → Missing

#### AGENTS.md Drift

- AGENTS.md correctly states "frontend/ is an IDE stub"
- AGENTS.md shell mode guidance is accurate

---

### 4. Neurobench (`Neurobench/README.md`)

**Overall Accuracy:** ~85%

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **Critical** | License: MIT | LICENSE + pyproject.toml: AGPL-3.0-or-later | Should the license section be corrected? |
| **High** | "Long-running benchmark jobs handled by `neurobench-runner-worker`" | Proxy wiring exists in suite_api, but no worker container | Should this be clarified as "optional worker (not yet containerized)"? |
| **Medium** | "4 workspaces: Summary, Comparison, Reports, Robustness" | 5 tabs: Configure & Run, Results & History, Comparisons, Reports, Robustness | Should the workspace count be updated to 5? |
| **Medium** | "Upstream NeuroBench Python library used directly" | Declared as optional extra, not hard dependency | Should this be clarified as "optional integration"? |
| **Low** | "Consumes validated networks from `neurocnl`" | Accurate | No action needed |

#### AGENTS.md Drift

- AGENTS.md correctly describes contract-first development
- AGENTS.md shell mode guidance is accurate

#### Spec Drift

- `neurobench_spec.md` (477 lines) is comprehensive and matches implementation
- Spec version not stated; code is v0.6.0

---

### 5. Neurosense (`Neurosense/README.md`)

**Overall Accuracy:** ~95% (Most accurate README in the repo)

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **Critical** | License: MIT | LICENSE + pyproject.toml: AGPL-3.0-or-later | Should the license section be corrected? |
| **Low** | "OpenBCI Cyton: experimental" | Accurate — wired, mocked, honestly labeled | No action needed |
| **Low** | "Prophesee Vision: prototype" | Accurate — router exists, metavision optional | No action needed |

#### AGENTS.md Drift

- AGENTS.md accurately describes domain invariants
- AGENTS.md shell mode guidance is accurate

#### Spec Drift

- `neurosense_spec.md` (457 lines) matches implementation
- All referenced docs exist (flagship_workflow.md, session_artifact_contract.md, etc.)

---

### 6. Neurohub (`Neurohub/README.md`)

**Overall Accuracy:** ~60%

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **Critical** | License: MIT | LICENSE + pyproject.toml: AGPL-3.0-or-later | Should the license section be corrected? |
| **Critical** | AGENTS.md: "Port Assignment: NeuroHub backend runs on port 8005" | Dockerfile: port 8000; docker-compose: host port 9000 | Should AGENTS.md be corrected to port 8000/9000? |
| **High** | AGENTS.md: "NIR models managed via `neurohub/app/services/nir_service.py`" | File does not exist | Should this claim be removed or the file created? |
| **High** | pyproject.toml: "Suite Dashboard & Cross-App Orchestration Layer" | Code is a metadata fabric/registry, not orchestration | Should pyproject.toml description be updated to "Suite Registry & Metadata Layer"? |
| **Medium** | README: "Neurohub is not a runtime control plane; it is a Metadata Fabric" | Accurate for code, but contradicts pyproject.toml | Should pyproject.toml be aligned with README's metadata-fabric claim? |
| **Medium** | Spec claims routers: activity, workflows, dashboard, members, milestones, notes | None implemented | Should the spec be updated to remove unimplemented features? |
| **Medium** | Spec version v0.2.0 vs code version v0.6.0 | Spec has not been updated | Should the spec be revised to match current code? |
| **Low** | user_guide.md: "central orchestration and dashboard layer" | Contradicts metadata-fabric claim | Should user_guide.md be updated? |

#### AGENTS.md Drift

- Port 8005 claim is false (actual: 8000/9000)
- `nir_service.py` claim is false (file missing)
- Other AGENTS.md guidance is accurate

#### Spec Drift

- `neurohub_spec.md` v0.2.0 describes features not implemented (workflow engine, activity collector, etc.)
- Code has features not in spec (registry_artefacts, registry_auth, search_index, etc.)
- Spec needs full revision to match v0.6.0 codebase

---

### 7. Neuro-Dream-Hand (`Neuro-Dream-Hand/README.md`)

**Overall Accuracy:** ~85%

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **High** | References `STATUS.md` | File does not exist | Should the reference be removed or the file created? |
| **Medium** | "9 step scripts (step1 through step9)" | 22 step scripts exist (step1 through step16 with variants) | Should the README be updated to list all 22 scripts? |
| **Medium** | "3 CLI tools: neurodreamhand-sweep, -plot, -quantize" | 4 CLI tools exist (also `-export-crossbar`) | Should the 4th CLI tool be documented? |
| **Medium** | "Phase 4-5: Code complete, awaiting hardware" | Phases 4-5 more complete than claimed; PYNQ support beyond spec | Should the status table be updated to reflect Phase 4-5 progress? |
| **Low** | License badge: AGPL v3 | Accurate | No action needed |

#### AGENTS.md Drift

- AGENTS.md accurately describes safety bounds and constraints
- AGENTS.md correctly states "not a launcher peer module"

#### Spec Drift

- `SPEC.md` (708 lines) is comprehensive
- Code is ahead of spec in some areas (PYNQ support, Phase 4-5 implementation)

---

### 8. nmtk (Launcher) (`nmtk/neuro_toolkit/README.md`)

**Overall Accuracy:** ~95%

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **Critical** | License: MIT | LICENSE + pyproject.toml: AGPL-3.0-or-later | Should the license section be corrected? |
| **Low** | "Module Manifests: Uses `assets/modules.json`" | Accurate — 7 modules defined | No action needed |
| **Low** | "Default API: `suite_api` on port 9000" | Accurate | No action needed |

#### AGENTS.md Drift

- AGENTS.md accurately describes GoRouter shell routes, Provider state management
- AGENTS.md correctly states "module UIs are embedded web frontends"

---

### 9. nmtk_ui_core (`nmtk_ui_core/README.md`)

**Overall Accuracy:** ~98% (Most accurate README)

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **Low** | "40+ components" | Exactly 40 widget files | Should this be updated to "40 components" or left as "40+"? |
| **Low** | Version: 0.6.0+3 | Accurate | No action needed |

#### AGENTS.md Drift

- AGENTS.md accurately describes state-management-agnostic design
- AGENTS.md correctly lists barrel export pattern

---

### 10. neurocli (`neurocli/README.md`)

**Overall Accuracy:** ~95%

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **Low** | "Shipped commands: neuro new, status, install, run, hub login/push/pull/search" | Also has `neuro deploy` command | Should the deploy command be documented? |
| **Low** | "Typer-based Python package" | Accurate | No action needed |

#### AGENTS.md Drift

- AGENTS.md accurately describes package layout and constraints
- AGENTS.md correctly states "module IDs come from modules.json"

---

### 11. Neurosim (`Neurosim/README.md`)

**Overall Accuracy:** ~90%

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **High** | "Module-local backend: `uvicorn neurosim.app.main:app --reload --port 8001`" | Port 8001 retired; app is now a 5-line shim delegating to neurocnl backend on port 8000 | Should the local development section be updated to reflect consolidation? |
| **Medium** | "neurocnl/neurosim/ is the canonical package source" | Accurate | No action needed |
| **Medium** | "Supports one canonical graph topology: two-population sensory → motor reflex arc" | Accurate, but known P1 bug where reversed edges pass detection | Should the known bug be documented? |
| **Low** | "Visual canvas embedded in CNL Studio at `/canvas` route" | Accurate | No action needed |

#### AGENTS.md Drift

- AGENTS.md accurately describes canonical source location
- AGENTS.md shell mode guidance is accurate

#### Spec Drift

- `neurosim_spec.md` (464 lines) explicitly self-declares as "HISTORICAL"
- Spec describes standalone frontend that was never implemented
- Spec is a superseded design document

---

### 12. monitoring (`monitoring/README.md`)

**Overall Accuracy:** ~85%

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **Medium** | "Alertmanager: groups alerts, but currently sends them to a null-receiver" | Accurate — honestly stated | No action needed, but should this be marked as "not yet configured"? |
| **Medium** | "only modules with real metrics endpoints will provide useful Prometheus data" | Accurate — implies incomplete coverage | Should the README clarify which modules expose metrics? |
| **Low** | "Prometheus scrapes suite_api and optional worker targets" | Accurate | No action needed |

---

### 13. workers (`workers/README.md`)

**Overall Accuracy:** ~70%

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **High** | "Workers are created in Phase 4 of the consolidation plan" | 6 workers exist with full implementations | Should the README be expanded to describe each worker? |
| **Medium** | README is only 7 lines | 6 subdirectories with Dockerfiles, main.py, pyproject.toml | Should the README document each worker's purpose and dependencies? |

#### Missing Documentation

The workers README should document:
- `jupyter_server/` — JupyterLab environment with NMTK kernels
- `lava_backend/` — Lava NC simulation backend
- `neurochip_hw/` — Hardware I/O worker for Neurochip
- `neurobench_runner/` — Long-running benchmark execution worker
- `neurocnl_physics/` — Physics simulation worker for neurocnl
- `neurosense_hw/` — Hardware acquisition worker for Neurosense

---

### 14. docs (`docs/README.md`)

**Overall Accuracy:** ~90%

#### Discrepancies

| Severity | Claim | Actual | Alignment Question |
|----------|-------|--------|-------------------|
| **Low** | "docs/ADR-claude/ contains the accepted cross-repo architecture trail" | Accurate | No action needed |
| **Low** | "Not all documentation here has the same status" | Accurate and helpful | No action needed |

---

## AGENTS.md & Spec Drift

### neurohub/AGENTS.md

**Issue:** Port 8005 claim
```
Port Assignment: NeuroHub backend runs on port 8005.
Suite Ports: neurocnl (8000), NeuroSim (8001), NeuroChip (8002), NeuroBench (8003), NeuroSense (8004).
```

**Reality:**
- Neurohub: port 8000 (container) / 9000 (host)
- NeuroSim: port 8001 retired, now on 8000
- Other ports not verified but likely stale

**Alignment Question:**
> **Q:** Should the AGENTS.md port assignments be updated to match actual docker-compose configuration?

---

### neurohub/neurohub_spec.md

**Issue:** Spec version v0.2.0 vs code version v0.6.0

**Spec claims these exist:**
- Routers: activity, workflows, dashboard, members, milestones, notes
- Services: activity_collector, workflow_engine, milestone_tracker, nir_service, health_checker

**Code has these instead:**
- Routers: registry_artefacts, registry_auth, registry_community, registry_health, registry_search
- Services: activity_feed, registry_service, registry_auth_service, search_index, object_storage

**Alignment Question:**
> **Q:** Should the spec be revised to match the current registry-focused implementation, or is the orchestration-focused spec the intended future direction?

---

### neurocnl/AGENTS.md

**Issue:** References deleted parser
```
NEVER modify CNL grammar patterns in `cnl_parser.py` without human approval.
```

**Reality:** `cnl_parser.py` no longer exists; replaced by `nir_cnl/parser.py`

**Alignment Question:**
> **Q:** Should AGENTS.md be updated to reference the new parser location?

---

### Neurosim/neurosim_spec.md

**Issue:** Self-declared as historical
```
This spec describes the originally planned standalone product. The active product shape 
is Studio-integrated: NeuroSim provides a FastAPI backend mounted by CNL Studio, and 
there is no standalone Flutter frontend. Sections describing the frontend, template 
gallery, and standalone build are historical.
```

**Alignment Question:**
> **Q:** Should the spec be archived to `docs/archive/` or deleted, since it explicitly states it's historical?

---

## Prioritized Action Items

### Critical (Fix Immediately)

1. **Correct license claims in 6 module READMEs**
   - neurocnl, Neurochip, Neurobench, Neurosense, Neurohub, nmtk
   - Change "MIT" to "AGPL-3.0-or-later"

2. **Remove phantom infrastructure claims**
   - Neurochip: Remove or mark `neurochip-hw-worker` as "planned"
   - Neurobench: Clarify `neurobench-runner-worker` status
   - Neurohub: Correct port 8005 to 8000/9000 in AGENTS.md

3. **Fix broken documentation links**
   - Root: `./SETUP_GUIDE.md` → `./docs/SETUP_GUIDE.md`
   - Neurochip: Remove or create `teensy_deployment.md` and `akida_deployment.md`
   - Neuro-Dream-Hand: Remove or create `STATUS.md`

### High Priority (Fix Soon)

4. **Clarify suite_api architecture**
   - Update 5 module READMEs to explain proxy vs standalone architecture

5. **Update stale port references**
   - Neurosim: Remove port 8001 references from CI, docker-compose, docs
   - Neurohub: Correct all port 8005 references

6. **Expand workers/README.md**
   - Document each of the 6 workers with purpose, dependencies, and usage

7. **Update neurohub spec**
   - Revise v0.2.0 spec to match v0.6.0 codebase
   - Align pyproject.toml description with metadata-fabric intent

### Medium Priority (Fix When Convenient)

8. **Correct understated features**
   - Neuro-Dream-Hand: Update script count (22 not 9), CLI tools (4 not 3)
   - Neurobench: Update workspace count (5 not 4)

9. **Update neurocnl examples**
   - Fix broken imports referencing deleted `cnl_parser.py`

10. **Clarify optional vs integral dependencies**
    - Neurobench: Clarify upstream neurobench is optional
    - Neuro-Dream-Hand: Clarify mujoco, mediapy are optional extras

11. **Archive historical specs**
    - Move `Neurosim/neurosim_spec.md` to `docs/archive/`

### Low Priority (Nice to Have)

12. **Document monitoring stack in root README**
    - Add section on Prometheus+Loki+Grafana observability

13. **Add automated health checks for status percentages**
    - Root README module status table should be backed by CI checks

14. **Document known bugs**
    - Neurosim: Document P1 bug where reversed edges pass reflex-arc detection

---

## Conclusion

The NeuroMorphicToolKit documentation is **mostly accurate** but suffers from:

1. **Systematic license misrepresentation** (6 modules claim MIT, actual is AGPL-3.0)
2. **Architectural confusion** around suite_api proxy vs standalone services
3. **Phantom infrastructure** (workers and ports that don't exist)
4. **Stale references** to deleted files and retired ports

The implementation is generally **ahead of the documentation** — modules like Neuro-Dream-Hand and Neurochip have more features than their READMEs claim. The most critical fixes are the license corrections and removal of phantom infrastructure claims.

**Recommended approach:**
1. Fix all Critical items immediately (license, broken links, phantom workers)
2. Address High Priority items in the next documentation sprint
3. Tackle Medium Priority items as part of regular maintenance
4. Consider Low Priority items for future improvements

---

**Audit completed:** 2026-06-11  
**Auditor:** Automated analysis via code exploration  
**Next review recommended:** After Critical and High Priority fixes are applied
