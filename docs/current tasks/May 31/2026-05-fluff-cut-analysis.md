# NMTK Fluff-Cut Analysis (2026-05)

**Purpose.** This report audits the current state of the NeuroMorphicToolKit suite and selects functionality that is **low value relative to its upkeep cost** and should be cut, trimmed, or explicitly flagged. It is analysis-only: nothing here deletes code or removes a feature. Findings are grouped one section per module, and within each section product-feature fluff is separated from code-level fluff.

**Method.** The primary lens is *value vs. upkeep*: an item is a cut candidate when its ongoing maintenance and complexity cost is high relative to demonstrated value for the two personas in `docs/PRODUCT.md` (the researcher and the hardware engineer) and the core workflow `design → validate → deploy → benchmark → share`. Every candidate cites a concrete path or symbol observed in the repo. Where a candidate crosses a documented contract boundary (for example a `neurocnl` export field consumed by `Neurochip` or `Neurobench`), it is flagged as *cut requires consumer check* rather than an unconditional cut. Findings are cross-referenced against the existing critiques in `docs/assessment/` and the plan in `docs/current tasks/nmtk-strategic-action-plan.md`; where they agree, that is noted.

---

## How to read this report

**Verdicts**
- **Cut** — remove entirely; little or no value for either persona, low contract risk.
- **Trim** — keep the capability but collapse duplication, delete dead branches, or merge overlapping surfaces.
- **Keep-but-flag** — do not remove now; it crosses a contract or has real value, but it carries cost the owner should track or reframe.

**Confidence**
- **High** — evidence is direct (duplicate tree, stub-only endpoint, leftover artifact) and the cut is locally safe.
- **Medium** — likely fluff, but a consumer or persona check is needed first.
- **Low** — judgment call; depends on roadmap intent the code alone cannot confirm.

**Contract safety.** Anything touching cross-module handoff (CNL/NIR export fields, deploy manifests, registry payloads) defaults to *Keep-but-flag* or *cut requires consumer check*. Per `AGENTS.md`, those changes require reading the consumer module first.

---

## Suite status snapshot

| Area | Size (py / dart) | Maturity read |
|---|---|---|
| `neurocnl` | 374 / 285 | Largest, most mature; carries a duplicated `neurosim/` tree |
| `Neurochip` | 136 / 0 | Backend-heavy; frontend is an IDE stub (UI lives in CNL Studio); several sim-backed "hardware analysis" endpoints |
| `Neurobench` | 89 / 42 | Functional benchmarking; sim-only robustness + CI/CD aspirations overshoot persona |
| `Neuro-Dream-Hand` | 144 / 0 | Thesis/demo; no API surface; assessments say reclassify as example |
| `Neurosense` | 90 / 51 | Real encoding pipelines; vendored stub copies of peer modules |
| `Neurohub` | 106 / 68 | Registry + team store; carries project-management chrome that conflicts with PRODUCT.md |
| `Neurosim` | 87 / 2 | Canonical simulator; duplicated inside `neurocnl` |
| `nmtk` (launcher) | 12 / 59 | Control plane; multiple overlapping setup wizards |
| `nmtk_ui_core` | 0 / 193 | Shared widget library; theme-experiment leftovers |
| `neurocli` | 19 / 0 | Aspirational; README says "appears intended to"; de-list already planned |
| `suite_api` | 25 / 0 | Unified proxy backend; overlaps the per-module + launcher model |

Most upkeep cost concentrates in three places: (1) **duplicated module trees** (`neurocnl/neurosim` vs `Neurosim/neurosim`), (2) **sim-backed endpoints presented as hardware analysis** (Neurochip/Neurobench faults, estimation, perturbation), and (3) **scope-padding surfaces** (Neurohub PM chrome, neurocli, root scratch directories). Each module also carries a `deprecated/` folder (49 files across the suite).

---

## neurocnl

Status: largest module (374 py / 285 dart), the most mature, and the CNL/NIR contract owner. Its cost driver is a second copy of the simulator and a long tail of half-wired backend converters.

