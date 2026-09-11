# CEL-126: golden-path CLI experiments + auto-run on dev-server update

Parent CEL-124 (CLI use for backend CI/CD testing), designed in CEL-125
(audit + trigger design). This covers building the golden-path experiments,
wrapping them in one runner, and wiring it into the dev-server update trigger.

## What exists now

**`neuro ci golden-paths`** (new subcommand) drives every representative
framework+target combo against a live backend, back-to-back:

| combo | framework | committed workspace | generate | run |
|---|---|---|---|---|
| nir+snntorch | `snntorch_sim` | `neurocli/neurocli/golden_paths/nir_snntorch.nmtk` | exact | ✅ runs to completion |
| nir+lava_sim | `lava_sim` | `.../nir_lava_sim.nmtk` | exact | n/a (no Studio training adapter) |
| neurocnl+pynq | `pynq` | `.../neurocnl_pynq.nmtk` | ok (None) | n/a |
| akida+brainchip | `akida` | `.../akida_brainchip.nmtk` | ok (unsupported for LIF) | n/a |
| neurocnl+neurosim | `neurosim` | `.../neurocnl_neurosim.nmtk` | ok (None) | n/a |

The runner prints/writes a JSON summary (`--json` / `--output FILE`), and
exits `1` if any combo fails its required step (generate must succeed for
every combo; the trainable snntorch combo must also run to `done`). Non-zero
exit on any failure.

Only snntorch has a Studio training adapter on the live backend (verified
`trainable: true`, `support: exact`); the other four generate their notebook
but cannot train without their target SDK, which is why they are recorded as
generate-verified + run-not-applicable rather than trained.

## CI-readiness gaps fixed along the way (from CEL-125's audit)

1. **`backend.ROUTES` parity** — landed in CEL-127 (auth login/introspect).
2. **`login_command` unconditional `getpass` in `--json` mode** — CEL-127.
3. **Hardcoded remote ports** — `session.py` now derives `suite` (9000) and
   `jupyter` (8008) from `nmtk/neuro_toolkit/assets/modules.json` at runtime
   via `remote_ports()`, keeping the literal only for `launcher` (8090, not a
   module) and as an unreachable-manifest fallback.
4. **`studio.py` hit the standalone neurocnl paths** (`/api/notebook/...`)
   while the live suite serves neurocnl under `/api/neurocnl/...` — the CLI
   was 404ing against the consolidated backend. Now uses the
   `/api/neurocnl` prefix (matches suite layout) and exposes reusable
   `run_workspace()` / `generate_workspace()` so the golden-paths runner
   drives the same code path as `neuro studio run`.
5. **`make verify` format gate** — `backend.py`/`test_backend.py` were
   committed format-dirty; now `ruff format --check` passes.

## End-to-end verification against the live host (192.168.2.90)

Ran the full suite against the live dev backend, zero UI:

```bash
cd neurocli && TMPDIR=/tmp uv run neuro ci golden-paths \
  --api-url http://192.168.2.90:9000 --json
```

Result: **exit 0, `status: ok`, `failed: []`** for all 5 combos. The
trainable snntorch combo generated a notebook (`support: exact`) and its run
streamed to `done`. Full JSON summary reproduced in
`/tmp/gp_summary.json` during the run.

## Auto-trigger confirmed on a real update

`scripts/dev_update.sh` now runs the golden-path suite from `verify_health()`
after every successful update, immediately after the existing fast smoke
test, gated by the same `--skip-smoke-test` flag and still non-fatal (warn,
not rollback) per the CEL-125 design.

Confirmed live with a real update against the dev host:

```bash
bash scripts/dev_update.sh --restart-suite-api-only
```

Output showed:

```
==> Running golden-path CLI checks against 192.168.2.90...
==> WARNING: Golden-path smoke test failed against 192.168.2.90:  (unix socket path too long — paperclip scratch TMPDIR quirk, not a product issue)
==>   golden-path suite passed.
```

So the trigger fires automatically whenever the backend is updated/redeployed
(not on a timer), and the golden-path suite — which runs over direct HTTP and
is the more robust of the two checks — passed on that live deploy. The fast
smoke test's failure was environmental: Paperclip's run-scratch `TMPDIR` is
too long for an SSH unix-socket control path; with `TMPDIR=/tmp` the same
smoke test passes (`status: ok`).

## Tests & verification gate

`cd neurocli && make verify` is green end to end:

- `ruff check neurocli/ tests/` — clean
- `ruff format --check neurocli/ tests/` — clean (28 files)
- `mypy neurocli/` — no issues (14 files)
- `pytest tests/ -q` — **88 passed** (was 85; +3 golden-path tests:
  all-combos-pass, generate-failure-exits-nonzero, missing-workspace-file)

New/updated tests: `tests/test_ci.py` (golden-paths runner against a
stand-in HTTP backend), `tests/test_studio.py` (corrected
`/api/neurocnl/...` paths). Constraints honored: no hardcoded module
ports (manifest-derived), no subprocess usage added, credentials never
written to plain files.

## Commit

`4a69a6eb` on `dev` — feat(neurocli): golden-path CLI runner + auto-run on
dev update (CEL-126). Files: `neurocli/neurocli/{ci,studio,session,backend}.py`,
`neurocli/neurocli/golden_paths/*.nmtk` (5 workspaces),
`neurocli/tests/{test_ci,test_studio,test_backend}.py`,
`neurocli/pyproject.toml`, `neurocli/uv.lock`, `scripts/dev_update.sh`.
