---
target: Execute > Deploy tab (Hardware/Simulator/Lava target tables)
total_score: 21
max_score: 40
na_heuristics: 
p0_count: 2
p1_count: 2
timestamp: 2026-08-18T09-22-59Z
slug: screens-studio-deploy-deploy-targets-overview-dart
---
Method: dual-agent (A: critique-assessment-a · B: critique-assessment-b)

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Status badges work, but "Ran" (hardware table) vs. duration+spike-count (simulator table) give wildly different amounts of info for what looks like the same column |
| 2 | Match System / Real World | 2 | "Trainable: Fixed" is raw backend vocabulary shown verbatim, no plain-language gloss |
| 3 | User Control and Freedom | 2 | No way to see or change *why* Lava is grouped where it is; Configure dialog is the only escape hatch |
| 4 | Consistency and Standards | 1 | 3 stacked DataTables, 2 different column sets (Trainable vs Settings), 2 different primary verbs (Configure vs Run), and Lava reuses the Hardware row shape purely for code-reuse reasons, not user meaning |
| 5 | Error Prevention | 3 | Run buttons correctly disable while running; preflight gates block bad runs |
| 6 | Recognition Rather Than Recall | 2 | User must remember/guess that Lava defaults to simulator mode — nothing on screen re-states it |
| 7 | Flexibility and Efficiency | 3 | "Run all" + shared-settings-cascade with per-row override (pin icon) is a genuinely strong power-user pattern |
| 8 | Aesthetic and Minimalist Design | 2 | Full bordered DataTable used even for a single-row table (Lava); heavy for the data density shown |
| 9 | Error Recovery | 2 | "Failed" badge on simulator rows gives no inline reason or link to logs |
| 10 | Help and Documentation | 1 | The hardware/simulator/hybrid taxonomy exists only in code comments — nothing in the rendered UI explains it |
| **Total** | | **21/40** | **Acceptable — functional, but the taxonomy this user is asking about is genuinely unclear** |

## Design Specificity Verdict