### Product-feature fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Bundled `neurocnl/neurosim/` simulator (`neurocnl/neurosim/`) | A near-complete 89-file copy of the top-level `Neurosim` backend, with diverging `main.py`, routers, and backends | Two sources of truth for the same simulator means every sim fix must land twice; `diff -rq` shows the trees have already drifted | Trim (consolidate to one) | Medium |
| Multi-framework deploy/export targets (`neurocnl/neurocnl/converter/`, `export/`) | Converters/exporters for sinabs, rockpool, spinnaker2 alongside the primary path | Several are stubs (see below); breadth of "supported" targets overstates readiness vs. `docs/support_matrix.md` | Keep-but-flag (cut requires consumer check) | Medium |

### Code-level fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| `converter/sinabs_io.py`, `converter/rockpool_io.py`, `converter/spinnaker2_io.py` | Converters whose code paths raise `NotImplementedError` for common topologies (e.g. `spinnaker2_io.py:21,40`; `sinabs_io.py:62,235,240,248,299`) | Carry import surface, tests, and support claims while not actually converting; classic aspirational stub cost | Trim (gate behind support matrix, remove dead branches) | Medium |
| `neurocnl/training_registry.py` (`training_registry.py:128`) | Registry method that raises `NotImplementedError` | Dead path that still needs typing/test upkeep | Keep-but-flag | Low |
| `neurocnl/deprecated/` (5 files) | Retired code retained in-tree | Pure carrying cost; history is in git | Cut | High |

---

## Neurochip

Status: 136 py, no first-party UI (the `frontend/` here is an IDE stub; deployment UI lives in `neurocnl/frontend/lib/features/deploy/` per `Neurochip/AGENTS.md`). Cost driver is a wide router surface where several endpoints present simulated numbers as hardware analysis.

### Product-feature fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Fault-tolerance sweep (`Neurochip/neurochip/app/routers/faults.py`) | `POST /api/neurochip/faults` returns "estimated robustness metrics" from `fault_runner` with no real hardware | `docs/assessment/nmtk-final-assessment.md` flags fault analysis as overshooting the student/researcher persona; high concept surface, low validated value | Keep-but-flag (reframe as estimate, or cut) | Medium |
| Power/latency estimation (`Neurochip/neurochip/app/routers/estimation.py`) | `POST /estimate/power` + `/estimate/latency` via `power_estimator` | Same overshoot: estimates dressed as instrumentation; persona-mismatched per assessment | Keep-but-flag | Medium |
| Multi-SDK target breadth (`routers/akida.py`, `routers/lava.py`, `routers/speck.py`, `routers/spinnaker2.py`) | Per-vendor routers for hardware most users cannot access | SDK fragility is the module's documented long-term risk; breadth inflates maintenance against a small validated set | Keep-but-flag (cut requires consumer check) | Low |
| IDE stub `frontend/` | A non-product Flutter stub kept only for IDE convenience | Per `AGENTS.md` it must not be edited for product work; it confuses the module's real UI ownership | Keep-but-flag (document, don't grow) | Medium |

### Code-level fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| `Neurochip/deprecated/` (7 files) | Retired code in-tree | Carrying cost; recoverable from git | Cut | High |
| Thin estimate routers (`faults.py` 23 lines, `estimation.py` 23 lines) | Endpoints delegating to sim services with `@limiter` overhead | If the feature is reframed out, the routers + schemas + service become dead weight | Trim (fold into one "estimates" surface) | Low |

---

## Neurobench

Status: 89 py / 42 dart, functional benchmarking with a real visual workflow. Cost driver is sim-only robustness endpoints and CI/CD-oriented surfaces that don't match the persona.

### Product-feature fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Regression / CI integration (`Neurobench/neurobench/app/routers/regression.py`) | Benchmark regression tracking framed for CI/CD | `nmtk-final-assessment.md`: "CI/CD aspiration is persona-mismatched"; adds surface few researchers use | Keep-but-flag | Medium |
| Fault + perturbation robustness (`routers/faults.py`, `routers/perturbation.py`) | Robustness sweeps with no real hardware | Same "simulations presented as hardware results" caution as Neurochip; value is real only if labeled as simulation | Keep-but-flag | Medium |
| Vendor-specific runner (`routers/synsense.py`, 119 lines) | SynSense-specific benchmark path | Vendor breadth against a small validated user set; high SDK upkeep | Keep-but-flag (cut requires consumer check) | Low |

### Code-level fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| `Neurobench/deprecated/` (7 files) | Retired code in-tree | Carrying cost | Cut | High |
| Overlapping report surfaces (`routers/reports.py`, `routers/results.py`, `routers/comparison.py`) | Three adjacent read/render surfaces | Likely consolidatable; verify before merge | Trim | Low |

