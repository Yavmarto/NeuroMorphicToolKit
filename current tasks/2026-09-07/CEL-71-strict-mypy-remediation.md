# CEL-71: neurocnl strict-mypy remediation

## What this is

CEL-66 wants to flip `neurocnl/pyproject.toml`'s `[tool.mypy]` to a real
strict config (`strict = true`, `disable_error_code = ["import-untyped",
"no-untyped-call"]`, no per-package overrides). That flip currently
exposes latent errors because the old 19-entry top-level
`disable_error_code` list was silently unioned under every per-package
`strict = true` override. This issue is the remediation work: fix the
real errors so the flip in CEL-66 becomes a no-op config change.

**Do not edit `neurocnl/pyproject.toml`'s `[tool.mypy]` section as part of
this issue** — that flip belongs to CEL-66 and should only happen once
this issue reports 0 errors.

## How to reproduce the target-strict error count

The committed `pyproject.toml` still has the lenient top-level
`disable_error_code` (19 entries) plus per-package overrides. To see the
*real* error count under the target strict config without touching the
committed file, copy `pyproject.toml` to a scratch file, shrink its
`[tool.mypy]` `disable_error_code` to
`["import-untyped", "no-untyped-call"]` (leave everything else,
including the per-package override blocks, alone — mypy unions codes, so
this alone reveals every error the overrides were also hiding), then run:

```bash
cd neurocnl
python -m mypy --config-file /path/to/scratch-pyproject.toml neurocnl
```

(Needs a venv with `pip install -e /path/to/nmtk_contracts -e ".[dev]" "numpy<2" matplotlib`
— `nmtk_contracts` lives at the monorepo root, not inside `neurocnl/`.)

Note: the `mypy`/`grep`/etc. shell commands in this repo are transparently
rewritten by the user's `rtk` Claude Code hook. For anything where exact
byte-for-byte output matters (grepping mypy output, checking error
counts), prefix with `rtk proxy` (e.g. `rtk proxy python -m mypy ...`) —
the un-proxied path can silently reformat/garble output.

## Progress so far (this session)

Starting point: 550 errors / 68 files (matches the issue description
exactly).

Fixed the entire **no-untyped-def bucket**: 258 → 0 errors. Mechanical
pass in two stages:

1. Auto-fixed 167 cases where mypy's note said `Use "-> None"` (pure
   `-> None` insertions on already-annotated-elsewhere functions) via a
   small script (not committed — scratch, deleted after use).
2. Manually annotated the remaining ~91 cases (missing param types too):
   pytest fixtures, hypothesis `@st.composite` `draw` callbacks,
   `unittest.mock` patches, `__getattr__`, a custom `UserDict` subclass,
   and `**kwargs`. Files touched are all in the 6 commits below.

Along the way, fixing `test_round_trip_properties.py`'s
`_toggle_keyword_case` surfaced a **real latent bug**: the inner lambda's
`kw=kw` default arg (needed to avoid the classic late-binding-closure bug
in the `for kw in _KEYWORDS` loop) had been dropped by an earlier edit;
restored it via a nested `def` with an explicit default.

Current state (end of second heartbeat this session): **550 → 145 errors** (74% reduction), 0 of them `no-untyped-def`.

### Second heartbeat: integrating two parallel worktree agents

Mid-session, a board review comment (on this same issue) surfaced that
two other agents had been working the same issue in parallel via git
worktrees under `neurocnl/.claude/worktrees/` — `agent-ac894339cbd65c343`
(test files) and `agent-af207f9c6e7828554` (source files, backend
routers/schemas/services + neurocnl converter/layers/pipeline/runtime) —
both terminated mid-task by an Anthropic session-quota reset, leaving
real uncommitted progress stranded in their worktrees.

