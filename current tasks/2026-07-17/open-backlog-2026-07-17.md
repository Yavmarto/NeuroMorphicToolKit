# Open Backlog — 2026-07-17

Consolidated rollup of every genuinely-still-open item found while cleaning up `current tasks/` (full read of all 33 folders / 72+ files, cross-checked against the `2026-07-16` ADR/README/gbrain audit and the full ~132-file ADR corpus). Same purpose as `June 13/TASKS.md` and `20 june/open-items-consolidated.md` before it — this is the current live rollup; treat those two as historical.

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
