# Shell Adapter Contract And Package Conventions

## Purpose

This document defines the suite-wide contract for package-based desktop module
integration.

It is the source of truth for:

- shell adapter responsibilities
- package naming and ownership conventions
- deep-link and restoration semantics
- capability and degradation reporting to the shell

Module repos should consume this contract. They should not invent local adapter
shapes or alternate status vocabularies.

## Scope

This contract applies to:

- `nmtk` as the desktop host
- `nmtk_ui_core` as the shared shell UI library
- `neurocli` where shell actions need CLI parity later
- every module repo that exposes a desktop-native surface through a package
  adapter

This document does not by itself change launcher behavior, manifest fields, or
module implementations. It defines the interface those later changes must
implement.

## Core Rules

1. Each module exposes exactly one shell adapter package.
2. The adapter package is the shell integration boundary for that module.
3. Domain logic, backend contracts, and product UI stay in module-owned
   packages; they do not migrate into `nmtk`.
4. The shell may persist and replay module restoration data, but the module owns
   its schema and version compatibility rules.
5. Optional runtime or hardware gaps must degrade cleanly through capability
   reporting. They must not collapse into generic startup failures.
6. During migration, a module may expose the same contract shape while still
   rendering a web-embedded fallback.

## Package Conventions

### Naming

- Adapter package format: `<module>_shell_adapter`
- Examples:
  - `neurocnl_shell_adapter`
  - `Neurosim_shell_adapter`
  - `Neurochip_shell_adapter`

Use the module's existing suite identifier casing unless that repo already has a
published package naming convention that requires normalization. If a repo needs
normalization later, record that in a repo-local ADR instead of silently
deviating here.

### Ownership

The adapter package owns only shell-facing integration concerns:

- module metadata exposed to the host
- native desktop entry surface registration
- deep-link decoding and routing into the module workspace
- restoration snapshot encode/decode
- capability report mapping into shell-facing states

The adapter package must not own:

- suite navigation policy
- shared design token definitions
- launcher install/start/stop state machines
- backend service contracts that are not shell-facing

### Versioning

- Adapter packages follow semantic versioning.
- Breaking contract changes require a major version bump.
- If the shell contract evolves, the adapter must declare the supported contract
  version in its registration metadata.
- Module-local internal refactors that do not change shell-facing behavior do
  not require a contract version bump.

## Canonical Interfaces

The root contract is language-agnostic. Names below are normative; exact syntax
may vary by implementation language.

### `ShellModuleAdapter`

Represents the module entry registered with the desktop shell.

Required responsibilities:

- expose stable module metadata:
  - module id
  - display name
  - package id
  - supported host modes
  - minimum supported shell contract version
- expose one desktop entry surface for the module workspace
- expose the adapter's deep-link decoder and restoration hooks
- expose capability reporting for shell status surfaces
- expose a fallback mode when native desktop rendering is unavailable

Required behavior:

- adapter registration must be deterministic and side-effect-light
- registration must not require optional hardware at import time
- metadata must remain usable even when the module is degraded or unavailable

### `ModuleDeepLink`

Represents a shell-to-module intent.

Required fields:

- `version`: deep-link schema version owned by the adapter
- `target`: stable module-defined target id
- `entityId`: optional primary entity identifier such as file, project, export,
  report, deployment, or session id
- `context`: optional structured payload for view selection, filters, or
  selection state

Rules:

- the shell treats the deep link as opaque beyond routing it to the correct
  module
- targets are module-owned and documented by the adapter package
- unknown targets or stale payloads must fail gracefully inside the module
- deep links are not a replacement for backend API contracts

### `ShellRestorationSnapshot`

Represents best-effort state restoration for reopening an existing workspace.

Required fields:

- `version`: adapter-owned restoration schema version
- `workspaceKey`: stable key for the module workspace instance
- `primaryRoute`: module-defined restoration target
- `payload`: adapter-owned serialized restoration data

Rules:

- restoration is best-effort, never fatal
- missing files, deleted projects, stale artifacts, or unavailable hardware must
  produce a recoverable module state, not a shell crash
