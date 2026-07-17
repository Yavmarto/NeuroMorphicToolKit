# Open Backlog — 2026-07-17

Consolidated rollup of every genuinely-still-open item found while cleaning up `current tasks/` (full read of all 33 folders / 72+ files, cross-checked against the `2026-07-16` ADR/README/gbrain audit and the full ~132-file ADR corpus). Same purpose as `archive/June 13/TASKS.md` and `archive/20 june/open-items-consolidated.md` before it — this is the current live rollup; treat those two as historical.

**Path note:** every source file this doc cites below (e.g. `16 june/...`, `2026-07-08/...`, `June 13/...`) has since been moved wholesale into `archive/`, same relative sub-path, same filename — e.g. `16 june/cnlstudio_notebook_analysis.md` is now `archive/16 june/cnlstudio_notebook_analysis.md`. `current tasks/` now holds only `archive/` (every historical file, done or not) and this folder (today's live backlog). Paths below were not individually rewritten to avoid introducing copy errors across ~50 references — just prepend `archive/` to any bare path you don't find at the top level.

## Decisions made today (2026-07-17) and what was done about them

1. **Neurosim mirror desync → retire the mirror.** Decision made: stop maintaining `Neurosim/neurosim/` as a separate copy of `neurocnl/neurosim/`; point everything at the real (`neurocnl`) version instead. **Not executed yet** — this is a cross-module surgery (routing, build config, imports all need checking first) and deserves its own scoped task rather than a same-session edit. See "Still to schedule" below.
2. **gbrain backfill → skipped.** Clarified: gbrain *is* "Open Brain" — same tool, just the CLI name (`~/.claude/CLAUDE.md`'s "Always check Open Brain" instruction refers to this same `gbrain search`). Given only 1 of 132 ADRs was ever mirrored into it and everything else already lives in git-committed ADRs/docs, it isn't adding anything ADRs don't already cover today. Skipping the backfill; revisit only if cross-session semantic search across the whole repo becomes something worth having.
3. **Dead code → deleted.** Confirmed (independently, via grep for actual callers, not just trusting the audit's claim) that all 5 items had zero live callers, then deleted them:
   - `Neurohub/neurohub/app/services/suite_client.py` + its dedicated test `neurohub/tests/test_suite_client.py` (test only exercised the dead module in isolation — no router/service anywhere called `call_app_api`, `send_bundle_handoff`, or `fetch_activity`).
   - `Neurohub/frontend/lib/widgets/workflow_step_card.dart`
   - `Neurohub/frontend/lib/widgets/milestone_timeline.dart`
   - `Neurohub/frontend/lib/screens/settings_screen.dart`
   - Empty placeholder dir `Neurochip/nmtk_ui_core/`
   - **Context found along the way:** `Neurohub/.swarm/plan.md` holds a stale (dated 2026-05-11/12) multi-phase "NeuroHub Registry Repositioning Mission" plan from a different agent/tool, whose Phase 1 explicitly planned trimming `suite_client.py` down to `send_bundle_handoff`/`call_app_api`/`fetch_activity`/`DEFAULT_URLS` and removing suite-wide health checking. The repo today has gone further than that plan (those "keep" functions ended up with zero callers too) — this confirms the Neurohub drift was a deliberate architecture pivot, not random rot, but that `.swarm/` mission itself looks abandoned/superseded and was left out of scope here.
4. **Stale ADR headers → fixed.** These already had a body-level "Status Update (2026-07-16 audit)" note explaining the real state, but the `## Status` header itself still said "Accepted" — updated the header on the 5 where the audit's own note made the new status unambiguous:
   - `nmtk/docs/ADR-claude/0002-provider-state-management.md` → "Superseded by ADR 0006"
   - `nmtk/docs/ADR-claude/0005-separate-deployment-providers.md` → "Superseded by ADR 0006 and ADR 0007"
   - `Neurohub/docs/ADR-claude/0003-workflow-engine.md` → "Deprecated — feature removed"
   - `Neurohub/docs/ADR-claude/0004-suite-service-discovery.md` → "Deprecated — dead code, no live callers"
   - `docs/ADR-claude/0030-dynamic-training-graph-executor.md` → "Superseded (reverted same-day)"
   - Left `Neurohub/docs/ADR-claude/0001-postgresql-sqlalchemy-alembic.md` header as "Accepted" — its core tech decision (SQLAlchemy 2.x + Alembic) still holds; only the model list is stale, which the existing body note already covers.

## Still to schedule (not done in this pass)
- **Retire the Neurosim mirror** (decision #1 above) — needs its own investigation into what still points at `Neurosim/neurosim/` before anything gets deleted or redirected.
- Everything else below this line is unchanged from the original audit — still open, still needs someone to pick it up.

## Housekeeping done in this pass
- Deleted 2 confirmed append-only duplicate files (old copy kept only the "AWAITING APPROVAL"/"not started" header; the `June 13/` copy is identical plus a `## Verified Implementation Status (2026-07-04)` section): `archive/June 2/2026-06-02-akida-manage-targets-pynq-target-picker.md`, `archive/June 9/2026-06-09-cml-studio-workspace-hub-plan.md`. `archive/June 9/` is now empty and was removed.
- Moved 4 dead-end/superseded plans into `archive/` (content preserved, just out of the active view): `2026-07-13/dynamic_training_graph_plan.md` (built in `neurocnl` 2026-07-13, fully deleted same day — see ADR-0030 note below), `2026-07-05/cnl_training_eval_plan.md` (CNL `pipeline {}` block never adopted, JSON pipeline config stayed canonical), `June 13/2026-05-27-validation-deploy-readiness.md` (confirmed NOT STARTED as of 07-04; problem space later solved differently — see below), `June 11/MASTER_TASK_ORDER.md` (superseded rollup, chain is now `archive/June 2/MASTER_TASK_ORDER.md` → `archive/June 11/MASTER_TASK_ORDER.md` → `June 13/TASKS.md`, only the last is current).
- Renamed `30 june/implementation_plan.md` → `30 june/wgpu_native_viz_plan.md` (it's the Wgpu native-renderer plan, unrelated to the similarly-named root `30 June.md`; the generic name inside a same-named-but-different-case folder was confusing).
- **Correction to a prior automated claim:** `12-june/canvas-drawing-model.md` and `June 13/2026-06-12-canvas-drawing-model-plan.md` are *not* a duplicate pair despite looking like one at a glance — both carry independently-written, non-overlapping verification detail (different file/line evidence, different test findings). Left both in place untouched.
- `archive/June 2/`, `archive/June 8/`, `archive/June 9/` still exist as real folders even though `June 13/TASKS.md` claims old folders were "removed" — that claim is just stale wording in a historical doc; no action needed, this is what `archive/` is for.
- **2026-07-17, later same day:** every remaining dated/named folder and loose file in `current tasks/` — done or not — was moved into `archive/` (pure `git mv`, zero content changes, verified via `git diff --stat` showing 0 insertions/deletions across all 60 renames). Reasoning: this backlog doc is now the single index of what's actually open, with a source-file pointer for every item; there's no longer a reason for `current tasks/` itself to hold dozens of loose historical files at the top level. `current tasks/` now contains only `archive/` and this `2026-07-17/` folder.

## ADR / doc drift needing a human decision (from 2026-07-16 audit)
1. **Neurosim mirror desync** — `Neurosim/neurosim/` is missing real files present in canonical `neurocnl/neurosim/` (`schemas/canvas.py`, `schemas/components.py`, `schemas/export.py`, `schemas/preview.py`, `schemas/projects.py`, `schemas/sweep.py`, `services/chip_targets.py`, `services/topology_cascade_generator.py`, several tests). **Decided 2026-07-17: retire the mirror** (see "Decisions made today" above) — execution still needs scheduling.
2. ~~gbrain backfill~~ — **decided 2026-07-17: skip** (see "Decisions made today" above).
3. ~~Orphaned dead code~~ — **done 2026-07-17**, see "Decisions made today" above.

## ADRs still missing a supersession marker
- ~~`nmtk/docs/ADR-claude/0002`, `0005`~~ — **fixed 2026-07-17**, headers now say "Superseded" (see "Decisions made today" above).
- ~~`Neurohub/docs/ADR-claude/0003`, `0004`~~ — **fixed 2026-07-17**, headers now say "Deprecated" (see "Decisions made today" above). `0001`'s header was deliberately left as "Accepted" — only its model list is stale, the underlying tech decision still holds.
- ~~`docs/ADR-claude/0030`~~ (Dynamic Training Graph Executor) — **fixed 2026-07-17**, header now says "Superseded".

## Unresolved bugs
- **Stepper-stuck bug** — `2026-07-12/flutter_ram_blowup_round5_explain_and_stepper_bug.md` added debug instrumentation but did not fix a new stepper-stuck issue found while chasing the RAM-blowup chain (rounds 1→3→5; "round 4" is referenced in prose but was never written up as its own file — confirmed via git history, not a lost file, just undocumented).
- **Docker build broken** — per `4 juli/notebook_generation.md`: a private package pin + a missing README copy step breaks the build.
- **`snntorch_apply.ipynb` misclassified** — an earlier doc rated it 🟢 HIGH replication confidence; batch-generation testing found the real `.nir` uses `SumPool2d` (not `AvgPool2d`), which is actually `unsupported`.
- **CNL sentence-picker still emits legacy grammar** — `June 13/2026-05-22-neurocnl-sentence-picker-nir-alignment.md`: autocomplete still suggests biological-grammar phrases (`MUST`, `sensory neuron`, `STDP`) that the NIR-native parser's denylist immediately rejects. Confirmed still broken as of 07-04 (zero drift from original report), two concrete rewrite tasks defined, neither applied.

## Unfinished plan phases still open
- `June 11/frontend-remediation-plan.md` — phases 0, 1C, 3, 4, 7, 8, 9, 10 not started (only 5 and 6 are done/mostly-done); flagship acceptance criteria (clean builds, zero `ZETA-MIGRATION-TODO`) unmet as of 07-04.
- `2026-06-07/frontend-migration-plan.md` — Phase 4 unfinished; Phase 2's "✅ COMPLETE" claim is **over-stated** (07-04 verification found 109 test failures, worse than the doc's own last-recorded 73) — needs re-verifying, not just finishing.
- `2026-06-07/studio-single-source-of-truth-remaining-implementation-plan.md` — Task 7 (remove dual-write) is the one genuinely unfinished item; Task 9 (final verification) unchecked.
- `June 13/2026-05-24-nir-bundle-architecture.md` — Phase 1 (the `.nir`+`.train` → `.nmtk` bundle container itself), the `reward_signal` field, and Phase 4/4b (BindsNET/Lava online-learning adapters) remain not started.
- `1 juli/` mobile redesign — Phase 3 (per-module content adaptation: split-panes→tabs, tables→lists) barely started vs. Phases 1-2 done.
- **Wgpu native renderer** (`30 june/wgpu_native_viz_plan.md`) — real Rust crate + Flutter FFI bridge built, but hard-disabled by default behind a feature flag due to an unfixed SIGSEGV in the macOS texture bridge; production always falls back to the fragment-shader renderer.
- `June 13/2026-05-26-material-icons-to-zeta-icons-migration.md` — functional migration is ~75% done (631→155 raw `Icons.*` hits); the only remaining gap is a paper-trail one (`.kiro/specs/...` artifacts referenced by governance tests were never created) — low priority.
- `11 june/architecture-contracts-deep-dive.md` — 7 drift issues found; `20 june/open-items-consolidated.md` rolled up *some* of these into Waves A-D (A1/A3/A5 done, A2/A4 not started) but doesn't clearly cover 100% of the original 7 — worth a quick recheck of which of the 7 are still genuinely open.

## Needs a status re-check (last confirmed broken 2026-07-09, not confirmed fixed since)
`July 9/flutter_frontend_audit.md` P0s: Neurosense has real compile errors, Launcher silently drops Settings access, a wrong hardcoded port, `TextEditingController` leaks. No later doc in the tree confirms these were fixed.

## Pending manual verification (fix landed in code, live click-through not done)
- `2026-07-15/cnl-renderer-synaptic-gap-fix.md` — remote deploy re-test still pending.
- `2026-07-15/model-canvas-cleared-no-confirm-fix.md` — fix not yet manually clicked through in a live running app.

---

# Round 2 additions (2026-07-17, same day) — filling gaps missed in the first pass

The sections above were built from survey-agent *summaries*. Two follow-up agents did full line-by-line reads of the docs most likely to hide open work — the notebook-replication files (nothing about them made it into round 1 at all) and the older rollup/release-gap docs whose Wave B/C/D items were reported as "unverified" rather than actually read. Everything below is new; nothing above changed.

## CNLStudio notebook-replication backlog

**Correction (2026-07-17, later same day):** this whole area was misrepresented above and in the earlier archiving pass, in two ways. First, "fully shipped ✅"/"guides written" describe **capability presence confirmed by reading source code**, not actual end-to-end runs — nobody has opened CNLStudio, built the 3 written guides' graphs, run them, and confirmed the original notebooks' numeric results come out the other end. Second, and missed until the user flagged it: **everything below only ever covered a subset of the notebooks in the repo.** Full accounting:
- All 4 "known" notebook collections (the 42-ish `paper/01_lif`/`02_cnn`/`03_rnn` notebooks, the 6 `Spiking-Neural-Networks-Tutorials-main` intros, the 12 `notebooks-main` Norse tutorials, the 5 Chinese SpikingJelly tutorials) turn out to all be siblings nested inside one parent, `paper/` — ~59-63 notebooks total, of which only 10 are on the curated "reproducible" list, only 3 groups have guides, 0 have been actually run in CNLStudio.
- **A whole separate real notebook collection was never assessed at all: `Neuro-Dream-Hand/`** (NMTK's own submodule) — `demo.ipynb` + 6 example notebooks (conveyor, dynamic mass, fragile grasp, noisy sensors, phantom limb, prosthetic fatigue), Nengo/MuJoCo prosthetic-hand demos. No P0-P5 backlog, no ranking, no guide — needs its own pass from scratch.
- Two more notebook locations exist but are **not** replication targets (noted so they don't get mistaken for new sources): `workers/jupyter_server/notebooks/00_nmtk_quickstart.ipynb` (NMTK's own product notebook) and `gen test/` (CNLStudio's own generated codegen-test output, not a source — its `MANIFEST.md` was never actually read before now; it re-confirms the `snntorch_apply`/`SumPool2d` finding and adds a new one: the 3 Braille notebooks classify `approximate` not `exact` because `RSynaptic`/`Synaptic` flatten to `CubaLIF` at NIR export — expected behavior, but means Guide 2 isn't an exact reproduction of the original dynamics).

The real open task is: replicate and test the `paper/` set end-to-end, then do a from-scratch assessment of `Neuro-Dream-Hand/`'s 7 notebooks — not just write more instructions. The latest guide (`snntorch_cnlstudio_replication_guide.md`, dated 2026-07-16) was pulled back out of `archive/` into this same `2026-07-17/` folder for that reason — it's live work, not history. Treat every "done"/"shipped" claim below as "instructions exist for a subset of notebooks, execution unverified."

The original P0–P5 feature backlog (`16 june/cnlstudio_notebook_analysis.md`) has a ✅ on all 24 items, meaning the underlying UI capabilities exist — untested end-to-end. Still open, none of it covered by that backlog:
- **"Spike Rate Logger" node** (Notebook 1) — major, not implemented. Distinct from the already-shipped Spike Generator / Dynamics-tab visualization.
- **Connection-topology clarity** in the canvas UI for multi-port wiring — minor, recurring across notebooks 1/2/3, never fixed.
- **Nengo path** (`nengo_apply.ipynb`): `nir_to_nengo` converter needs extending for `cnl.RSynaptic`; no in-canvas Nengo simulation preview for RSynaptic; results only viewable externally/via `.npy` import.
- **No deploy target at all for SpiNNaker2, Spyx, or Xylo** — blocks 6 named notebooks (`lif_spyx.ipynb`, the SpiNNaker2 debug notebook, `s2_apply.ipynb`, `spyx.ipynb`, `spyx_apply.ipynb`, `xylo_apply.ipynb`). Real backend work, not a node-palette gap.
- **No per-node exact/approximate/unsupported support table** for 6 targets that already have converters but are unclassified (`nengo_io`, `sinabs_io`, `rockpool_io`, `brian2_io`, `pynn_io`, `akida_mapper`) — leaves ~9 notebooks stuck at 🟡 MODERATE until built.
- **`Affine` wrongly marked `unsupported` at `lava_sim`** in `nir_support.py` — an external script (`nir_to_lava.py`) already does this mapping correctly; promoting it is low-effort but not done. Same underlying issue via `Conv2d` blocks the `lava_apply.ipynb` notebooks (🔴 LOW).
- **`rockpool_io` coverage for `cnl.RSynaptic`/`cnl.Synaptic` is unverified** — blocks `rockpool_apply.ipynb` (🔴 BLOCKED per the 07-16 guide).
- **`02_cnn/nengo.ipynb`** is 🔴 BLOCKED — needs `Conv2d`/`Flatten`/`SumPool2d`, all three unsupported in the nengo backend; "no UI workaround short of removing the convolutions."
- **Agent-driven notebook-guide set**: only 1 of the planned 10 guides is written (`agent-tests/guides/lif_snntorch.md`); the other 9 are unwritten and not even enumerated inline — check `agent-tests/reproducible_notebooks.md` for the full target list before picking this up. The AppleEvent-timeout fix proposed for `run_agent.sh` (the `-1712` error) is itself unverified — never confirmed against a real Terminal.app window.
- **Docker build broken**: `neurocnl/backend/Dockerfile` doesn't actually build — `requirements.txt` pins a private non-PyPI package (`neurodreamhand`) and `pyproject.toml` needs a `README.md` the Dockerfile never copies in. Worked around only in a throwaway image for one-off generation; the real Dockerfile is still broken for anyone building fresh.
- **`snntorch_apply.ipynb` misclassified**: rated 🟢 HIGH in the original analysis, but the real `.nir` file uses `SumPool2d` (not `AvgPool2d`), which is `unsupported` on `snntorch_sim` — should read `unsupported`, not HIGH confidence.
- Only 3 of the ranked replication candidates have written step-by-step guides (`tutorial_3_feedforward_snn`, the 4-notebook LIF group, `Braille_training_snntorch`) — **none of the 3 have been actually run in CNLStudio and checked against the original notebooks' output; this is the single biggest concrete next step.** The Norse `notebooks-main` set and all of `spikingjelly-master` were explicitly never meant to get guides (documented reasoning — not an oversight, don't chase these).

## Wave B / C / D backlog (`20 june/open-items-consolidated.md`)
Unlike Wave A (covered in round 1), the doc itself says Waves B/C/D were **never re-verified** — treat everything below as live backlog, not "maybe already fixed":
- **Wave B:** 7 Neurohub stub widgets needing `NmtkEmptyState` treatment (config panel, member manager, note editor, bundle-export dialog, live-test dashboard, plus the 2 widgets already deleted this session — `workflow_step_card`/`milestone_timeline` — so only 5 of the 7 remain); `auth_service.dart` timeout/error handling; `_launchModule` stub in `project_detail_screen.dart`; import-path standardization; `test_cross_module.py` port rewrite (drop per-module port defaults, use `SUITE_API_URL`); `composeProfile` divergence in `DeploymentCapability` (needs a delete-vs-wire decision); `zetaFallback()` helper adoption (5 call sites); `NmtkToasts`→`NmtkSnackBars` deprecation (3 frontends); a few misc small cleanups. (B4d and the `neat/dark/` theme move are explicitly deferred — not open, don't list as backlog.)
- **Wave C:** Neurosense `@freezed`+`@riverpod` codegen migration (6 providers, 4 models) plus small `live_signal_viewer.dart`/`app.dart` fixes; 5 small Neuro-Dream-Hand code-quality items (overly-broad excepts in `adapter.py`/`hitl_surface.py`, magic numbers, mid-body imports across 4 files, docstring style in 2 files, a `_constants.py` extraction); the Pydantic→Dart contract-sync codegen pipeline (new package, 4 model pairs — marked highest-risk, plan first).
- **Wave D:** 12 low-priority polish items (D1–D12) scattered across Neurobench/Neurosense/Neurohub/nmtk_ui_core/NDH — desktop-scaffold adoption, mounted-guards, spacing/breakpoint tokens, a `Ticker→Timer` swap, a generic list helper, re-enabling lints, template-text cleanup, codegen for shell tokens, hover-state cleanup, a docstring fix, and one implement-or-remove call on `trend_chart.dart`.
- **Deployment Open Questions** (blocking the 18-June deploy plan's closure) — all still unanswered: rsync-path deprecation decision, multi-arch Docker build, how to handle private/proprietary packages in `ghcr.io` images, image-tag strategy.

## June 13 `TASKS.md` — remaining not-done items
- Zeta icon migration: ~660 raw `Icons.*` hits still remain (the T-ICON-2/3 sweeps of `neurocnl/frontend` and the remaining packages aren't done); the T-ICON-1 governance-spec files (`.kiro/specs/...`) were never created.
- CML Studio Workspace/Hub integration: not started, no code found — note this is the *reverse* direction from the already-done Studio→Hub "Share" flow; Hub owning the workspace lifecycle itself hasn't begun.
- Validation + Deploy Readiness Gate (ADR-0024-mandated): not implemented — a `ValidationPanel` exists but no gate/guard actually wired to it.
- NIR Bundle Architecture (`.nmtk` format): no production code, not prioritized.
- Akida/PYNQ Manage-Targets picker: `TASKS.md` itself still shows this as "AWAITING APPROVAL" — but round 1 already confirmed the underlying bugs are fixed in code. This is a doc/reality mismatch, not unbuilt work — worth a quick status update to the doc rather than treating it as a real gap.
- MCP service: Phase 2 (deployability check) partial; Phase 3 (simulation tool) and Phase 4 (deploy tool) not started.

## Release-gap backlog (`archive/June 2/RELEASE_GAP_ANALYSIS.md` + `REMAINING_EXECUTION_PLAN.md`)
Most P0s already shipped via Plans A/B/C1 — only what's still open:
- **P0 #5 — Neurochip has no validated hardware deployment path yet.** The one still-open P0; still just an investigation, no implementation plan written.
- P1 #10: Windows code signing + signed update channel — pending (macOS side is done).
- P1 #11/#12: neurocnl validation-panel deploy-readiness truth (doesn't surface "unsupported" as "Deploy Blocked") + pre-export capability check (`/api/export/preflight` doesn't exist, export dialog can show green when export would actually fail) — same root cause as the stub-converter gaps above.
- P1 #14: golden-path CI gate — `tests/integration/test_golden_path_1.py` doesn't exist yet.
- Per-module P1 items nothing else addresses: neurocnl training-pipeline bare `NotImplementedError` at `training_registry.py:128`; Neurosense encoding-preset honesty (disclaimers/provenance) + hardware-tier graceful degradation (BrainFlow/Prophesee); Neurohub team/private-lab repo mode + "open in Studio" deep-link; NDH reclassification-as-example + MuJoCo dependency gating; launcher backend-connection-mode (Local/Docker/K8s/Connect) end-to-end verification + doctor-as-hard-CI-gate; suite_api production CORS default (currently `*`) + rate/size limits; neurocli auth parity once suite auth is enforced; nmtk_ui_core dependency-version pinning + accessibility baseline.

## Frontend state-management migration candidates (`archive/June 2/frontend-state-management-review.md`)
Recommended in May, nothing since shows these migrated — still open:
- Async load/error → `AsyncNotifier`/`FutureProvider`: `nmtk/neuro_toolkit/lib/screens/environment_editor.dart`, `python_setup.dart`; `Neurohub/frontend/lib/screens/login_screen.dart`, `share_model_screen.dart`; `neurocnl/frontend/lib/screens/analysis_screen.dart`, `hardware_screen.dart`.
- Cross-widget app/nav state → `Notifier`/`NotifierProvider`: `nmtk/neuro_toolkit/lib/screens/tool_view.dart` (`_activeModuleId`, `_moduleLoadFailures`, `_controllers`).

## Fluff-cut tiers never acted on (`archive/June 2/2026-05-fluff-cut-analysis.md`)
- **Tier 1 (safe/high-yield):** delete module `deprecated/` folders (49 files across 7 modules); gitignore + relocate committed DBs/logs (`jobs.db`, `*.sqlite`, `server.log`, etc.); remove vendored stub dirs (`Neurosense/neurobench/`, `Neurosense/neurocnl/`); archive root scratch directories; drop committed `Neuro-Dream-Hand/site/` + `output/` build artifacts.
- **Tier 2 (product reframing):** cut Neurohub PM-chrome routers (`workflows.py`, `milestones.py`, `activity.py`, `notes.py`, `dashboard.py`) — consistent with the workflow-engine ADR already marked removed/deprecated this session; reclassify NDH as roadmap/example (neurocli's own reclassification is already done); merge the launcher's 4 setup screens into one flow; collapse `nmtk_ui_core`'s `neat/dark` + `neat/dark2` themes into one (same item as Wave B4d above — deliberately deferred, high blast radius).
- **Tier 3 (de-duplication):** `neurocnl/neurosim` vs `Neurosim/neurosim` — same mirror already decided "retire" earlier in this doc; consolidate duplicate Neurohub registry routers (`registry_auth`/`registry_health`); consolidate scattered doc trees (`docs/issues - future/`, `docs/issues-archive/`, `issues-archive/`, `docs/tasks/`).
