# ADR / Open Brain / README Alignment Audit — 2026-07-16

Full-repo check of whether Open Brain (gbrain), the ~90 ADR files across all modules, and the module READMEs still match the current code. Six parallel sub-agent audits covered every module's ADR directories (`ADR-claude`/`ADR-Codex`/`ADR-Gemini`); two more covered ADR/gbrain location and README-vs-code drift. Findings below are grouped by area. Where an ADR was found stale, a "Status Update (2026-07-16 audit)" section has been appended to the ADR file itself rather than rewriting its history — see the companion fix pass for the exact files touched.

## 1. Open Brain (gbrain)

- CLI installed (`gbrain 0.42.15.0`), config at `~/.gbrain/config.json`, engine `pglite`.
- **Only 5 pages exist in the entire brain**, 0 embedded (embedding was deferred at `/setup-gbrain` time on 2026-06-03 and never turned on — no `OPENAI_API_KEY`/`VOYAGE_API_KEY` set). `gbrain search` is therefore keyword/tsvector matching only, not semantic — searches for "README" or "repo policy" return nothing even though relevant content exists in the repo, simply because the literal words aren't in the 5 stored pages.
- Of the ~90 ADR files in the repo, **exactly one** (`docs/ADR-claude/0029-no-additional-settings-screens.md`) has a corresponding gbrain page (`no-additional-settings-screens-decision`, tagged `adr-0029`) — and that one is accurate and well-mirrored. The other ~89 ADRs have no gbrain presence at all.
- `CLAUDE.md` instructs checking Open Brain at the start of every task; `AGENTS.md` instructs writing gbrain entries for sync-sensitive changes. Neither instruction is producing much value right now given how sparse the brain is — an agent following "check gbrain first" gets almost nothing back except the settings-screen decision, `deploy-standard-command-docker-ex-m`, `nmtk-end-user-convenience-principle`, and one training-loop invariant note.
- **Recommendation (not executed — external personal store, needs your call):** run `gbrain sync --repo /Users/yoshimartodihardjo/NeuroMorphicToolKit` to backfill the ADR corpus, and set an embedding key so search stops being keyword-only.

## 2. ADR drift, by module

Each item below has file:line evidence gathered during the audit; the corresponding ADR file now also carries a "Status Update (2026-07-16 audit)" section with the same evidence.

### Root (`docs/ADR-claude/`)
- **0030 (Dynamic Training Graph Executor):** built in `neurocnl` on 2026-07-13, then fully deleted the same day (commit `676ebaf2`) — logic was ported into `notebook.py` codegen instead. ADR still says "Accepted."
- **0024 (validation gate):** Deploy-path gating still holds; the Training-path half describes `TrainingInspectorPanel`, which no longer exists — canvas-DAG training now runs exclusively through pipeline step 6.
- **0017 (desktop shell adapter contract):** no `ShellModuleAdapter` class/interface exists anywhere; each module has its own independently-named adapter with no shared base type.
- **0022 (remove `import_network` fallback):** cites a deleted file path (`Neurochip/frontend/lib/services/import_network_payload.dart`); the underlying decision holds, logic now lives in the Neurochip feature package.
- **0026 (canvas-driven notebook generation):** names a nonexistent `_node_var()` helper; real function is `_python_identifier()` with a different prefix string.
- **0029 (no additional settings screens):** low severity — an orphaned, unrouted `settings_screen.dart` exists in Neurohub's frontend but isn't a live contradiction.

### neurocli / neurocnl
- **neurocli 0001/0002:** the documented flagship example (`--framework lava --target loihi2`) doesn't match any real combo in `new.py`'s `_COMBOS`.
- **neurocli README claim:** `uri_parser.py` "byte-for-byte equivalent" with Neurohub's copy is false — 7 vs 8 artefact types, a real functional gap (`hub push --type custom_node` fails CLI-side).
- **neurocnl 0001 (regex parser):** superseded by the NIR-native parser; `cnl_grammar.md` no longer exists.
- **neurocnl 0002 (three-layer validation):** invariant count and hardware-specific validators (loihi/akida/spinnaker/teensy) were removed 2026-07-04 as dead code.
- **neurocnl Gemini-0002:** misattributes an LLM parse stage to `planner.py` (that file is capability planning only; parsing is deterministic).
- **neurocnl Gemini-0003:** cites a nonexistent `validation` submodule; enforcement actually lives in `layers/`.

### Neuro-Dream-Hand / Neurobench
- **NDH claude-0003:** `stdp_learning.py` implements BCM, not STDP, despite the ADR's title and description.
- **NDH Gemini-0002:** describes an edge-autonomy hardware state machine that doesn't exist; real code is a synchronous lockstep bridge plus a separate human-blending state machine.
- **NDH README:** dangling `STATUS.md` link — file doesn't exist.
- **Neurobench claude (backends):** claims uniform httpx dispatch across all targets plus MuJoCo support; reality is two targets over httpx, three over in-process SDK imports, and no MuJoCo router at all.
- **Neurobench claude (metrics):** claims an 8-value `AllowedMetric` enum; reality is a 16-value `Literal`, not an enum.

