# CLI Contracts For Shell Actions

## Owner

- `C1` Full-workspace local agent or dedicated `neurocli` owner

## Depends on

- `issues/02-shell-adapter-contract-and-package-conventions.md`
- `issues/04-launcher-modules-surface-and-install-start-semantics.md`

## Can run in parallel with

- Phase B module lanes once launcher semantics are stable enough

## Write scope

- `neurocli/**`

## Tasks

- Define planning-ready CLI contracts for `install`, `launch`, `status`, `diagnostics`, and `scaffold`.
- Mirror launcher lifecycle semantics and module ids from `nmtk/neuro_toolkit/assets/modules.json`.
- Treat the CLI as a portability layer for future remote and mobile clients.

## Done when

- The CLI plan mirrors launcher semantics without inventing a second registry.
- Future implementation work can start from one stable command contract.

## Validation

- Doc review against `neurocli/AGENTS.md` and `nmtk/neuro_toolkit/assets/modules.json`
