# Python Major Refactor Handoff — 2026-08-26

## Purpose

This document hands off the behavior-preserving Python refactor defined in
[`../2026-08-25/python-major-refactor-plan.md`](../2026-08-25/python-major-refactor-plan.md).
The program is approximately **49% complete**, weighted by remaining complexity rather than
file count or number of milestones. Most completed work improves safety, ownership, testability,
and failure handling; it deliberately does not introduce a major new end-user workflow.

## Current checkpoint

The working tree is at a buildable and testable launcher-control checkpoint. Public HTTP paths,
successful response bodies, launcher JSON casing, settings-file keys, CLI behavior, deployment
progress events, and `cleanInstall` semantics have been preserved. No data migration is required.

The implementation is **not committed**. The working tree also contains substantial unrelated
Dart, Suite API, documentation, and `neurocnl` submodule changes made by other workstreams; do not
discard, reformat, stage, or include those changes when continuing this refactor.

## What has been completed

### 1. Verification, security, and persistence foundations

- Established useful launcher characterization coverage and reliable launcher guardrails.
- Hardened the external launcher boundary and retained the distinction between a blocking
  `preflight failed` result and a non-blocking `degraded optional capability` result.
- Established typed settings and persistence foundations while retaining existing stored field
  names and restart behavior.
- Preserved optional hardware/runtime imports so an unavailable SDK degrades capability reporting
  instead of preventing launcher startup.

These foundations are materially complete but not the end of milestones 1 and 3: repository-wide
baseline closure, shared job contracts, database ownership, async blocking-work removal, and
standardized errors still have outstanding work outside launcher-control.

### 2. Launcher typed-state foundation

- Replaced key dictionary-driven launcher internals with typed settings, hardware records, status
  values, and service protocols.
- Moved shared constants and normalization helpers out of the server module.
- Removed service-to-server circular dependencies and extracted hardware discovery.
- Reduced `nmtk/launcher_control/server.py` to 492 lines while keeping compatibility exports and
  route behavior stable.

### 3. Deployment executor split

- Reduced `deployment_executors.py` to a 34-line compatibility façade.
- Added separate standalone, Docker, and Kubernetes executors.
- Added a shared typed command runner and immutable result with bounded retained output, timeout
  state, and secret redaction.
- Kept factory signatures, executor classes, progress events, errors, and `cleanInstall` behavior
  compatible.

Owning files:

- `nmtk/launcher_control/deployment_executor_base.py`
- `nmtk/launcher_control/deployment_executor_factory.py`
- `nmtk/launcher_control/deployment_executor_standalone.py`
- `nmtk/launcher_control/deployment_executor_docker.py`
- `nmtk/launcher_control/deployment_executor_kubernetes.py`
- `tests/launcher_control/test_deployment_executor_boundaries.py`

### 4. Akida host boundary split

- Reduced `akida_host_service.py` from a 1,300-line mixed-responsibility service to a 297-line
  compatibility façade.
- Extracted host persistence and default selection into a repository.
- Extracted bounded SSH, SCP, and HTTP transport into a remote client with secret-safe diagnostics.
- Extracted pure preflight evaluation, provisioning coordination, and runtime proxy behavior.
- Preserved host CRUD, selection, password handling, same-host gateway rewriting, token recovery,
  provisioning stages, restart behavior, runtime proxy payloads, and legacy private test delegates.

Owning files:

- `nmtk/launcher_control/akida_host_repository.py`
- `nmtk/launcher_control/akida_remote_client.py`
- `nmtk/launcher_control/akida_preflight.py`
- `nmtk/launcher_control/akida_provisioning.py`
- `nmtk/launcher_control/akida_runtime_proxy.py`
- `tests/launcher_control/test_akida_service_boundaries.py`

### 5. PYNQ host boundary foundation

- Extracted board CRUD, persisted fields, default selection, secret-free serialization, and
  selection repair into `PynqBoardRepository`.
- Extracted pure preflight status evaluation.
- Extracted bounded SSH, SCP, and HTTP transport with capped diagnostic tails, explicit timeouts,
  structured logging, and credential redaction.
- Password authentication now uses the `SSHPASS` environment variable instead of placing the
  password in process arguments; sudo passwords use bounded standard input.
- Extracted deploy, verify, run, and runtime-status forwarding into a typed runtime proxy.
- Preserved current public methods and private patch points through the 1,133-line
  `pynq_service.py` compatibility façade.

Owning files:

- `nmtk/launcher_control/pynq_board_repository.py`
- `nmtk/launcher_control/pynq_remote_client.py`
- `nmtk/launcher_control/pynq_preflight.py`
- `nmtk/launcher_control/pynq_runtime_proxy.py`
- `tests/launcher_control/test_pynq_service_boundaries.py`

## Last verified results

The most recent completed checkpoint produced these results:

- Focused PYNQ tests: **85 passed**.
- Complete launcher-control suite: **337 passed**.
- Canonical launcher guardrails: **passed**.
- Launcher doctor: **0 fatal findings** and **1 expected degraded optional capability** for the
  optional Studio SDK.
- Flutter tests included by the canonical guardrail: **198 passed** and **1 expected skip**.
- Ruff check and Ruff formatting for launcher-control and its tests: **passed**.
- Strict mypy for the four new PYNQ boundary modules: **passed**.
- Python bytecode compilation and `git diff --check`: **passed**.

The full launcher suite initially encountered sandbox-denied loopback sockets; the required
outside-sandbox rerun passed all 337 tests. A broad existing-code strict-mypy run is not green yet:
focused strict typing is currently enforced for each new boundary, while legacy launcher typing
debt remains part of milestone 8.

## What remains

Approximately **51 percentage points** remain:

- Baseline and live verification closure — **1 point**.
- Reference assets and legacy `paper/` migration — **4 points**.
- Shared backend persistence, async execution, job, and error boundaries — **5 points**.
- Remaining launcher-control decomposition — **3 points**.
- NeuroCNL notebook generation split — **12 points**.
- NeuroCNL parser, compiler, planner, and materializer split — **11 points**.
- Remaining product Python boundaries — **10 points**.
- Strict typing, CI gates, and compatibility removal — **5 points**.

These are estimates, not earned-value accounting. NeuroCNL notebook generation and core compiler
work are the largest and riskiest remaining areas.

## Immediate next slice

The next safe slice is the **PYNQ provisioning coordinator split**. Move installation status,
health polling, user-space launch/restart, privileged systemd promotion, bundle construction,
overlay inspection, provisioning, repair, and runtime restart orchestration from
`pynq_service.py` into `nmtk/launcher_control/pynq_provisioning.py`.

Preserve these constraints while doing so:

- Keep all routes, payloads, progress stages, exceptions, settings fields, and serialized output
  unchanged.
- Keep temporary delegates for existing tests and internal consumers that patch `_run_ssh`,
  `_run_scp`, `_run_ssh_sudo`, `_run_ssh_detached`, health polling, install-status reading,
  preflight refresh, user-space restart, systemd promotion, and log-tail emission.
- Make the coordinator depend on a typed owner protocol, following the established Akida pattern.
- Do not move embedded installer programs or unit files in the same slice; template extraction is
  a later, separately testable launcher slice.
- End with Ruff, focused strict mypy, focused PYNQ tests, all launcher tests, launcher doctor, and
  `bash scripts/run_launcher_guardrails.sh` green.

After PYNQ provisioning is green, finish launcher template extraction and status serialization,
then proceed to NeuroCNL notebook generation rather than expanding launcher scope further.

## Compatibility and cleanup rules

- Treat `deployment_executors.py`, `akida_host_service.py`, and `pynq_service.py` as temporary
  compatibility façades, not places for new behavior.
- Keep compatibility exports and legacy path fallbacks for one release; remove them only after
  consumer migration and contract tests prove they are unused.
- Never delete a local legacy `paper/` tree automatically, because it may contain modified research
  material.
- Do not change HTTP contracts, launcher JSON, grammar, compiler imports, hardware handoff fields,
  or storage layouts as part of structural moves.
- Keep optional Akida, PYNQ, Lava, SpiNNaker, MuJoCo, BrainFlow, and report runtimes lazy and
  non-fatal at base startup.

## Developer deployment

`make dev-update` is the correct way to apply this checkpoint to the development host. It runs the
affected tests before syncing, sends only allowlisted backend runtime paths, and restarts
launcher-control because `nmtk/launcher_control/**` changed. No local restart is needed, and no
database migration is involved.

Do not present this terminal command as an end-user workflow. Released users receive backend
updates through the app's Backend Setup screen.

## Known tooling issue

The required Open Brain entry for the launcher repository/client/coordinator ownership invariant
could not be recorded because `gbrain` was blocked by a stale PGLite lock. Retry the knowledge
capture before or after the next slice; do not treat the missing entry as evidence that the
cross-file invariant is unimportant.

`semble` is also currently unusable because its installed launcher points to a missing virtual
environment interpreter. Use exact `rg` searches as a temporary fallback until `semble` is
reinstalled or repaired.