Integrated both via `git diff` (from inside each worktree, scoped to
files not already covered by this session's own commits) piped into
`git apply --3way` on the main checkout. ~11 files turned out byte-identical
between the worktree and main already (no-op, skipped); a handful of
real 3-way conflicts were resolved by hand — see commits `8b5123f3` and
`2ec69545` for the reasoning on each (one conflict in
`neurosim/app/routers/custom_nodes.py` would have silently replaced a
real 400-error branch with a bare `assert`; kept the existing correct
behavior). One file's fix (`test_compiler_weight_init.py`) was dropped
entirely — the file no longer exists on `dev` (split into three files by
commit `5824f9bb` after the worktree branched), so resurrecting it would
reintroduce dead code.

**Worktree gotcha for next time**: `cd` into a worktree to inspect it,
then `cd` back to the main checkout with an explicit absolute path
before running anything else — the Bash tool's cwd persists across
calls, and running `git worktree list` / `git branch --show-current`
without pinning cwd first can make you think the main branch's history
got reset when you're actually just still sitting inside a linked
worktree.

Both worktrees were removed after integration (`git worktree remove
--force`) since everything usable was extracted and committed.

Remaining buckets (from `/tmp/mypy_final.txt`, paths under `/tmp` don't
persist across sessions):

| code | count |
|---|---|
| arg-type | 58 |
| type-arg | 34 |
| no-any-return | 11 |
| union-attr | 10 |
| index | 8 |
| assignment | 8 |
| unused-ignore | 4 |
| call-arg | 4 |
| attr-defined | 3 |
| no-redef | 2 |
| name-defined | 2 |
| misc | 1 |

Commits (all on `dev`, in order):
- `d3589dcc` — 167 mechanical `-> None` fixes
- `ffb519bb` — test_run_simulation, test_converter, teensy properties
- `8f6ce187` — hypothesis strategies + test_compile tmp_path
- `24873aa2` — generation tests, capabilities dict, spinnaker2 exporter
- `1e911728` — remaining export/nir_native_cnl no-untyped-def (closes the bucket)
- `8b5123f3` — integrated source-file fixes from worktree agent-af207f9c
- `e2a8cdf7` — fixup: redundant-cast vs no-any-return on `_bin_sample`
- `2ec69545` — integrated test-file fixes from worktree agent-ac894339

## Third heartbeat: 145 → 0 errors — issue closed

Worked through every remaining bucket file-by-file (arg-type, type-arg,
union-attr, no-any-return, assignment, unused-ignore, call-arg,
attr-defined, no-redef, name-defined, misc), verifying with mypy +
pytest and committing per batch. `python -m mypy neurocnl` now reports
**0 errors** under the target strict config
(`disable_error_code=["import-untyped","no-untyped-call"]`, no
per-package overrides) — the exact config CEL-66 wants to flip
`pyproject.toml` to.

Commits (continuing from the list above, all on `dev`):
- `d162a58f` — test_layer2_validator ParsedSentence fixtures (25 arg-type)
- `06a1efa3` — _CompilerRecord unions in shape/diagnostic property tests
- `11656d1b` — dict/ndarray type-args in pynq contract + array-serialisation tests
- `cd303ea5` — no-redef fallback import, Optional int(), anthropic cast
- `12dcc5e2` — intentional-validation-error contract tests (call-arg ignores)
- `4ce6f2c1` — weight-init test suite typing + legacy_rng_state() helper
- `f7348d5b` — union-attr narrowing, compact_metadata casts
- `04414c81` — three shadowed-variable bugs (checker/pop/src_sig)
- `3b820810` — missing tuple comma, duplicate annotation, untyped SDK cast
- `b49838f4` — explicit re-exports (parser/visualization), tuple literals
- `f0aca194` — real missing-argument bug in Lava rejection tests
- `f5c7820e` — PYNQ weight-typing gaps (exporter/planner/tests)
- `e845430d` — last error (frozen-dataclass test, type: ignore[misc])

### Found but explicitly NOT fixed (out of CEL-71's mypy-remediation scope)

`neurocnl/export/nir_exporter.py`'s `ONLINE_LEARN_BACKENDS` derivation
(`_derive_online_learn_backends()`) appears to produce an **empty set**
at runtime today: `BACKEND_CAPABILITIES` marks every backend's
`stdp_learning` as `"approximate"`, never `"faithful"`, so the derived
set is always empty, silently discarding the hardcoded
`{"lava","loihi","loihi2"}` fallback the code comments document as
intentional (`# ponytail: hardcoded — capabilities registry marks stdp
as "approximate" for all backends`). This means
`validate_deployment_mode_fidelity` currently rejects `online_learn`
deployment mode for every backend including Lava/Loihi. Only fixed the
*type* mismatch (bare `set` → `frozenset`), preserved the exact
existing (buggy-looking) runtime behavior — deciding whether the
hardcoded set or the derived one should win is a product call, not a
mypy fix. Worth a follow-up issue if this deployment mode is actually
used anywhere yet.

## Handoff to CEL-66

Ready: delete the per-package `[[tool.mypy.overrides]]` blocks in
`neurocnl/pyproject.toml`, shrink the top-level `disable_error_code` to
`["import-untyped", "no-untyped-call"]`, confirm `python -m mypy
neurocnl` reports 0 errors with the real committed config (should
match this session's scratch-config result exactly), confirm
`test-neurocnl-backend` CI still gates on it.
