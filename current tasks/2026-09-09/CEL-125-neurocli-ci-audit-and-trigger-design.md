# CEL-125: neurocli CI-readiness audit + dev-server auto-run trigger design

Parent: CEL-124. Hands off to CEL-124b (Engineer) for implementation.

## Part 1 — Audit: does neurocli meet ADR 0004 in practice?

Ran `uv sync --extra dev` + `ruff check` / `mypy` / `pytest` from `neurocli/`
(the Makefile's `install` target shells out to `python`, which doesn't exist
on this machine — only `python3`/`uv` — so `make verify` itself failed at the
first step here; `uv` gets the same three checks running).

**ruff: clean. mypy: clean.**

**pytest: 1 failure of 81** — this is a real, current gap, not a style nit:

- `tests/test_backend.py::test_routes_cover_every_launcher_endpoint_the_app_calls`
  fails. `backend.ROUTES` (the CLI/app parity table, `neurocli/backend.py`) is
  missing `/api/launcher/auth/login` and `/api/launcher/auth/introspect`,
  which the launcher app already calls. AGENTS.md is explicit: "Adding an
  endpoint to the app means adding one line there." Two lines are missing.
  **This alone means neurocli currently fails its own verification gate** —
  a CI job that runs `make verify`/`uv run pytest` on this repo today is red.

Other findings, in descending severity:

2. **`neuro backend login` prompts unconditionally in `--json` mode**
   (`backend.py`, `login_command`): `password = getpass.getpass(...)` runs
   with no `json_mode` guard. Contrast with `neuro hub login` (`hub.py:158-167`),
   which correctly checks `if json_mode: error_exit(...)` before falling back
   to `typer.prompt`. In a headless CI runner with no tty, `getpass.getpass`
   either raises or blocks — `--json` does not save you here. This is the one
   command in the audited surface that violates "zero interactive prompts."

3. **Hardcoded infra ports duplicate `modules.json`**: `session.py:39`
   defines `REMOTE_PORTS = {"launcher": 8090, "suite": 9000, "jupyter": 8008}`
   as a literal dict. `suite` (9000) and `jupyter` (8008) are already present
   in `nmtk/neuro_toolkit/assets/modules.json` — this is a second source of
   truth that can silently drift from the manifest. (`launcher` at 8090 isn't
   in modules.json at all — it's not a "module," so that one may be
   unavoidable as a literal; the other two aren't.) The various
   `http://127.0.0.1:PORT` fallback constants in `deploy.py`, `hub.py`,
   `lifecycle.py`, `studio.py` are fine — they're env-var-overridable local
   defaults, not the ports/paths the constraint is about.

4. **`Makefile`'s `install` target calls `python`, not `python3`**. Harmless
   on hosts where `python` resolves (many Linux CI images symlink it), but
   fails outright here, and PEP 668 (`externally-managed-environment`) blocks
   a plain `pip install` on this machine's Homebrew Python regardless — `uv`
   sidesteps both. Worth switching `Makefile` to `uv sync`/`python3` so
   `make verify` is the reliable single entry point ADR 0004 implies it is.

Exit codes (0/1/2) and `--json`-on-every-path were spot-checked across
`cli.py`/`backend.py`/`hub.py`/`lifecycle.py` via `output.error_exit` — this
part holds up; every command routes errors through the shared helper with a
`code` argument, and the one exception found is #2 above (a missing guard,
not a missing `--json` output shape).

## Part 2 — Design: trigger a golden-path CLI run on dev-server update, not a timer

### How the dev backend actually gets updated today

`scripts/dev_update.sh` is the real deploy path (`make dev-update` runs it) —
`docker-ex-deploy`/`run_dev.sh` are deprecated per root AGENTS.md.  It:

1. runs changed-module tests locally, syncs source to
   `moosebun2@192.168.2.90:~/nmtk-deploy` via rsync, classifies what changed,
   rebuilds/restarts only the affected `docker compose` services (or does an
   app-managed image swap if the host is running the app-provisioned stack),
2. then **always** finishes a successful run — normal path, the
   nothing-changed shortcut, and `--restart-suite-api-only` — by calling
   `verify_health()`, which polls `http://<host>:9000/api/suite/health` and
   (unless `--skip-jupyter-check`) `check_jupyter_health()` on `:8008`.

`verify_health()` is the single choke point every successful update path
already funnels through. That makes it the natural trigger site — the
alternative (adding the call at each of the three `main()` call-sites
individually) is strictly more code for the same effect.

### Proposed mechanism

Add one function, call it from inside `verify_health()`, after the existing
Jupyter check:

```bash
# in verify_health(), after check_jupyter_health "$host_ip"
$SKIP_SMOKE_TEST || run_golden_path_smoke "$host_ip"
```

```bash
run_golden_path_smoke() {
  local host_ip="$1"
  log "Running golden-path CLI smoke test against $host_ip..."
  local out
  if out="$(cd "$REPO_ROOT/neurocli" && uv run neuro ci smoke-test \
      --target "$host_ip" --json 2>&1)"; then
    log "  smoke test passed."
  else
    warn "Golden-path smoke test failed against $host_ip:"
    printf '%s\n' "$out" | sed 's/^/      /' >&2
    warn "  backend deploy itself succeeded — this is a smoke-test failure, not a rollback trigger."
  fi
}
```

Design choices, and why:

- **No scheduler, no new service.** This is a shell function call inside a
  script that already runs on every update — zero new moving parts, matches
  "smallest mechanism."
- **`--skip-smoke-test` flag**, mirroring the existing `--skip-tests` /
  `--skip-jupyter-check` pattern in this same script, for symmetry and so a
  known-flaky smoke test doesn't block iterating on unrelated changes.
- **Non-fatal (`warn`, not `die`).** The backend is already live by the time
  `verify_health` runs; a smoke-test failure is a signal to look at, not a
  reason to fail a deploy that already succeeded. `report_jupyter_failure`'s
  "print WHY, not just THAT" convention is reused (dump the CLI's `--json`
  error body inline) instead of inventing a second failure-reporting shape.
  Non-zero exit code for real infra failure vs. `warn`+continue for a smoke
  failure keeps `die` meaning what it already means in this script.
- **The `neuro ci smoke-test` command itself doesn't exist yet** — this issue
  designs the trigger, not the fixture. CEL-124b owns building that command
  (golden-path steps: connect, list modules, hit a representative endpoint —
  scope TBD by CEL-124b) plus fixing the two audit gaps above (#1 is the one
  that should land first; it's a two-line `ROUTES` fix and unblocks a green
  `make verify`).

### Handoff to CEL-124b

Scoped to CEL-124b: fix `backend.ROUTES` (finding #1), guard the `getpass`
call in `login_command` (finding #2), build `neuro ci smoke-test` (or
equivalent), and wire the `verify_health()` call + `--skip-smoke-test` flag
above into `scripts/dev_update.sh`. Findings #3/#4 are lower-severity cleanup
CEL-124b can take or leave.
