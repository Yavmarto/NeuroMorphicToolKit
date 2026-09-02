# Python Major Refactor — Remaining Stages (as of 2026-08-31)

Source plan: `current tasks/2026-08-25/python-major-refactor-plan.md`.
Stages 4, 5, 6 confirmed DONE (2026-08-27 through 2026-08-29 sessions).
Overall program: ~70% complete. This doc records what's left in the other
five stages, per the 2026-08-31 status audit, so it doesn't need
re-discovering later.

## Stage 3 — Shared backend boundary (DONE, closed 2026-08-31)

Mostly done: Suite API auth, launcher-control bearer-token gate +
loopback-default bind, `{code, message, request_id, retryable}` error
contract, `NMTK_DATA_DIR`-derived paths, async offload of blocking work —
all already in place and verified.

**Closed gap:** raw `sqlite3`/`aiosqlite` used directly (no typed
SQLAlchemy 2.0 repository layer) in four stores — all four migrated to a
typed SQLAlchemy 2.0 ORM layer (`<name>_db.py` + `<name>_store.py`/
`dataset_cache.py`), byte-identical public API/behavior, verified via
full test-suite regressions + ruff + mypy on each:
- `Neurochip/neurochip/app/services/deployment_store.py` (+ `deployment_db.py`)
- `neurocnl/neurosim/app/services/project_store.py` (+ `project_db.py`)
- `neurocnl/backend/app/services/job_store.py` (+ `job_db.py`)
- `neurocnl/backend/app/services/dataset_cache.py` (+ `dataset_cache_db.py`)

Risk closed: schema drift / column-type mistakes / silent corruption from
hand-written SQL, and no single enforced "one owner" pattern for these
four data stores. Table/column names kept identical since several tests
poke the raw SQLite file directly (`PRAGMA table_info`, direct `SELECT`).

## Stage 1 — Trustworthy baseline (NOT STARTED)

No recorded ruff/mypy/pytest/OpenAPI/launcher-doctor snapshot exists
anywhere in the repo. `current tasks/2026-07-28/mnist-fcn-baseline.md` is
an unrelated ML training baseline, not this.

**To do:**
- Record current Ruff/format/mypy/pytest results per module in one dated doc.
- Snapshot the OpenAPI schema and launcher-control JSON responses so
  future stages can diff against a known-good "before."
