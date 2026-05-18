# neurocnl Shell Adapter Execution Packet

Use this packet when a single-repo cloud agent is implementing the first
desktop-shell adapter pass for `neurocnl`.

This packet assumes the suite-level source of truth is:

- root `AGENTS.md`
- root `CODING_STYLE_GUIDE.md`
- [Shell Adapter Contract And Package Conventions](../2026-04-24-shell-adapter-contract-and-package-conventions.md)
- [ADR 0017: Desktop Shell Adapter Contract](../ADR-claude/0017-desktop-shell-adapter-contract.md)

## Goal

Create the initial `neurocnl_shell_adapter` package that exposes a shell-safe
desktop entrypoint for CNL Studio without changing cross-repo shell semantics.

## Package And Ownership

Expected adapter package name:

- `neurocnl_shell_adapter`

The agent may edit:

- the new adapter package
- module-owned desktop composition or feature-layer code needed to support the
  adapter
- repo-local tests and docs for the adapter

The agent must treat as read-only unless explicitly instructed otherwise:

- root shell contract docs
- `nmtk` launcher routing and module host code
- `nmtk_ui_core`
- cross-module backend contracts unless the assigned issue explicitly includes a
  contract change

## Required First-Pass Adapter Surface

The first pass should expose:

- stable module metadata for `neurocnl`
- one desktop entry surface for the authoring workspace
- deep-link decoding for the first target set
- restoration encode/decode for the first target set
- capability reporting mapped into shell-facing states

The adapter may initially wrap existing module-owned UI while the native desktop
surface evolves, but it must keep the shell-facing API stable.

## Required Deep-Link Targets

Implement these targets first:

- `project`
- `file`
- `validation`
- `export`
- `support`

Expected usage:

- `project`: open a saved authoring workspace or project context
- `file`: open a specific source document
- `validation`: focus diagnostics or validation results for the current source
- `export`: open export configuration or a recent export artifact view
- `support`: focus support-verdict or backend-support status UI

Unknown targets or stale payloads must land on a safe editor workspace rather
than failing the module open.

## Required Restoration Hooks

The first restoration payload should preserve only:

- active project or file
- active primary pane
- active diagnostics/support/export view when one is open
- enough editor context to return the user to a meaningful working surface

Do not persist:

- secrets or tokens
- transient backend process ids
- module-external absolute paths unless the repo already treats them as stable

Restoration failure must fall back to a clean editor open.

## Capability And Degradation Output

The adapter must emit shell-facing states using the root contract vocabulary.

Expected initial mapping for `neurocnl`:

- `ready`: editor and required authoring backend paths are usable
- `preflight_failed`: a required local dependency or startup prerequisite for
  the core authoring workflow is missing
- `degraded_optional_capability`: optional export or accelerator-specific paths
  are unavailable, but core authoring still works

Do not collapse optional export or hardware-target limitations into generic
startup failure if the core authoring workflow remains available.

## Validation

Before handing work back:

1. Run the owning repo tests for the adapter package and any touched feature
   layers.
2. Verify deep-link decoding for `project`, `file`, `validation`, `export`, and
   `support`.
3. Verify restoration replay for a normal happy path and a stale-payload
   fallback.
4. Verify optional capability limitations surface as
   `degraded_optional_capability`, not `preflight_failed`, when authoring still
   works.

If the issue changes a cross-repo contract after explicit approval, escalate
back to a full-workspace agent instead of changing the root shell contract in
the module repo.