---

## Neuro-Dream-Hand

Status: 144 py, no API routers, no first-party UI; ships `cnl-docs/`, `cnl-specs/`, `examples/`, `output/`, and a built `site/`. Multiple assessments converge on the same conclusion.

### Product-feature fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Peer-module framing | Listed/treated as a suite peer module | `nmtk-final-assessment.md` and `nmtk-strategic-action-plan.md` both say reclassify as a demo/example, not a peer; presenting it as a module misrepresents suite completeness | Trim (reclassify as example) | High |
| Built `Neuro-Dream-Hand/site/` in-repo | Generated docs site committed to the tree | Build artifact; regenerable, inflates the checkout | Cut | Medium |

### Code-level fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| `Neuro-Dream-Hand/deprecated/` (6 files) | Retired code in-tree | Carrying cost | Cut | High |
| `output/` artifacts | Demo run outputs committed alongside code | Belongs in a recordings/artifact store, not the module source | Cut | Medium |

---

## Neurosense

Status: 90 py / 51 dart, with genuinely useful reproducible encoding pipelines. Cost driver is vendored stub copies of peer modules and hardware-specific surfaces.

### Product-feature fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Event-camera integration (`Neurosense/neurosense/app/routers/prophesee.py`) | Prophesee event-camera device path | Hardware few users own; high driver/SDK upkeep against narrow value | Keep-but-flag (cut requires consumer check) | Low |
| Preset encoding strategies (`routers/presets.py`) | Encoding presets surfaced as one-click choices | `nmtk-strategic-action-plan.md` flags presets can produce "silently wrong" science; the upkeep is in disclaimers, not the feature | Keep-but-flag (reframe, don't cut) | Medium |

### Code-level fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Vendored `Neurosense/neurobench/` and `Neurosense/neurocnl/` (1 py each) | Stub directories shadowing peer module names | Confusing namespace collisions for one-file stubs; pure cost | Cut | High |
| `Neurosense/deprecated/` (7 files) | Retired code in-tree | Carrying cost | Cut | High |
| `recordings_smoke_test/` in module root | Test recordings committed in source | Belongs in fixtures or a store, not module root | Trim | Low |

---

## Neurohub

Status: 106 py / 68 dart. The team artifact registry is a real, defensible use case. The cost driver is project-management chrome that directly conflicts with the product's own anti-references, plus a sprawling registry router family.

### Product-feature fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| PM chrome (`routers/milestones.py`, `routers/notes.py`, `routers/activity.py`, `routers/members.py`, `routers/workflows.py`, `routers/dashboard.py`) | Milestones, notes, activity feed, members, workflows, dashboard | `docs/PRODUCT.md` explicitly lists Jira/Atlassian "ticket-driven" chrome as an anti-reference; this is the clearest off-mission surface in the suite (836 lines across these routers) | Cut (workflows/milestones/activity) / Trim (members) | Medium |
| Split registry surface (`registry_search.py`, `registry_artefacts.py`, `registry_community.py`, `registry_health.py`, `registry_auth.py`) | Five separate registry routers plus top-level `auth.py`/`health.py` | `registry_auth`/`registry_health` overlap `auth`/`health`; the registry could be one cohesive surface | Trim (consolidate; cut requires consumer check) | Medium |

### Code-level fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Duplicate auth/health (`routers/registry_auth.py` vs `routers/auth.py`; `routers/registry_health.py` vs `routers/health.py`) | Parallel auth and health endpoints | Two auth/health code paths is a security-and-maintenance liability; unify | Trim | Medium |
| `Neurohub/deprecated/` (8 files) | Retired code in-tree | Carrying cost | Cut | High |

---

## Neurosim

Status: 87 py / 2 dart, the canonical simulator. The simulator itself is core, not fluff. The fluff is the *duplication* of it elsewhere and retired code.

### Product-feature fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Duplication with `neurocnl/neurosim/` | The same simulator exists in two trees that have already diverged | One canonical simulator should exist; the duplicate doubles fix cost and risks behavior drift between CNL Studio and standalone sim | Trim (pick one canonical home) | Medium |

### Code-level fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| `Neurosim/deprecated/` (9 files) | Retired code in-tree, the largest deprecated folder in the suite | Carrying cost | Cut | High |
| `Neurosim_shell_adapter/` | Separate adapter package mirroring shell wiring also present in other modules | Verify it isn't a per-module re-implementation of shared shell glue before keeping | Keep-but-flag | Low |

---

## nmtk (launcher)

Status: 12 py / 59 dart control plane. Core to the suite. Cost driver is several overlapping first-run setup wizards.

### Product-feature fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Overlapping setup screens (`nmtk/neuro_toolkit/lib/screens/backend_setup.dart`, `python_setup.dart`, `server_setup.dart`, `environment_editor.dart`) | Four separate setup/configuration surfaces | Likely overlapping first-run flows; PRODUCT.md wants "invisible orchestration," not four wizards. Consolidating reduces UI + provider + test upkeep | Trim (merge into one guided flow) | Low |

### Code-level fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| `neurocli` entries in `nmtk/neuro_toolkit/assets/modules.json` | Manifest listing for an unimplemented module | `nmtk-strategic-action-plan.md` already plans to de-list `neurocli`; carrying it misrepresents completeness. Per `AGENTS.md`, manifest changes must update Dart models + launcher tests together | Trim (de-list; contract-coupled) | High |

---

## nmtk_ui_core

Status: 193 dart shared widget library. Mostly load-bearing. Cost driver is theme-experiment leftovers.

### Product-feature fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| `lib/neat/dark` + `lib/neat/dark2` | Two parallel "neat" dark theme experiments | Naming (`dark2`) signals an abandoned variant; duplicate theme assets carry visual-regression upkeep | Trim (keep one, drop the other) | Low |

### Code-level fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Unbarrelled / unused public widgets | Per `AGENTS.md`, the public API is `lib/nmtk_ui_core.dart`; any widget not exported there and not consumed is dead | Shared-library dead code multiplies across every consumer's analysis | Keep-but-flag (audit barrel vs. usage) | Low |

---

## neurocli

Status: 19 py. The README opens with "`neurocli` appears intended to be the command-line companion" and describes what it *should* do — a strong aspirational-stub signal.

### Product-feature fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Peer-module status | Presented as a suite peer in docs/manifests | `nmtk-final-assessment.md` ("unimplemented, should not be presented as a peer module") and the strategic plan ("De-list `neurocli`") both agree | Cut (de-list as peer; keep as roadmap) | High |
| `hub` sub-commands (`neurocli/neurocli/hub.py`) | login/push/pull/search against Neurohub | Duplicates Neurohub registry surface from a second client before the CLI itself is real | Keep-but-flag (cut requires consumer check) | Low |

### Code-level fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Template bundles (`neurocli/neurocli/templates/`) | Scaffolding bundles (`nir_snntorch`, `nir_lava_sim`, `neurocnl_pynq`, `akida_brainchip`) | Real package data, but unmaintained templates rot fast against moving contracts; gate to the ones actually verified | Trim | Low |

---

## suite_api

Status: 25 py unified backend (`suite_api/main.py`, `proxy.py`, per-domain routers). Architecturally clean, but it overlaps two other orchestration models.

### Product-feature fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Parallel orchestration model | `suite_api` proxies to per-module backends (`suite_api/proxy.py`, `suite_api/domains/*/router.py`) while the launcher (`nmtk`) also manages module lifecycle and per-module FastAPI apps exist standalone | Three ways to stand up the same backends is real architectural upkeep; pick the canonical path or document why both exist | Keep-but-flag (architectural decision) | Medium |
| `domains/jupyter/router.py` | A Jupyter domain inside the unified API | Off the `design → deploy → benchmark → share` core; verify it's used before keeping | Keep-but-flag | Low |

### Code-level fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Thin pass-through domain routers (`suite_api/domains/*/router.py`) | Per-domain routers that mostly forward to `proxy_to_worker` | If the launcher remains the canonical orchestrator, these are duplicate glue | Keep-but-flag | Low |

---

## Cross-cutting / root

Suite-wide items not owned by a single module. These are the cheapest, safest cuts — almost entirely scratch artifacts and retired code.

### Repo-hygiene fluff
| Item | What it is | Why it's fluff (value vs. upkeep) | Verdict | Confidence |
|---|---|---|---|---|
| Committed databases (`jobs.db` ~5.9 MB, `neurohub.db`, `projects.db`, `neurobench.sqlite`, `test_alembic_migrations.db`) | Runtime/test SQLite DBs committed at repo root | Binary state in source bloats the checkout and churns on every run; belongs in gitignore + a data dir | Cut (gitignore) | High |
| Stray run artifacts (`server.log`, `simulation_report.json`, `recordings/`) | Logs and outputs committed at root | Generated artifacts, not source | Cut | High |
| One-off patch script (`patch_nir_compat.py`) | Root-level compatibility patch script | One-shot migration helper left in the tree; fold into a migration or remove | Trim | Medium |
| Scratch/idea directories (`.tmp_manual_ui/`, `Auto agentic workflows (Jules)/`, `UI - issues/`, `UI-mistakes/`, `pitches/`, `workflow-errors/`, `tools/`) | Manual scratch, agent experiment output, and idea folders at repo root | No role in `design → deploy → benchmark → share`; these are notes, not product | Cut (archive out of repo) | Medium |
| Per-module `deprecated/` folders (49 files across 7 modules) | Retired code retained in every module | Uniform carrying cost the suite has institutionalized; git already preserves history | Cut | High |
| Duplicate doc trees (`docs/issues - future/`, `docs/issues-archive/`, `issues-archive/` at root, `docs/current tasks/` vs `docs/tasks/`) | Overlapping issue/task doc locations | `docs/issues - future/001-003` already call for consolidating active vs archived docs; fragmentation raises doc upkeep | Trim (consolidate) | Medium |

---

## Consolidated cut list (ranked by upkeep saved vs. risk)

**Tier 1 — safe, high-yield (do first; no contract risk).** These reclaim the most upkeep for the least risk.
1. Delete all module `deprecated/` folders (49 files). *(High)*
2. Gitignore + relocate committed DBs and run artifacts (`jobs.db`, `*.db`, `*.sqlite`, `server.log`, `simulation_report.json`, `recordings/`). *(High)*
3. Remove vendored stub dirs `Neurosense/neurobench/` and `Neurosense/neurocnl/`. *(High)*
4. Archive root scratch directories (`.tmp_manual_ui/`, `Auto agentic workflows (Jules)/`, `UI - issues/`, `UI-mistakes/`, `pitches/`, `workflow-errors/`) out of the repo. *(Medium)*
5. Drop the committed `Neuro-Dream-Hand/site/` build and `output/` artifacts. *(Medium)*

**Tier 2 — product reframing (clear value, low contract risk).**
6. Cut Neurohub PM chrome — `workflows.py`, `milestones.py`, `activity.py`, `notes.py`, `dashboard.py`; trim `members.py` — to align with the PRODUCT.md anti-references. *(Medium)*
7. Reclassify `neurocli` and `Neuro-Dream-Hand` from peer modules to roadmap/example (matches the existing strategic plan). *(High / High)*
8. Merge the four launcher setup screens into one guided flow. *(Low)*
9. Collapse `nmtk_ui_core` `neat/dark` + `neat/dark2` to a single theme. *(Low)*

**Tier 3 — de-duplication (medium effort, needs care).**
10. Consolidate the duplicated simulator (`neurocnl/neurosim/` vs `Neurosim/neurosim/`) to one canonical home. *(Medium)*
11. Consolidate Neurohub registry routers and remove duplicate `registry_auth`/`registry_health`. *(Medium)*
12. Consolidate overlapping doc trees per `docs/issues - future/001-003`. *(Medium)*

**Contract-dependent — cut requires consumer check (do not cut blind).**
- `neurocnl` stub converters/exporters (sinabs/rockpool/spinnaker2) and any export-field changes → check `Neurosim`, `Neurochip`, `Neurobench`, `Neurohub` consumers and `docs/support_matrix.md`.
- Neurochip/Neurobench sim-backed endpoints (`faults`, `estimation`, `perturbation`, `synsense`) → reframe as estimates or gate; verify the deploy/benchmark UI consumers first.
- De-listing `neurocli` from `nmtk/neuro_toolkit/assets/modules.json` → must update launcher Dart models and launcher tests in the same change (`nmtk/AGENTS.md`).
- `suite_api` vs launcher orchestration overlap → an architectural decision, not a blind delete.

---

*Scope note: This report recommends cuts only; it changes no code. Confidence is deliberately conservative — anything crossing a documented contract boundary is flagged rather than marked as a clean cut. A follow-up implementation pass would be a separate task.*
