# docs

`docs/` is the shared architecture, operations, and governance layer for the whole workspace.

## What Is Authoritative Now

For current suite behavior, start with:

- [`ADR-claude/`](./ADR-claude/)
- [`api/README.md`](./api/README.md)
- [`agents/`](./agents/)
- dated consolidation and roadmap docs in the root of `docs/`

The current architecture to keep in mind while reading the repo is:

- one backend: `suite_api`
- one control plane: `nmtk`
- native Flutter feature packages instead of WebView-hosted module apps
- `NeuroHub` as registry and metadata, not launcher/runtime orchestration

## What Lives Here

- user and operator guides
- suite-level API and backend-smoke guidance
- ADRs and dated decision/roadmap documents
- CI, release, and operational playbooks
- agent and automation workflows
- historical audits and archived reports

## How To Read This Folder

Not all documentation here has the same status.

- `docs/ADR-claude/` contains the accepted cross-repo architecture trail.
- `docs/archive/` is historical record and should not be rewritten to match current state.
- dated roadmap and audit docs are useful evidence, but their title and status line matter.
- older pipeline directories may still be informative, but they are not automatically the current source of truth.

If you only need the current suite model, read these first:

1. [`../README.md`](../README.md)
2. [`ADR-claude/0018-suite-api-unified-backend.md`](./ADR-claude/0018-suite-api-unified-backend.md)
3. [`ADR-claude/0019-flutter-feature-packages.md`](./ADR-claude/0019-flutter-feature-packages.md)
4. [`ADR-claude/0021-studio-neurochip-handoff-contract.md`](./ADR-claude/0021-studio-neurochip-handoff-contract.md)
5. [`ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md`](./ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md)
6. [`api/README.md`](./api/README.md)