- Confirm no CI job silently tolerates Python failures (spot-checked
  2026-08-31: `.github/workflows/ci.yml` looked clean, no `continue-on-error`
  masking real test/lint failures — but this wasn't an exhaustive audit).

## Stage 2 — Vendor/paper tree replacement (DONE, closed 2026-08-31)

`tools/reference_assets.py` + `tools/reference_assets.lock.json` already
implement the full manifest (URL, pinned revision, checksum, license).
`neurocnl/backend/app/services/dataset_catalog.py` + `catalog.json`
already give NeuroCNL a proper dataset catalog.

**Closed gap:** `Neurohub/scripts/seed_hub_entries.py` hardcoded literal
`paper/03_rnn/data/ds_test.pt`-style paths (the gitignored, legacy vendor
tree that only exists after `tools/reference_assets.py fetch`) directly
into the two Braille Studio workspaces' `selectedDatasetPath` fields.
Fixed by adding `_copy_braille_dataset()`, which copies the source file
into `shared_assets/dataset/` once at seed time — same
`copy_to_storage()` pattern every other asset type in the script already
uses — so seeded workspaces reference a durable Neurohub-owned path
instead of the vendor tree; missing source now warns and leaves the field
unset rather than seeding a broken path. Verified via `--dry-run`
(confirmed both workspaces resolve `selectedDatasetPath` to
`shared_assets/dataset/ds_test.pt`) and ruff-check clean on the new code.

## Stage 7 — Remaining product Python (PARTIAL)

Akida SDK imports are already properly lazy everywhere (no top-level
`import akida` found anywhere in Neurochip/neurocnl).

**Closed 2026-09-02:** `Neurohub/scripts/seed_hub_entries.py` (was 1583
lines, one script mixing catalog data with the loader) split into
declarative seed documents + a small idempotent loader, per the plan's
stage 7 bullet. The 37 catalog entries (18 CNL specs, 9 benchmarks, 3
encoding presets, 3 studio workspaces, 6 projects) now live as JSON under
`Neurohub/scripts/seed_data/` (`cnl_assets.json`, `benchmark_assets.json`,
`encoding_presets.json`, `studio_workspaces.json`, `projects.json`),
validated on load against pydantic models in `seed_data/models.py`
(`extra="forbid"`, so a typo'd field fails fast instead of being silently
dropped). `seed_hub_entries.py` itself shrank to path resolution, the
source-file/dataset copy helpers, payload builders, HTTP POST, and the
CLI — no catalog data left in it. The extraction was done by importing the
live pre-refactor module and serializing its own catalog functions to JSON
(a temporary, since-deleted script), not hand-transcription, to rule out
copy errors across ~1100 lines of dict literals. Verified byte-identical
dry-run HTTP payloads before/after (only the `created_at`/`updated_at`
timestamps differ, expected since each run captures a fresh `NOW`), run
from both `Neurohub/` and the NMTK root, mypy clean relative to baseline
(fewer bare-`dict` findings than before, none new), and full `pytest` —
206 passed / 15 failed / 2 skipped, matching the already-documented
pre-existing Neurohub baseline exactly (none of the 15 touch this script).

**Remaining gap:**
- `Neurochip/neurochip/app/routers/pynq.py` (901 lines, 20 functions) and
  `akida.py` (747 lines) still carry business logic instead of being
  transport-only — needs the same router-thinning treatment already done
  for NeuroCNL's notebook router in stage 5.

## Stage 8 — Quality gates (PARTIAL)

Mypy strict already enabled package-by-package in `neurocnl/pyproject.toml`;
CI wrapper pattern (`scripts/ci/suiteapi.sh` style, invoked per-module)
already exists.

**Closed 2026-09-01:** `neurocli/pyproject.toml` and `Neurohub/pyproject.toml`
raised from `requires-python = ">=3.10"` to `>=3.11` (matching the rest of
the program), plus their `ruff`/`black`/`mypy` `target-version`/
`python_version` settings. Both venvs already run 3.14, so no interpreter
change; ruff check, mypy, and full pytest re-run on both modules — pre-existing
failures (16 `dict[type-arg]` mypy errors in `Neurohub`, 15 pytest failures in
`neurohub/tests/test_all_endpoints.py`/`test_assets_router.py`) confirmed
identical with the bump reverted, so unrelated to this change.

Side effect worth a follow-up slice (not fixed here — out of scope for a
"bump the floor" change, would touch 13 files across `Neurohub/neurohub/`):
raising `Neurohub`'s ruff `target-version` to `py311` unlocked 18 new
pyupgrade findings (16× `UP017` `timezone.utc` → `datetime.UTC`, 2× `UP042`
`class X(str, Enum)` → `StrEnum`) that were previously hidden by the `py310`
target. All auto-fixable; low-risk mechanical cleanup whenever picked up.

**Remaining gap:** No ADR exists for storage/job ownership (checked
`docs/ADR-*` and `neurocli/docs/ADR-*`) — the plan calls for one recording
the "one authoritative owner per database/job/artifact" decision.

## Suggested order after Stage 3

1. Stage 2's seed-script path fix (small, isolated, unblocks nothing else
   but closes a near-done stage).
2. Stage 8's Python-floor bump for neurocli/Neurohub (mechanical, low risk).
3. Stage 7's NeuroHub seed-script rewrite (bigger, same shape as stage 2's
   fix but the full declarative-loader design).
4. Stage 7's Neurochip pynq.py/akida.py router thinning (same pattern as
   stage 5, proven playbook).
5. Stage 1's baseline snapshot + Stage 8's storage/job ADR (documentation-
   heavy, best done once the data-layer work above has settled so the
   snapshot reflects the post-refactor state, not a moving target).
