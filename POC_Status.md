# NeuroMorphicToolKit — POC Readiness Assessment

**Date:** 2026-03-19  
**Assessor:** Antigravity AI (Gemini)  

---

## POC Definition

**What the POC demonstrates:**  
Open the desktop launcher → Browse available modules → Install a module → Write a CNL spec → Validate → Generate SNN → Simulate → View results → Export to hardware format.

---

## Overall POC Readiness: **~50%**

```
████████████████████░░░░░░░░░░░░░░░░░░░░  50%
```

---

## Readiness by Layer

### ✅ Core Python Engine — 95% DONE

| Component | Status | Notes |
|-----------|--------|-------|
| neurocnl library v0.3.0 | ✅ Complete | 13 concepts, 18 invariants, 5 exports, CLI |
| Neuro-Dream-Hand library | ✅ Complete | MuJoCo, SNN controller, sleep learning, quantization |
| neurocnl FastAPI backend | ✅ Complete | 14 routers, async jobs, prosthetic endpoints |
| neurocnl tests | ✅ 30 test files | ~305 passing tests |
| NDH tests | ✅ 25 test files | ~130 passing tests |

**Verdict:** The engine works today. `neurocnl examples/slip_reflex.cnl` runs end-to-end.

---

### ⚠️ Backend APIs — 80% DONE (4 of 6 complete)

| Module | Service LOC | Real Logic? | Docker? | POC-Critical? |
|--------|------------|-------------|---------|---------------|
| **Neurosim** | 535 (routers) | ✅ Yes | ✅ | Yes |
| **Neurochip** | 1,092 | ✅ Yes (9 services) | ✅ | No |
| **Neurosense** | 1,114 | ✅ Yes (7 services) | ✅ | No |
| **Neurohub** | 937 | ⚠️ Mixed (some thin) | ❌ Missing | No |
| **Neurobench** | 495 | ⚠️ Mixed (runner thin) | ⚠️ Incomplete | No |

**Verdict:** 4 of 6 backends have real service logic. Neurobench runner is still minimal. Neurohub has no Docker.

---

### ⚠️ Frontend UIs — 40% DONE

| Module | Dart Files | Dart LOC | Status |
|--------|-----------|---------|--------|
| **neurocnl** | 59 | 8,978 | ✅ 5 screens, 11 providers, GoRouter |
| **Neurosense** | 20 | 688 | ⚠️ DeviceSelector works, viewer partial |
| **Neurosim** | 14 | 556 | ⚠️ Canvas stub exists, not functional |
| **Neurohub** | 20 | 238 | ❌ All scaffolds |
| **Neurobench** | 17 | 164 | ❌ All scaffolds |
| **Neurochip** | 16 | 133 | ❌ All scaffolds |

**Verdict:** Only neurocnl has a working frontend. Neurosense is partially functional. The remaining 4 are structural scaffolds.

---

### ❌ Desktop Launcher — 0% DONE (CRITICAL REGRESSION)

| Component | Status |
|-----------|--------|
| `neuro_toolkit/lib/` | **DELETED** — directory does not exist |
| `neuro_toolkit/pubspec.yaml` | **DELETED** |
| Process orchestration | Never implemented (was mock) |
| WebView integration | Never implemented |
| Module catalog | Was 3 hardcoded entries (now deleted) |

**Verdict:** The launcher IS the POC, and it has been reduced to empty platform scaffolds. This is the single biggest blocker.

---

### ❌ Root Orchestration — 0% DONE

| Component | Status |
|-----------|--------|
| Root docker-compose.yml | ❌ Does not exist |
| One-command startup | ❌ Does not exist |
| Port coordination | Documented but not enforced |
| Installer scripts | Untested (scripts exist in `nmtk/installer/`) |

---

## Gap Analysis: What's Needed for POC

### TIER 1 — Must Do (Blocks Everything)

| # | Task | Effort | Why Critical |
|---|------|--------|-------------|
| 1 | **Restore/rebuild neuro_toolkit** | 3-5 days | The launcher IS the POC. Currently 0 source files. |
| 2 | **Process manager in launcher** | 3-5 days | Must actually start/stop Python backends |
| 3 | **WebView or embedded UI in launcher** | 2-3 days | Must display module UIs after launch |
| 4 | **Root docker-compose.yml** | 1 day | One-command startup for all services |

### TIER 2 — Should Do (Makes POC Convincing)

| # | Task | Effort | Why Important |
|---|------|--------|-------------|
| 5 | Add all 7 modules to launcher catalog | 2 hours | Currently only 3 were listed |
| 6 | Neurosim: minimal canvas UI | 3-5 days | Visual designer is a selling point |
| 7 | Neurohub: Docker + ci.yml | 1 day | Only module without both |
| 8 | Demo walkthrough script | 1 day | Guided demo scenario |

### TIER 3 — Nice to Have

| # | Task | Effort | Why Useful |
|---|------|--------|-----------|
| 9 | Neurobench: wire real benchmark runner | 2-3 days | Shows benchmarking capability |
| 10 | Neurochip: finish QuantizationExplorer | 2 days | Shows hardware deployment flow |
| 11 | Validate installer scripts | 1-2 days | Enables real distribution |
| 12 | Pre-commit hooks across all modules | 1 day | Developer quality enforcement |

---

## Estimated Timeline to POC

| Phase | Tasks | Duration |
|-------|-------|----------|
| **Week 1** | Restore neuro_toolkit, add process manager | 5 days |
| **Week 2** | WebView integration, root Docker, catalog | 5 days |
| **Week 3** | Neurosim canvas MVP, demo script | 5 days |
| **Buffer** | Bug fixes, polish, testing | 2-3 days |
| **TOTAL** | | **~3 weeks** |

---

## What Works Right Now (No Changes Needed)

1. `neurocnl examples/slip_reflex.cnl` — full CLI pipeline
2. `uvicorn app.main:app` in neurocnl/backend — full API at :8000
3. `docker-compose up` in Neurosim/ — backend at :8001
4. `docker-compose up` in Neurochip/ — backend at :8002
5. `docker-compose up` in Neurosense/ — backend at :8004
6. `python scripts/step3_reflex.py` in Neuro-Dream-Hand — simulation
7. `flutter run -d macos` in neurocnl/frontend — working desktop app
8. All CI pipelines pass on their respective submodules

---

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| neuro_toolkit source code unrecoverable | 🔴 Critical | Check git reflog, branch history, or rebuild from Opus Status description |
| MuJoCo binary licensing on CI | 🟡 Medium | Mock-test physics in CI, real tests local only |
| Submodule pointer drift (4 have `+` prefix) | 🟡 Medium | Commit updated submodule pointers to dev |
| Neurohub has no Docker or CI | 🟡 Medium | Low priority for POC but creates quality gap |
| Installer scripts untested on target platforms | 🟡 Medium | Test during distribution phase, not POC |

---

## Bottom Line

**The engines and backends are strong.** neurocnl and Neuro-Dream-Hand are thesis-quality Python libraries with hundreds of tests. Five out of six backends have real service implementations exceeding 400 LOC each.

**The integration layer is broken.** The desktop launcher has 0 source files. There is no root orchestration. Only one module (neurocnl) has a functional Flutter frontend.

**To reach POC:** Restore the launcher, add real process management, create root Docker orchestration, and build a minimal Neurosim canvas. This is approximately a **3-week focused sprint**.