### Neurosim / Neurochip
- **Neurosim claude-0002, claude-0006, Gemini-0003, Codex-0001:** all describe deleted services (`graph_to_cnl.py`, `neurocnl_bridge.py`) or a standalone Flutter frontend that never existed (canvas UI is actually embedded in `neurocnl/frontend`).
- **Neurosim mirror desync (not ADR-specific, code issue):** `Neurosim/neurosim/` is genuinely missing several files present in canonical `neurocnl/neurosim/` (schemas, services, tests) despite the README's sync guarantee. **Not fixed in this pass — flagged below as a follow-up decision.**
- **Neurochip claude-0009:** wrong generator filenames (`lava_generator.py` doesn't exist; `akida_simulator.py` is a CI test double, not the real generator); several real generators go unmentioned.
- **Neurochip Gemini-0003:** conflates the `/export/teensy` endpoint (just builds a zip) with the actual flash/upload logic (lives in `flash_service.py`, a different router).

### Neurohub / Neurosense
- **Neurohub claude-0001, 0003, 0004:** the worst drift found. A whole workflow/milestone/notes feature — DB tables, background worker, service-discovery client — was dropped via migration `c2d4e5f60002_drop_pm_workflow_tables.py`. `suite_client.py` is dead code with zero live callers; frontend widgets `workflow_step_card.dart`/`milestone_timeline.dart` are orphaned. None of these three ADRs carried a supersession marker.
- **Neurohub claude-0002:** minor — uses `bcrypt` directly, not via `passlib`; secret key defaults to empty string with a production fail-fast, not a hardcoded fallback.
- **Neurosense claude-0001:** claims a 2-tier support-level system; reality is 3 tiers (validated/experimental/prototype).
- **Neurosense claude-0002 / Gemini-0003:** claims delegation to `neurocnl`'s spike-encoding module; code never imports `neurocnl` at all — pure NumPy/SciPy, no fallback branch.
- **Neurosense Gemini-0002:** claims a 30-second ring buffer; reality is a 5-item `asyncio.Queue` for backpressure only.

### nmtk / nmtk_ui_core
- **nmtk claude-0004:** its own supersession note points to paths that don't exist under `nmtk/docs/`; the WebView→native migration it describes is incomplete (2 of 6 modules still fall back to WebView).
- **nmtk claude-0007:** cites Neurochip deploy-UI file paths that don't exist (`Neurochip/frontend/` is an empty stub) — superseded by the later CNL-Studio-owns-deployment architecture, unmarked.
- **nmtk claude-0001:** module state machine has 9 states, not 8 (missing `degraded`).
- **nmtk claude-0002 / 0005:** already superseded per ADRs 0006/0007's own text, but 0002/0005 themselves carried no reciprocal pointer.
- **nmtk_ui_core claude-0001:** barrel export order doesn't follow the claimed theme→models→widgets convention.
- **nmtk_ui_core claude-0002/0003:** claims a `google_fonts` runtime dependency that doesn't exist; real dependencies include `zeta_flutter` and a local Rust FFI plugin.

## 3. README / doc drift (independent of ADRs)

- Root `README.md`: module list omitted real modules (Neurosim); linked a nonexistent `SETUP_GUIDE.md`.
- `neurocnl/examples/README.md`: documented `03_generate_network.py`/`04_full_pipeline.py`, neither of which exists.
- `neurocli/README.md`: broken example command and false byte-for-byte claim (see ADR section above).
- `Neuro-Dream-Hand/README.md`: dangling `STATUS.md` link.
- Seven frontend/plugin READMEs were unedited scaffolding boilerplate despite real code underneath: `Neurohub/frontend`, `neurocnl/frontend`, all 6 `nmtk/packages/*_feature`, `rust/nmtk_wgpu_renderer_plugin`.
- `nmtk_ui_core/README.md`'s dependents list was inconsistent with `CODING_STYLE_GUIDE.md`'s shell-mode table regarding Neurochip.

All of the above have been corrected in this same pass (see the six agent reports for the exact diff per file).

## 4. Not fixed — needs a decision

1. **Neurosim mirror desync.** `Neurosim/neurosim/` is missing real files (`schemas/canvas.py`, `schemas/components.py`, `schemas/export.py`, `schemas/preview.py`, `schemas/projects.py`, `schemas/sweep.py`, `services/chip_targets.py`, `services/topology_cascade_generator.py`, several test files) that exist in canonical `neurocnl/neurosim/`. This is a code-sync action, not a doc fix, and copying files across module boundaries risks masking a real merge conflict — recommend deciding explicitly whether to re-sync or retire the mirror entirely.
2. **gbrain backfill.** See section 1 — running `gbrain sync --repo` and setting an embedding key would make Open Brain actually useful, but that's a change to your personal external knowledge store outside this repo, so it wasn't run automatically.
3. **Orphaned dead code** surfaced during the audit but out of scope for a docs-only pass: `Neurohub/neurohub/app/services/suite_client.py`, `Neurohub/frontend/lib/widgets/workflow_step_card.dart` + `milestone_timeline.dart`, `Neurohub/frontend/lib/screens/settings_screen.dart`, and the empty `Neurochip/nmtk_ui_core/` placeholder directory. All are candidates for straightforward deletion in a follow-up cleanup task.
