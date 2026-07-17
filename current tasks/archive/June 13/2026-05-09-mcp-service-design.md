# MCP Service Design for NeuroMorphicToolKit

## Verified Implementation Status (2026-07-04)

**Status: PARTIAL — substantially further along than "Phase 1 only" (per `TASKS.md`'s June 13 summary); Phase 2 is essentially done, Phase 4 confirmed not started.**

`tools/nmtk_mcp_server/` contains 18 Python modules plus a `tests/` directory (1956 total lines), last touched by commit "Several fixes and cleanup" (2026-05-12).

Done (registered and implemented):
- `tools/nmtk_mcp_server/server_blueprint.py:77-136` registers tools `validate_cnl`, `suite_health`, `launcher_doctor`, `list_modules`, `get_cnl_authoring_guide`, `submit_simulation`, `poll_simulation_job`, `check_deployability`, `prepare_neurochip_handoff`, `save_deerflow_packet`, `load_local_state`.
- `tools/nmtk_mcp_server/tool_handlers.py:52-247` implements matching handler methods for all of the above, including `get_cnl_authoring_guide` (line 107) — this closes the "pending" item the doc's own 2026-05-10 status note flagged.
- `tools/nmtk_mcp_server/simulation_client.py` implements `SimulationClient.submit_simulation`/`poll_job` — the Phase 2 "simulation wrappers" the doc's status note marked "pending" are now done.
- `tools/nmtk_mcp_server/deployability_client.py` (200 lines) implements the deployability check wrapper — Phase 2 deployability item done.
- `tools/nmtk_mcp_server/state_store.py` persists `DeerFlowPacket` records for `save_deerflow_packet` — Phase 3 packet-persistence primitive exists.

Still missing (confirmed by grep, zero hits across `tools/nmtk_mcp_server/*.py`):
- `deploy_to_target`, `get_deployment_status`, `run_on_simulator` — Phase 4 privileged deployment execution tools are NOT implemented.
- No evidence of an automated DeerFlow dispatch/send-receive loop beyond packet storage (Phase 3 is packet-persistence only, not an active delegation pipeline).

Net effect: this doc and `TASKS.md`'s "Phase 1 exists, Phase 2 partial, Phase 3/4 not started" summary undersell current progress — treat Phase 2 as done and only Phase 4 (plus the DeerFlow dispatch loop) as outstanding.

Date: 2026-05-09

Status: Proposed

## Why This Exists

We need a project MCP service that gives an agent one coherent control surface for the core operator workflow:

1. learn how to write valid NeuroCNL
2. draft or repair a `.cnl` spec
3. validate the spec against current backend support
4. start a simulation
5. prepare deployment
6. deploy and run on simulation or supported devices

This service should not invent a second control plane. The current suite model is already clear:

- `suite_api` is the canonical backend surface
- `nmtk` is the sole control plane for lifecycle and runtime state
- `neurocnl` owns canonical authoring, validation, and deployment-target selection
- `Neurochip` owns target-specific execution, flashing, and hardware diagnostics
- optional workers remain isolated for MuJoCo and hardware runtimes

The MCP server should expose those capabilities to agents in a way that is typed, auditable, and low-token.

Important clarification:

In this design, DeerFlow should be treated primarily as a build-time delegation mechanism for implementing the MCP server, not as a required runtime dependency of the shipped MCP service.

## Goals

- Provide one MCP server for authoring, simulation, and deployment workflows.
- Reuse existing `suite_api`, `neurocnl`, `Neurochip`, and `nmtk` contracts instead of duplicating logic.
- Keep all privileged actions local, deterministic, and observable.
- Keep the shipped MCP runtime independent from DeerFlow unless a later phase proves that a runtime dependency is necessary.
- Preserve current ownership boundaries across modules.

## Non-Goals

- Do not create a second manifest, module registry, or launcher lifecycle model.
- Do not bypass `suite_api` and call random module internals directly when a stable route already exists.
- Do not make the shipped MCP server depend on DeerFlow for core runtime behavior.
- Do not claim stronger backend or hardware support than `neurocnl/docs/support_matrix.md` already allows.

## Current Building Blocks

The repo already contains most of the primitives this MCP service needs:

- CNL grammar and examples:
  `neurocnl/neurocnl/cnl/cnl_grammar.md`
- CNL validation and backend support:
  `POST /api/neurocnl/validate`
- CNL generation, export, and deployability checks:
  `POST /api/neurocnl/generate`
  `POST /api/neurocnl/export`
  `POST /api/neurocnl/deploy/teensy/network`
  `POST /api/neurocnl/deploy/pynq/network`
- NeuroSim preview and simulation-oriented refinement:
  `POST /api/neurosim/preview`
- Unified backend routing:
  `suite_api` on port `9000`
- Optional hardware and physics workers:
  `workers/neurochip_hw/main.py`
  `workers/neurocnl_physics/main.py`
- Launcher and lifecycle semantics:
  `nmtk/neuro_toolkit/assets/modules.json`
- Existing DeerFlow file handoff pattern:
  `scripts/deerflow_send_task.sh`
  `scripts/deerflow_receive_task.sh`

## Proposed Architecture

### 1. Service Placement

Implement the MCP server as a root-owned service package, for example:

`tools/nmtk_mcp_server/`

It should be a thin orchestration layer over:

- `suite_api` for online domain actions
- `nmtk` manifest and launcher-control helpers for lifecycle actions
- local file storage for session artifacts and audit logs
- optional DeerFlow-assisted implementation work during development

This keeps the MCP server outside any one module while still respecting module ownership.

### 2. Trust Boundaries

Split the service into three execution classes.

#### A. Authoritative local tools

These call local code, `suite_api`, or launcher-control surfaces and return results that the suite can stand behind:

- validation
- support verdicts
- simulation start/status
- deployability checks
- device deployment handoff
- runtime health
- module start/stop/status

#### B. Read-only resources

These are static or slowly changing context surfaces that agents can read cheaply:

- CNL grammar
- support matrix
- launcher module manifest
- target mapping and handoff contract

### 3. Transport Model

The shipped MCP server should expose:

- `resources` for grammar, support, and manifest context
- `tools` for actions
- `prompts` for common workflows such as “write a valid reflex-arc CNL” or “prepare PYNQ deployment”

The server should not expose raw shell execution to the model. Every action should be a named tool with typed inputs and outputs.

## MCP Surface

### Resources

Suggested resources:

- `nmtk://cnl/grammar/current`
  Backed by `neurocnl/neurocnl/cnl/cnl_grammar.md`
- `nmtk://cnl/support-matrix/current`
  Backed by `neurocnl/docs/support_matrix.md`
- `nmtk://suite/modules/current`
  Backed by `nmtk/neuro_toolkit/assets/modules.json`
- `nmtk://studio/neurochip-target-map/current`
  Backed by ADR 0020 / ADR 0021 semantics
- `nmtk://api/openapi/current`
  Backed by `http://127.0.0.1:9000/openapi.json`

### Prompts

Suggested prompts:

- `write-cnl-from-intent`
- `repair-invalid-cnl`
- `explain-target-support`
- `prepare-simulation-run`
- `prepare-device-deployment`

Prompts should be small wrappers that preload grammar and support resources instead of inlining long docs into every request.

### Tools

#### Authoring and validation

- `get_cnl_authoring_guide(intent?, target_backend?)`
  Returns the minimal grammar subset, examples, and warnings relevant to the requested task.
- `validate_cnl(spec, backend="nengo")`
  Wraps `POST /api/neurocnl/validate`.
- `export_cnl(spec, format, filename?)`
  Wraps `POST /api/neurocnl/export`.

#### Simulation

- `run_neurocnl_simulation(spec, backend="nengo", mode="validate_only|full")`
  Uses the existing `neurocnl` pipeline path for canonical CNL-driven execution.
- `run_neurosim_preview(graph_or_spec, duration_ms=1000)`
  Wraps `POST /api/neurosim/preview`.
- `run_prosthetic_simulation(spec, require_mujoco=false)`
  Calls `/api/neurocnl/prosthetic/simulate` through `suite_api`; returns a clear `worker_unavailable` state if the physics worker is absent.
- `get_simulation_job(job_id)`
  Polls async job status where applicable.
- `cancel_simulation_job(job_id)`

#### Deployment and runtime execution

- `check_deployability(spec, target, options={})`
  Dispatches to the correct local check:
  - `teensy` -> `/api/neurocnl/deploy/teensy/network`
  - `pynq` -> `/api/neurocnl/deploy/pynq/network`
  - `akida` -> local/exportability route once normalized through `suite_api`
- `prepare_neurochip_handoff(spec, target, readiness_summary?)`
  Produces the typed handoff payload without executing device-side work.
- `deploy_to_target(spec_or_handoff, target, execution_mode, device_endpoint?)`
  Uses authoritative local checks first, then calls the correct `Neurochip` or worker-backed route.
- `get_deployment_status(deployment_id)`
- `run_on_simulator(target, artifact_or_spec, options={})`
  For targets that support simulator fallback, for example PYNQ simulator or Speck software fallback.

#### Control-plane tools

- `suite_health()`
  Reads `suite_api` health and worker availability.
- `module_status(module_id?)`
  Reads from the same manifest semantics as `nmtk`.
- `start_module(module_id)`
- `stop_module(module_id)`
- `doctor()`
  Wraps launcher doctor and returns structured `preflight_failed` vs `degraded_optional_capability`.

## Tool Semantics

### 1. `get_cnl_authoring_guide`

This should be the default “how do I write a CNL?” entrypoint.

It should:

- read the grammar resource
- select only the concept families relevant to the user’s intent
- include valid examples
- include target-specific support warnings from the support matrix
- avoid generating a full tutorial unless explicitly requested

This tool should not call DeerFlow. The source material is already local and authoritative.

### 2. `run_neurocnl_simulation`

This should support two modes:

- `validate_only`
- `full`

`validate_only` is cheap and should be the default in agentic flows.
`full` should run only after validation passes or the caller explicitly asks for best-effort execution.

### 3. `check_deployability`

This is where the MCP service protects the rest of the workflow from false claims.

It should:

- normalize target names to the Studio-owned mapping
- call the existing deployability route
- return the exact local verdict
- separate:
  - `exportable`
  - `deployable`
  - `not_deployable`
  - `requires_optional_runtime`
  - `worker_unavailable`

It should not collapse exportability into proven on-device readiness.

### 4. `deploy_to_target`

This must be a privileged local action.

The tool should require:

- a validated handoff or spec
- an explicit target
- an explicit execution mode
- a clear runtime endpoint when the action leaves the local machine

Recommended modes:

- `scaffold_only`
- `simulator`
- `local_worker`
- `remote_runtime`

The response should always include:

- what was attempted
- which authoritative check passed first
- which local or remote endpoint was used
- whether the result is package generation, runtime mapping, or actual execution

## DeerFlow Build Strategy

DeerFlow fits best as a development accelerator for building the MCP server itself.

Implementation update as of 2026-05-10:

- `tools/nmtk_mcp_server/resources.py` is already in place for canonical file-backed resources.
- `tools/nmtk_mcp_server/neurocnl_client.py` and `tools/nmtk_mcp_server/control_plane.py` cover the initial validation and doctor wrappers.
- DeerFlow-derived wrappers have now been integrated for:
  - `tools/nmtk_mcp_server/deployability_client.py`
  - `tools/nmtk_mcp_server/module_registry.py`
  - `tools/nmtk_mcp_server/prompts.py`
  - `tools/nmtk_mcp_server/result_models.py`
- The integration requirement is unchanged: these helpers must preserve authoritative repo semantics rather than simplify them into generic booleans.

### What DeerFlow Should Build

Good DeerFlow handoff candidates:

- MCP tool schema scaffolding
- request and response model definitions
- client wrappers around `suite_api` routes
- resource loader code for grammar, support matrix, and manifest surfaces
- test fixture generation
- repetitive boilerplate for job/state persistence
- draft documentation and usage examples

### What DeerFlow Should Not Own

Keep these pieces under local review and final integration:

- final tool semantics
- security boundaries
- endpoint allowlists
- deployment execution paths
- launcher doctor integration
- any code that changes module ownership or suite-visible runtime semantics

### Recommended Delegation Model

Use DeerFlow as a packet-based worker for bounded subtasks, not as the system architect.

Recommended loop:

1. define the next bounded deliverable locally
2. prepare a DeerFlow task packet with only the needed context
3. send the packet with the existing handoff scripts
4. receive the patch or artifact
5. review and integrate locally
6. run the authoritative local checks

The packet should include:

- target file paths
- exact write scope
- required route or contract references
- expected tests
- explicit non-goals

Example DeerFlow implementation packet:

```json
{
  "task_type": "implement_mcp_tool_wrapper",
  "write_scope": [
    "tools/nmtk_mcp_server/client/neurocnl.py",
    "tools/nmtk_mcp_server/models/validation.py",
    "tools/nmtk_mcp_server/tests/test_validate_cnl.py"
  ],
  "inputs": {
    "route": "POST /api/neurocnl/validate",
    "source_files": [
      "neurocnl/backend/app/routers/validate.py",
      "suite_api/domains/neurocnl/router.py"
    ],
    "requirements": [
      "typed request and response models",
      "no shell execution",
      "propagate backend_support fields"
    ]
  },
  "expected_output": {
    "files_changed": [],
    "tests_added": [],
    "open_questions": []
  }
}
```

### Why This Is Better

This preserves a clean product boundary:

- the shipped MCP server remains self-contained
- DeerFlow reduces implementation-token cost
- local validation still decides what merges
- runtime reliability does not depend on an external delegation loop

## Model Allocation Recommendation

The planning and packet-preparation stages should use a strong model. That is the point where mistakes are most expensive because the packet defines the implementation envelope, invariants, and verification bar.

Recommended split:

1. Strong model for planning and repo-grounding
   - choose the exact write scope
   - identify the real source-of-truth routes, contracts, and docs
   - define fail-closed semantics
   - decide what must be tested
2. Strong model for DeerFlow packet creation
   - write the sanitized task packet
   - include exact interfaces, examples, edge cases, and non-goals
   - remove ambiguity before the external worker sees the task
3. External DeerFlow model for bounded draft implementation
   - good for boilerplate, typed wrappers, repetitive tests, and narrow adapters
   - not trusted to invent product semantics from partial context
4. Local integration model for merge, correction, and verification
   - can be weaker only when the task is already narrowed to mechanical implementation
   - should be strong when the patch crosses semantic boundaries or requires correcting abstractions

Practical answer for this repo:

- Strong-model planning plus strong-model DeerFlow packaging is viable.
- A strong external DeerFlow model without full repo context is viable only for bounded packets whose semantics are fully specified in the packet.
- A weaker implementation model such as Gemini Flash or Haiku is viable for:
  - mechanical code generation
  - schema mirrors
  - fixture expansion
  - simple tests
  - straightforward glue code where the packet already defines exact behavior
- A weaker implementation model is not the right default for:
  - cross-file semantic alignment
  - route-specific verdict normalization
  - subtle ownership-boundary work
  - launcher/control-plane behavior
  - anything that must preserve truthfulness wording such as `preflight_failed` versus `degraded_optional_capability`

For this MCP-server effort specifically, a weak model is sufficient for some bounded subtasks, but not for end-to-end implementation without strong review. The deployability and control-plane surfaces carry enough semantic nuance that at least one strong model should own implementation or final integration for those slices.

## State and Persistence

The MCP server should maintain a small local state store for:

- sessions
- generated CNL drafts
- validation results
- simulation jobs
- deployment attempts
- DeerFlow packets and responses

Suggested location:

`.nmtk/mcp/`

Suggested records:

- `sessions/<session_id>.json`
- `jobs/<job_id>.json`
- `artifacts/<job_id>/...`
- `deerflow/<task_id>/packet.json`
- `deerflow/<task_id>/result.json`

This should be append-oriented and easy to inspect manually.

## Error Model

Every tool should return machine-readable status instead of only prose.

Suggested top-level result envelope:

```json
{
  "status": "ok|invalid_input|unsupported|blocked|failed",
  "summary": "short human-readable result",
  "details": {},
  "artifacts": [],
  "next_actions": []
}
```

Recommended blocker classes:

- `invalid_cnl`
- `unsupported_backend`
- `optional_runtime_missing`
- `worker_unavailable`
- `device_unreachable`
- `not_deployable`
- `preflight_failed`
- `degraded_optional_capability`

This matches existing suite language and avoids generic “something went wrong” responses.

## Security and Safety

- Only allow deployment and lifecycle tools against approved local endpoints or manifest-derived targets.
- Never let the model choose arbitrary shell commands.
- Require explicit opt-in fields for remote URLs or hardware endpoints.
- Mask secret fields in logs and artifacts.
- Keep DeerFlow task packets free of secrets by default.
- Treat hardware actions as idempotent only when the underlying module already guarantees it.

## Recommended Implementation Plan

### Phase 1: Read-only and safe local actions

- implement resources
- implement `get_cnl_authoring_guide`
- implement `validate_cnl`
- implement `suite_health`
- implement `module_status`
- implement `doctor`

Status on 2026-05-10:

- done: resources
- done: `validate_cnl`
- done: `suite_health`
- done: `module_status` client wrapper via `module_registry.py`
- done: `doctor`
- partial: prompt metadata scaffolding via `prompts.py`
- pending: the actual MCP prompt-serving surface and `get_cnl_authoring_guide`

This phase provides immediate agent value with low risk.

### Phase 2: Simulation and deployability

- implement `run_neurocnl_simulation`
- implement `run_neurosim_preview`
- implement `check_deployability`
- implement `prepare_neurochip_handoff`

Status on 2026-05-10:

- done: `check_deployability` client wrapper via `deployability_client.py`
- done: `prepare_neurochip_handoff` typed payload scaffolding
- pending: simulation wrappers
- pending: MCP tool registration and result-envelope wiring

This phase covers the core operator workflow without executing hardware actions.

### Phase 3: DeerFlow-assisted implementation workflow

- define DeerFlow implementation packet schema
- identify boilerplate-heavy MCP subtasks
- use DeerFlow to generate bounded code patches
- review and integrate locally

This is where token savings matter most.

### Phase 4: Privileged deployment execution

- implement `deploy_to_target`
- implement `get_deployment_status`
- implement `run_on_simulator`
- add target-specific auth and endpoint controls

This phase should happen only after the read-only and planning flows are stable.

## Design Decisions Worth Keeping

- Build the MCP server over `suite_api`, not over direct ad-hoc imports.
- Treat `nmtk` manifest semantics as the only runtime registry.
- Keep `Studio` as the canonical deployment-target chooser.
- Use DeerFlow to speed implementation, not to define runtime authority.
- Return structured results with explicit blocker classes.

## Open Questions

1. Should the first shipped version live as a standalone Python package under `tools/`, or as a root script plus package that later moves into `neurocli` once `neurocli` becomes real?
2. Which target should be the first privileged execution path: `teensy`, `pynq`, or `akida`?
3. Do we want MCP prompts checked into the repo as versioned assets, or generated directly from resources at runtime?
4. Which MCP subtasks are repetitive enough to be worth standard DeerFlow packets from day one?

## Recommendation

Build the MCP service now as a root-owned orchestration package over `suite_api` and `nmtk`, and use DeerFlow as an implementation accelerator rather than a runtime dependency.

Keep the first release intentionally narrow:

- authoritative local read-only resources
- validation
- simulation start
- deployability checks

Do not make device deployment the first thing the MCP server does. Start with planning and verification, use DeerFlow to offload bounded implementation slices, and add privileged execution after the tool contracts and error model are stable.
