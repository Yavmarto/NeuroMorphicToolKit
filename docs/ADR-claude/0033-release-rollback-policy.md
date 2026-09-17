# ADR 0033: Release Rollback Policy and the Schema-Migration Exception

## Status
Accepted. Approved by the CTO on 2026-09-17 (decision recorded in CEL-304).

## Context
The backend deploy path used the mutable `:latest` tag, and `install.sh` ran
`down` → `pull` → `up` → health-verify with no restore path. A bad `v*` release
therefore took every updating host down until another good release shipped.
ADR-0011 already flagged "no automated rollback" as a known negative
consequence. A release that changes the database schema or migrates saved data
must not be reverted under running data that already moved: doing so corrupts
state silently.

## Decision

**Deploy by a resolved, immutable version — not `:latest`.**
`install.sh` resolves the pulled `suite-api` image to its stamped release
version (the `org.opencontainers.image.version` label, falling back to the
`NMTK_VERSION` environment variable) and pins the whole stack to that tag.
Before any teardown it records the image reference, image ID, and repo digest
of every running service in `.nmtk-state/`. If the version cannot be resolved,
the requested tag is used and rollback relies on the recorded digests.

**Auto-rollback on a failed post-update health verification.**
When an update starts the new stack but health verification fails, the
installer restores the exact pre-update images by digest, tags them with a
local-only alias, starts the stack, and re-verifies. It reports both the release
that failed and the release it restored to in `deployment.status`. Rollback
only runs when a pre-update snapshot with images exists, so a first install is
never "rolled back" to nothing.

**Schema/data migration exception — alert and hold.**
Auto-rollback is withheld when the release carries a schema or data migration.
The install reports the failure and requires a human to restore or to ship a
fixed release. The condition is met by any of:

- the release is flagged with `--schema-migration true` (or
  `NMTK_SCHEMA_MIGRATION=true`); or
- the installer itself moves legacy data during this run; or
- `--rollback-policy hold` (or `NMTK_ROLLBACK_POLICY=hold`) forces hold for all
  releases.

**Release requirement.** A release that migrates schema or data MUST declare it,
so the app passes `--schema-migration true`. Until the app-side plumbing lands,
the installer's own legacy-data detection covers the in-repo migration and the
policy above is the contract.

## Consequences
- **Positive:** A bad release no longer strands updating hosts. The running
  version is recorded and reproducible, and a rollback to the previous release
  is automatic, exact, and reported.
- **Negative:** A release that migrates schema needs explicit flagging, or its
  failure will alert and hold instead of self-healing. The app must pass the
  flag for image-internal migrations that the installer cannot observe.
- **Follow-up:** thread `--schema-migration` and the resolved release version
  through the launcher's deploy request so the flag comes from release metadata,
  not only from on-host detection.