- the shell may persist and replay the blob, but it must not inspect or mutate
  adapter-owned payload internals
- adapters must tolerate unknown or older payload versions when feasible and
  fall back to a safe landing view otherwise

### `CapabilityReport`

Represents shell-facing readiness and degradation information for the active
module surface.

Required fields:

- `state`
- `message`
- `warnings`
- `availableTargets`: optional list of ready capabilities or runtimes
- `unavailableTargets`: optional list of degraded or blocked capabilities
- `recommendedAction`: optional shell-safe next step for repair or fallback

### `CapabilityState`

Use these shell-facing values:

- `ready`
- `preflight_failed`
- `degraded_optional_capability`
- `unavailable`

Semantics:

- `ready`: the primary module workflow is available
- `preflight_failed`: a required dependency, manifest input, or startup contract
  is invalid; this is a blocker
- `degraded_optional_capability`: the module can run, but an optional runtime,
  hardware path, or advanced feature is unavailable
- `unavailable`: the module surface cannot currently be entered for reasons that
  are not a recoverable optional-capability degradation

Operator-facing surfaces should continue to render the phrases `preflight
failed` and `degraded optional capability` exactly, to match existing launcher
terminology and diagnostics.

## Deep-Link Contract

Every adapter must define its supported target ids in repo-local docs. The root
contract requires the following categories to exist where they make product
sense:

- project or workspace target
- artifact or result target
- diagnostics or status target
- review or replay target for session-oriented modules

Modules do not need to implement every category. They do need to document the
targets they support and keep them stable once published.

The shell may pass a deep link:

- on first open
- when switching to an already-open module workspace
- when restoring a prior session
- from another module handoff action

The adapter is responsible for normalizing these entry paths into one module
navigation flow.

## Restoration Contract

Each adapter owns its restoration payload and versioning. The shell owns only
these host-level guarantees:

- persistence of the opaque snapshot
- replay of the snapshot when reopening a workspace
- fallback to a clean module open if restoration fails

Adapters should include only state needed to restore the user to a meaningful
working surface:

- active document, project, run, report, or deployment
- active pane or tab selection
- view mode, filters, and focused entity where useful

Adapters should avoid persisting:

- secrets
- transient credentials
- host-specific absolute paths unless the module already treats them as stable
- data that can only be restored by assuming optional hardware is present

## Capability And Degradation Contract

Capability reporting must align with current launcher behavior in `nmtk`.

Required rules:

- distinguish required failures from optional degradation
- preserve actionable warning text where available
- do not report missing optional runtimes as fatal unless the module manifest or
  module contract marks them required
- surface a shell-safe fallback action when one exists, such as simulator mode,
  remote host mode, or review-only mode

Examples:

- Missing Lava on a host that can still use other Neurochip workflows:
  `degraded_optional_capability`
- Invalid required Python environment for a module's only startup mode:
  `preflight_failed`
- Missing Akida board while simulator-only execution remains possible:
  `degraded_optional_capability`

## Cloud-Agent Execution Conventions

Single-repo cloud agents should receive a repo-local brief that references this
document instead of re-specifying shell semantics.

Every repo-local brief should include:

1. expected adapter package name
2. target desktop entry surface
3. required initial deep-link targets
4. required initial restoration hooks
5. capability and degradation outputs expected by the shell
6. write boundaries inside the module repo
7. validation commands

Root-level shell contract changes remain owned by full-workspace agents.

## Implementation Notes For Later Issues

When executable adoption starts:

- `nmtk` should consume adapter metadata and capability output without inventing
  a second parallel status model
- `nmtk_ui_core` should provide shell primitives that render adapter states, but
  it should not absorb module-specific business logic
- `neurocli` should mirror shell actions against the same deep-link and
  capability concepts where practical

See also:

- [ADR 0017: Desktop Shell Adapter Contract](./ADR-claude/0017-desktop-shell-adapter-contract.md)
- [neurocnl Shell Adapter Execution Packet](./agents/neurocnl-shell-adapter-execution-packet.md)