**LLM assessment**: This reads as a generic admin/CRUD table screen wearing neuromorphic labels — swap "Akida/PYNQ-Z2/snnTorch" for "Server A/Server B/Worker Pool" and it's indistinguishable from a Jenkins job list or Kubernetes node dashboard. The screen's own top-of-file comment describes the design goal as "real tables instead of one page per target reached through a dropdown" — a data-density decision, not a domain-modeling one. Nothing in the IA encodes the real distinction that matters (fixed silicon you pair with vs. software you configure-and-run vs. Lava's hybrid dual-mode default), only icon choice and label text do, and both of those are inconsistent (see below).

**Deterministic scan**: `detect.mjs` ran clean (exit 0, no findings) across all three source files — this is a taxonomy/IA problem, not something a mechanical linter catches. Code evidence confirms the mechanism precisely:
- Two `DataTable`s use the exact same widget class, `_HardwareTargetsTable` (`deploy_targets_overview.dart:178`), instantiated once for real hardware (line 83) and once, separately, for Lava alone (line 123) — same columns (`Target, Status, Results, Trainable, ''`), same "Configure" verb.
- The simulator table uses a different class, `_SimulatorTargetsTable` (line 311), with different columns (`Target, Status, Results, Settings, ''`) and a "Run" verb.
- `lava` is catalogued with `kind: 'hardware'` (`deploy_target_catalog.dart:103-107`) but deliberately excluded from `hardwareTargetIds` (`deploy_targets_overview.dart:25`) and rendered under the "Software Simulators" heading anyway — with **no heading of its own** between the simulator table (line 112) and the Lava table (line 123); lines 114-122 are just a `SizedBox` and a comment.
- Icon set mixes `Icons.*` (9 targets) and `ZetaIcons.*` (3 targets) with no hardware-vs-software boundary: Lava's icon is `settings_input_composite_outlined` (a sliders glyph, reads as neither chip nor software), and `nengo` (codegen) and `akida` (hardware) use the exact same icon, `Icons.hub_outlined`.

**Visual overlays**: Not applicable — this is a native Flutter desktop screen (no dev server, no DOM), so no browser injection was attempted. This is expected, not a gap in coverage.

## Overall Impression

The screen is functionally solid (run gating, shared-settings cascade, and run-all all work correctly) but fails at exactly the thing being asked for: a clean mental model of "what kind of thing is this row." The root cause is architectural, not cosmetic — Lava is rendered by borrowing the Hardware table's widget class for implementation convenience, which quietly asserts "Lava is like Akida/PYNQ" to the user even though the code's own comments say the opposite (it defaults to simulator behavior). The biggest single opportunity is collapsing the taxonomy decision into something visible on-screen — a Type badge or column — instead of leaving it encoded only in which of two widget classes happened to be reused.

## What's Working

- **Shared-settings cascade with per-row override**: one settings card feeds all simulator rows, with a pin-icon + tooltip ("Has its own settings, separate from the shared card above") clearly marking any row that's diverged. This is the one place on the screen that explains itself.
- **"Run all"**: reuses the same per-row `runSimulatorBackend` call rather than a separate code path, so the mental model ("Run all = every Run button pressed at once") is simple and reliably true.
- **Status badges** (`NmtkStatusBadge`): consistent icon+tone pairing, legible at a glance within each table.

## Priority Issues

**[P0] Lava/Loihi2 sits in a headerless table with no visual identity of its own.**
**Why it matters**: A user scanning top-to-bottom hits "Software Simulators" → run-all → shared settings → simulator table → then, with zero heading, a second full DataTable with different columns and a "Configure" button. This is the literal shape of "I can't tell what category this belongs to" — the exact complaint driving this critique.
**Fix**: Give Lava its own micro-heading naming its hybrid nature (e.g. "Lava / Loihi2 — simulator by default"), or fold it into a single unified table with a visible Type column instead of a third stacked DataTable.
**Suggested command**: $impeccable layout

**[P0] The hardware/simulator/hybrid taxonomy exists only in code comments, never in the UI.**
**Why it matters**: `deploy_targets_overview.dart:20-24` explains exactly why Lava is grouped where it is — but that reasoning is invisible to the person using the app. A first-timer has no way to learn "Lava defaults to sim mode" short of opening its Configure dialog and finding an internal toggle by accident.
**Fix**: Surface the distinction directly — a "Type: Hardware / Simulator / Hybrid" badge per row, or a one-line subhead under each section explaining what belongs there and why.
**Suggested command**: $impeccable clarify

**[P1] Column sets diverge in a way that asserts false sameness.**
**Why it matters**: Hardware Targets and the Lava table share identical columns and the "Configure" verb — visually claiming "these are the same kind of row" — while Lava's actual runtime behavior today is simulator-like, matching the *other* table's Run/Settings shape instead. The table shape answers "which widget class was reused" rather than "what is this to the user."
**Fix**: Pick columns by user-facing behavior (pairing vs. running), not by which class was cheapest to reuse.
**Suggested command**: $impeccable layout

**[P1] "Trainable: Fixed" is backend jargon with no user-facing meaning.**
**Why it matters**: The column mirrors an internal variable name; nothing on screen tells a first-time user what "Fixed" implies for their workflow (no training step happens for this target).
**Fix**: Replace with a plain-language label or add a tooltip ("This target runs a fixed pipeline — no training step").
**Suggested command**: $impeccable clarify

**[P2] Icon language has no hardware/software boundary, and one icon is an exact duplicate across categories.**
**Why it matters**: `nengo` (codegen) and `akida` (hardware) both use `Icons.hub_outlined`; Lava's sliders icon (`settings_input_composite_outlined`) doesn't read as hardware or software. Users can't pattern-match on icon shape the way the rest of the screen implies they should be able to.
**Fix**: Establish two icon families (chip/board glyphs for physical hardware, algorithm/graph glyphs for software) and audit the catalog against them; resolve the nengo/akida duplicate.
**Suggested command**: $impeccable colorize

## Persona Red Flags

**Jordan (First-Timer)**: Highest risk here. Jordan has no way to know Lava defaults to simulator mode and will very plausibly click "Configure" on the Lava row expecting a pairing flow like Akida/PYNQ, only to land in what's actually a simulator-oriented workspace by default — and the missing sub-heading means section position gives no clue either.

**Alex (Power User)**: Notices the Trainable/Configure-vs-Settings/Run mismatch within seconds and reads it as an unfinished or buggy screen rather than a deliberate design choice, which erodes trust in the rest of the table even though the run-gating and cascade logic underneath are solid.

## Minor Observations

- `TableBorder.all` renders on all three tables, including the single-row Lava table — heavier chrome than the data density (4 targets total) warrants.
- Hardware table's "Not run yet" and Simulator table's "—" em-dash are two different idioms for the same "hasn't run" state, one section apart.
- "SC-NeuroCore (Simulation)" and "SC-NeuroCore (FPGA RTL)" are named almost identically but land in entirely different tables with different icons (`ZetaIcons.memory_sharp` vs `Icons.developer_board_sharp`) — another seam a user has to parse from label text alone.
- Results column means two incompatible things across sections (binary Ran/Not-run-yet vs. duration+spike-count) under the same header.

## Questions to Consider

- If Lava's real behavior is "simulator by default, hardware when toggled," should the table system have a genuine third visual treatment for hybrid targets, instead of borrowing Hardware's shape wholesale?
- Is the current split — one DataTable per implementation convenience — actually serving the user, or is code reuse quietly dictating an information architecture that contradicts its own section headings?
- Would one unified table with a visible "Type" column (Hardware / Simulator / Hybrid) resolve this more directly than three visually-similar-but-structurally-different tables ever could?
