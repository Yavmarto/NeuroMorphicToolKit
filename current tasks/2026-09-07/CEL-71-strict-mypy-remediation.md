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

Current state: **550 → 279 errors**, 0 of them `no-untyped-def`.

Remaining buckets (from `/tmp/mypy_out6.txt` breakdown, will differ
slightly by the time you re-run since paths under `/tmp` don't persist):

| code | count |
|---|---|
| type-arg | 121 |
| arg-type | 68 |
| no-any-return | 24 |
| union-attr | 16 |
| assignment | 12 |
| index | 8 |
| no-redef | 7 |
| comparison-overlap | 6 |
| call-arg | 5 |
| unused-ignore | 4 |
| misc | 3 |
| attr-defined | 3 |
| name-defined | 2 |

Commits (all on `dev`, in order):
- `d3589dcc` — 167 mechanical `-> None` fixes
- `ffb519bb` — test_run_simulation, test_converter, teensy properties
- `8f6ce187` — hypothesis strategies + test_compile tmp_path
- `24873aa2` — generation tests, capabilities dict, spinnaker2 exporter
- `1e911728` — remaining export/nir_native_cnl no-untyped-def (closes the bucket)

## Suggested next pass

`type-arg` (121, biggest remaining bucket) is next-most mechanical: bare
`dict`/`list`/`np.ndarray`/`UserDict` etc. missing type parameters. Same
approach — grep the mypy output for `[type-arg]`, group by file, fix in
small verified batches, commit per batch. `arg-type` (68) will need more
judgement since it's usually a real type mismatch, not just a missing
annotation — some of what surfaced in this session (e.g. the
`list[NIRNodeRecord | NIREdgeRecord]` vs `list[NIRNodeRecord]` invariance
issue in `_weight_init_helpers.py`) is representative of what's left in
`nir_native_cnl`.

After every bucket is at 0, hand back to CEL-66 to do the actual
`pyproject.toml` flip and confirm `python -m mypy neurocnl` is clean with
the real committed config (no scratch file needed at that point).
