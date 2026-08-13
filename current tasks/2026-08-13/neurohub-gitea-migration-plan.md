# Neurohub Gitea migration implementation plan

**Date:** 2026-08-13  
**Status:** Proposed  
**Goal:** Replace Neurohub's Supabase/PostgreSQL/object-storage persistence with a user-hosted Gitea instance while keeping the product, app surface, `neurohub://` links, and public API branded as **Neurohub**.

**Operator companion:** Follow [Neurohub with Gitea: operator setup and cutover guide](./neurohub-gitea-operator-runbook.md) for the executable DNS, TLS, SMTP, OAuth, deployment, validation, backup, migration, cutover, and rollback sequence.

## Executive decision

Use Gitea as Neurohub's identity, authorization, repository, version-history, collaboration, search-index source, and binary-release store. Keep a small stateless Neurohub FastAPI service in front of Gitea so NMTK clients continue to use Neurohub contracts instead of depending on Gitea's API shape.

The recommended storage unit is **one Gitea repository per workspace or published artefact**:

- An editable workspace is a private repository by default. Each explicit save creates one commit, sharing adds Gitea collaborators or organization teams, and publishing changes repository visibility only after confirmation.
- An immutable artefact is a public or private repository whose semantic versions are Gitea tags/releases. Small text metadata stays in Git; large models, recordings, datasets, and bundles are release attachments.
- Gitea issues/comments, stars, collaborators, followers, commits, and releases replace Neurohub's relational community tables where the semantics match.
- Neurohub remains the user-facing name. “Gitea” appears only in operator setup and an optional “Open repository” link.

This deliberately does **not** make every desktop client call Gitea directly. The Neurohub service owns schema validation, friendly errors, compatibility, and the mapping between domain concepts and Gitea resources.

## Assumptions to confirm before implementation

The plan uses these defaults because they minimize end-user setup:

1. There is one centrally hosted Neurohub Gitea instance, separate from every user's private NMTK backend.
2. Users sign into Neurohub with Gitea OAuth2 Authorization Code + PKCE; they do not paste personal access tokens.
3. Private workspace backup/sync and explicit sharing are in scope, not only public publishing.
4. A workspace save is user-triggered or debounced as one logical revision, not a commit for every keystroke.
5. The first supported Gitea baseline is 1.26.x or newer; the adapter checks `/api/v1/version` and rejects unsupported instances with an actionable operator error.
6. Gitea's own PostgreSQL/SQLite database is an implementation detail owned and backed up by the Gitea operator. Neurohub itself has no application database after the migration.

If assumption 1 changes and every organization can point the app at its own Gitea, the same adapter works, but instance discovery, trust, certificate handling, and per-instance OAuth registration become a separate product feature.

## Current-state findings that affect the plan

- Neurohub currently has two overlapping persistence surfaces: legacy `/api/neurohub` projects/assets/shares and newer `/api/v1` registry artefacts/search/community/auth.
- The public-registry path stores identity and metadata in SQLAlchemy tables, payloads in S3-compatible storage, and optionally indexes search in MeiliSearch.
- The existing Supabase design uses Supabase for Auth, PostgreSQL, and object storage, but the currently checked-out standalone Flutter frontend has been deleted.
- `suite_api/main.py` currently comments out the Neurohub router and lifespan, so a user's private backend does not actually expose the embedded Neurohub routes.
- `neurocnl/frontend/lib/services/hub_asset_client.dart` still points to `/api/neurohub` on the user's private Suite API, which conflicts with the earlier decision that the shared Hub is one central service.
- `Neurohub/Neurohub_shell_adapter` imports the deleted standalone `neurohub` Flutter package, so the current native Neurohub navigation surface needs repair before a migration can be tested end to end.
- Existing `neurohub://{type}/{owner}/{slug}[@version]` identifiers and Pydantic contracts are valuable compatibility boundaries and should survive.

These are Phase 0 blockers, not reasons to put Gitea into the private Suite API.

## Target architecture

```text
 NMTK desktop / CNL Studio / neurocli
                  |
                  | Neurohub API + Gitea OAuth token
                  v
        +-------------------------+
        | Neurohub API (stateless)|
        | validation + mapping    |
        | compatibility + errors |
        +------------+------------+
                     |
                     | Gitea REST API
                     v
        +-------------------------+
        | Central Neurohub Gitea  |
        |                         |
        | users / orgs / teams    |
        | repositories / commits  |
        | tags / releases         |
        | issues / stars / events |
        +------------+------------+
                     |
          +----------+----------+
          |                     |
          v                     v
   Gitea database       Gitea object storage
   (operator-owned)     (release attachments,
                         LFS if later needed)
```

The desktop app talks to one configured `NEUROHUB_API_URL`. The Neurohub API knows `GITEA_BASE_URL`; end users never enter ports, service names, storage keys, or admin tokens.

## Domain mapping

### Repository identity

| Neurohub concept | Gitea representation |
|---|---|
| User | Gitea user |
| Team/organization | Gitea organization + teams |
| Workspace/project | One repository, private by default |
| Workspace revision | Commit on `main` |
| Workspace member | Collaborator or organization-team permission |
| Published artefact | Repository with `neurohub` and type topics |
| Artefact version | Annotated tag + release named `vMAJOR.MINOR.PATCH` |
| Small payload | Tracked repository file |
| Large immutable payload | Release attachment |
| Description/readme | Repository description + `README.md` |
| Structured metadata | `.neurohub/manifest.json` |
| Soft delete | Archive repository first; permanent deletion is a separate confirmed action |
| Rating | Replace 1-5 ratings with Gitea stars |
| Comments/discussion | Gitea issue titled `Neurohub discussion` or native issue list |
| Follow publisher | Gitea user follow where available; otherwise omit from v2 rather than emulate a database |
| Activity feed | Gitea user/org events and repository updates |
| Download count | Drop from authoritative metadata unless Gitea exposes a reliable native count |

Do not fake old metrics. The v2 contract should expose `star_count`, `updated_at`, and release data directly. During the v1 compatibility window, deprecated rating/download fields may return `null`/zero with a deprecation header, but must not present fabricated values.

### Canonical repository layout

```text
workspace-or-artefact/
├── .neurohub/
│   └── manifest.json
├── README.md
├── workspace.nmtk.json        # editable workspace, when applicable
├── artefact/                   # small text/config artefacts
└── .gitattributes             # only if Git LFS is enabled later
```

`manifest.json` is schema-versioned and contract-owned:

```json
{
  "schema_version": 1,
  "kind": "workspace",
  "artefact_type": "studio_workspace",
  "slug": "mnist-akida",
  "display_name": "MNIST Akida",
  "description": "Train, verify, and deploy the MNIST example",
  "tags": ["mnist", "akida"],
  "payload": {
    "path": "workspace.nmtk.json",
    "sha256": "...",
    "media_type": "application/vnd.nmtk.workspace+json"
  },
  "nmtk": {
    "minimum_version": "...",
    "source_module": "neurocnl"
  }
}
```

For a release attachment, `payload` records the release tag and attachment name instead of a Git path. Existing metadata/model-card fields remain typed extensions under the manifest rather than being flattened into repository topics.

### Save and conflict semantics

```text
Open workspace
  -> GET manifest + payload at commit A
  -> edit locally
  -> Save to Neurohub(base_commit=A)
       -> current head still A: one atomic multi-file commit -> success B
       -> current head is B/C: return 409 with remote/local/base details
            -> user chooses reload, save a copy, or resolve
```

Use Gitea's multi-file repository-content endpoint so manifest, README, and workspace changes land in one commit. The server must require the client's base commit/SHA for updates; last-write-wins is unacceptable for shared workspaces.

## Authentication and authorization

1. Register Neurohub as a **public OAuth2 client** in Gitea.
2. Desktop and web clients use Authorization Code + PKCE, `state`, and an exact registered redirect URI.
3. Request only the granular OIDC/user/repository scopes needed by the released feature set. Gitea added granular OAuth scopes in v1.23, so the implementation must test against the chosen minimum version.
4. Store access and refresh tokens in the platform secure store. Never persist user tokens in Neurohub logs, its filesystem, or a database.
5. The client sends the access token to Neurohub; Neurohub validates identity through Gitea and uses that same user-scoped token for repository operations.
6. Normal operation must not use a global admin token. A short-lived admin token is allowed only for the one-time migration tool and is revoked afterward.
7. Repository visibility and collaborator/team permissions are the source of truth. Neurohub must never maintain a parallel ACL document.
8. Map Gitea `403`, `404`, `409`, `422`, rate-limit, timeout, and outage responses to stable Neurohub errors with recovery instructions.

Existing Supabase password hashes cannot be exported into Gitea. Migration pre-creates usernames/emails where permitted, then sends Gitea password-reset/invitation mail; users authenticate through Gitea after cutover.

## API strategy

Keep the client-facing API stable where semantics still match:

- `GET /api/v1/artefacts/{owner}/{slug}[/version]`
- `GET /api/v1/search`
- `POST /api/v1/artefacts`
- `PUT /api/v1/artefacts/{owner}/{slug}/{version}` for mutable descriptive metadata only
- `DELETE /api/v1/artefacts/...` mapped to archive, not permanent deletion
- `GET/POST /api/neurohub/workspaces` as the focused workspace sync/share surface
- `GET/PUT /api/neurohub/workspaces/{owner}/{slug}` with base-commit conflict control
- `PUT/DELETE /api/neurohub/workspaces/{owner}/{slug}/collaborators/{username}`
- `POST /api/neurohub/workspaces/{owner}/{slug}/publish`

Add `/api/v2` only for fields whose meaning changes, especially stars versus ratings, native repository URLs, commit history, visibility, and collaboration. Return `Deprecation`/`Sunset` headers on legacy endpoints once every shipped client uses v2.

The public `neurohub://` URI remains stable and resolves through Neurohub, never directly through a Gitea hostname. This lets the operator move or restore Gitea without invalidating saved workspace references.

## Implementation phases

### Phase 0: Correct the product boundary and establish a baseline

**Purpose:** Make the current shared-Hub path truthful before changing storage.

- Add an accepted Neurohub ADR that supersedes the PostgreSQL/Supabase identity and persistence decisions; do not rewrite historical ADRs.
- Document the central-service boundary: Neurohub/Gitea is not installed into every user's private backend.
- Repair or replace the deleted Neurohub frontend dependency with a focused native Neurohub feature surface in the NMTK app.
- Introduce one shared Dart `NeurohubClient` owned by Neurohub and use it from the native Hub UI and CNL Studio; remove direct construction of `/api/neurohub` URLs from `HubAssetClient`.
- Add one operator-configured `NEUROHUB_API_URL` with a release default. Do not expose a port field to end users.
- Keep the Suite API Neurohub router disabled unless it is explicitly used as a reverse proxy to the central service; do not start a second local registry database.
- Capture a full contract snapshot of current `/api/neurohub` and `/api/v1` behavior and inventory the actual Supabase rows/blobs before migration work.

**Exit gate:** A user can open Neurohub from the NMTK app, sign in against a fake server, list workspaces, download one, and publish one through a single injected client. Existing workspace round-trip tests pass.

### Phase 1: Define the Gitea contract and test harness

- Add `GiteaRepositoryRef`, `NeurohubManifest`, workspace revision, collaborator, release, and conflict contracts before router/service changes.
- Freeze manifest schema v1 and repository naming rules. Repository names should be deterministic, collision-safe, and reversible to a `neurohub://` URI.
- Build a test-only Gitea adapter fake from captured OpenAPI responses; do not scatter raw JSON dictionaries through services.
- Add an integration-test Gitea container pinned to the supported version, with Actions disabled and disposable local storage.
- Add a capability preflight: version, API access, OAuth discovery, repository creation, multi-file commit, releases/attachments, topics, collaborator permissions, and archive behavior.

**Exit gate:** Contract/property tests prove manifest round-trip, URI round-trip, path traversal rejection, checksum validation, semver mapping, visibility mapping, and stable error translation.

### Phase 2: Add Gitea as a storage backend behind Neurohub

- Introduce a narrow `RegistryStore` boundary covering identity lookup, repository CRUD, atomic content commits, releases, search, collaboration, archive, stars, and discussions.
- Wrap the existing SQL/object-storage implementation as `SqlRegistryStore` without changing its behavior.
- Implement `GiteaRegistryStore` using a typed `GiteaClient` with bounded timeouts, pagination, retry-after handling, and idempotency checks.
- Select with `NEUROHUB_STORAGE_BACKEND=sql|gitea`; default remains `sql` until migration validation passes.
- Refactor routers to depend on the store boundary, not SQLAlchemy sessions. Keep DB injection only inside the legacy store.
- Change health reporting from `db/storage` to named dependency checks (`gitea_api`, `gitea_storage_capability`, `version`) while preserving a compatibility projection for old clients.
- Use Gitea's atomic multi-file commit endpoint for workspace/manifest updates and the release attachment API for large immutable payloads.
- Add request correlation IDs but redact authorization headers, clone URLs containing tokens, and attachment signed URLs.

**Exit gate:** The same API contract suite passes once against SQL and once against the real disposable Gitea container, except explicitly documented v2 semantic changes.

### Phase 3: Replace Supabase Auth with Gitea OAuth

- Add OAuth discovery/config endpoints to Neurohub and implement Gitea token validation/user projection.
- Add PKCE sign-in, callback, refresh, sign-out, expired-session recovery, and account-switch flows in the app.
- Map the Gitea username to the `owner` segment of `neurohub://` URIs.
- Add secure-token-storage tests and prove tokens never appear in logs or crash reports.
- Remove Supabase SDK use from active clients only after Gitea auth E2E is green.

**Exit gate:** New users can register/sign in through Gitea, create a private workspace, reopen it on another device, share it with another account, and revoke that access without administrator help.

### Phase 4: Workspace sync and sharing

- Implement create/list/open/save/history/archive for workspace repositories.
- Save a workspace plus manifest as one commit with the prior commit SHA as the concurrency precondition.
- Add clear app states for offline, saving, saved, conflict, permission lost, quota exceeded, and server unavailable.
- Implement collaborators with `read`, `write`, and `admin` mappings; show the effective permission in the app.
- Add “Save a copy” and “Resolve conflict” paths so a conflict never destroys either side.
- Keep local workspace save working when Neurohub is offline; queue only an explicit retry marker, not silent background overwrites.

**Exit gate:** Two-user concurrent-edit tests cover clean sequential saves, stale-base conflict, permission revocation mid-save, retry after timeout, and offline recovery.

### Phase 5: Published artefacts and discovery

- Map each published artefact to a repository, manifest, topics, semantic tag, and Gitea release.
- Upload large payloads as release attachments and verify SHA-256 after download.
- Use repository search plus topics for coarse filtering, then read manifests for type-specific filters such as hardware target and neuron model.
- Add a bounded metadata cache only if measured latency requires it. The cache is disposable and must not become another authoritative database.
- Replace ratings with stars and comments with native discussions/issues in v2.
- Preserve `neurohub://` pull/push behavior in `neurocli` through the Neurohub API facade.

**Exit gate:** Every supported artefact type can publish, search, resolve latest semver, download exact versions, verify checksums, archive, and restore.

### Phase 6: Build and rehearse the migration

Create an idempotent, resumable operator migration command inside the Neurohub package, not an ad-hoc root script.

For each source user/project/asset/artefact:

1. Export source rows and blobs with checksums.
2. Pre-create or map the Gitea user/org.
3. Create the target repository private by default.
4. Commit manifest, README, and small payloads with preserved author/timestamps where the Gitea API allows.
5. Create semantic tags/releases and upload large payloads.
6. Add collaborators/teams.
7. Convert comments to issues/comments and ratings to a clearly labelled archival JSON file; do not invent stars on behalf of users.
8. Record source ID -> owner/repository/tag/commit mapping in a local migration report.
9. Read everything back through the Neurohub API and compare counts, sizes, SHA-256 values, visibility, membership, and latest-version resolution.

Run the migration against a production-shaped copy at least twice. The second run must make zero duplicate repositories, releases, attachments, or comments.

**Exit gate:** The reconciliation report has zero unexplained missing records/blobs and every mismatch is classified as transformed, intentionally dropped, or blocking.

### Phase 7: Cutover, canary, and rollback

1. Announce a short Neurohub maintenance window; private NMTK runtimes remain unaffected.
2. Put Supabase-backed Neurohub writes into read-only mode.
3. Run the final incremental migration and reconciliation.
4. Switch `NEUROHUB_STORAGE_BACKEND=gitea` and Gitea OAuth on the central service.
5. Canary with operator accounts, then a small user cohort, then all users.
6. Monitor auth failures, Gitea latency/error rate, save conflicts, checksum failures, migration misses, and release upload failures.
7. Keep the old SQL/object store read-only for at least one release cycle.

Rollback before new Gitea writes is a config switch back to SQL. After new Gitea writes, rollback must keep Gitea read-only and use the migration report/reverse exporter; never switch back silently and strand new commits.

**Exit gate:** Seven days without unexplained data loss, permission leaks, checksum mismatches, or sustained error-budget breach.

### Phase 8: Remove Supabase and legacy persistence

- Remove Supabase auth, SQLAlchemy/Alembic registry startup, object-storage, MeiliSearch, Redis refresh-token, and PostgreSQL optional dependencies only after the rollback window closes.
- Delete the legacy store and its migrations from runtime packaging, but retain a documented migration utility/version for operators with old installations.
- Remove dead legacy assets/shares/projects routes only after all clients, seed tooling, load tests, and docs use the repository-backed API.
- Update the Neurohub spec, README, deployment docs, security docs, release notes, and operator backup/restore runbook.
- Add a new GBrain cross-file invariant recording that manifest schema, `neurohub://` URI grammar, Dart models, Python contracts, and CLI parser must stay synchronized.

**Exit gate:** A clean deployment starts with only the central Neurohub API and Gitea configuration; no Supabase, Neurohub SQL database, object bucket, or MeiliSearch setting is required.

## Data migration rules

- **No destructive source cleanup during import.** Supabase/SQL data stays untouched until reconciliation and the rollback window finish.
- **Visibility defaults to private.** Preserve explicit public state only; uncertainty never becomes public exposure.
- **Identity collisions stop the affected user.** Never auto-merge accounts by similar names. Match verified email first, then an explicit operator mapping.
- **Checksums are mandatory.** A blob without a matching SHA-256 is not migrated.
- **Versions remain immutable.** A duplicate owner/slug/version with different content is a blocker, not an overwrite.
- **Timestamps are best effort, provenance is exact.** If Gitea cannot preserve a resource timestamp, write the original timestamp and source ID into migration metadata.
- **Partial failures are resumable.** Every operation has a stable idempotency key derived from source type and source ID.
- **Secrets are never exported.** Supabase tokens/password state and Gitea admin tokens do not enter migration reports.

## Gitea deployment and operations

The operator-hosted Gitea deployment needs:

- TLS and a stable public hostname.
- SMTP for invitations, verification, and password reset.
- A supported external PostgreSQL database for production unless the chosen hosting platform provides an equally durable supported option.
- Persistent repository storage and release-attachment storage; S3-compatible object storage is recommended when the host supports it.
- OAuth2 enabled, one public PKCE client registered, and only the needed repository/user scopes requested.
- Repository creation limits, attachment size limits, and total storage quotas set explicitly. Gitea defaults include several unlimited values that are unsafe for a public sharing service.
- Gitea Actions disabled initially; Neurohub does not require arbitrary user workflow execution.
- Metrics enabled and scraped; alerts for API failure rate, disk/object-store capacity, DB health, queue backlog, and backup age.
- Backups covering the Gitea database, repositories, configuration/secrets, and attachment/object storage. Restore drills are required; a backup that has never been restored is not an exit gate.
- A pinned Gitea version and staged upgrade rehearsal. Neurohub preflight should fail as `unsupported server version`, not expose raw API errors.

Gitea documents OAuth2/OIDC and PKCE, granular scopes, repository and multi-file content APIs, releases, collaborators, repository search, configurable object storage/LFS/attachment limits, and backup/restore. Relevant official references:

- [OAuth2 provider and PKCE](https://docs.gitea.com/1.26/development/oauth2-provider)
- [API authentication and OpenAPI discovery](https://docs.gitea.com/next/development/api-usage)
- [Gitea API](https://docs.gitea.com/api/1.26/)
- [Configuration and storage limits](https://docs.gitea.com/administration/config-cheat-sheet)
- [Backup and restore](https://docs.gitea.com/usage/backup-and-restore)

## Failure modes and required behavior

| Failure | Required behavior | Test |
|---|---|---|
| Gitea unavailable | Keep local work; show retry, never report saved | Integration |
| OAuth token expired | Refresh once; if rejected, return to sign-in without losing edits | E2E |
| Permission revoked mid-save | Return permission error and offer local export/save-copy | E2E |
| Concurrent save | Return 409 with base/local/remote revisions | E2E |
| Multi-file commit rejected | No partial workspace revision; retry is idempotent | Integration |
| Release upload times out after success | Probe by tag/name/checksum before retrying | Integration |
| Attachment checksum mismatch | Quarantine/block download and alert operator | Integration |
| Repository renamed in Gitea UI | Resolve by immutable repository ID, update cached URI projection | Integration |
| Repository deleted outside Neurohub | Return gone/repair guidance, never recreate silently | Integration |
| Search returns more than one page | Traverse Gitea pagination with a bounded maximum | Unit + integration |
| Gitea rate limit reached | Honor retry metadata and show a retry time | Unit + E2E |
| Storage quota exceeded | Preserve local work and show operator/user action | E2E |
| Migration interrupted | Resume from report without duplicates | Migration E2E |
| Backup is incomplete | Restore drill fails the release gate | Operations |
| Private repository leaks in search/feed | Treat as a P0 security failure | Security E2E |

## Test plan

```text
CONTRACTS
  manifest parse/serialize
  neurohub:// URI round-trip
  semver/tag mapping
  visibility + permission mapping
  legacy response compatibility
        |
        v
STORE CONTRACT (run against both backends during migration)
  create -> read -> update -> list -> archive
  atomic workspace save + stale-base conflict
  publish -> release -> attachment -> checksum download
  collaborator add/remove + access denial
  search pagination + filters + private visibility
        |
        v
REAL GITEA INTEGRATION
  OAuth user token
  repository APIs
  multi-file commit
  tags/releases/attachments
  topics/search/stars/issues
  timeout/rate-limit/error translation
        |
        v
USER E2E
  sign in -> create private workspace -> save -> reopen
  share -> second user edits -> first user sees revision
  concurrent edits -> resolve or save copy
  publish artefact -> search -> exact-version download
  offline/expired token/revoked permission/quota full
        |
        v
MIGRATION + OPERATIONS
  export -> import -> reconcile -> rerun idempotently
  canary cutover -> rollback rehearsal
  backup -> empty-host restore -> checksum comparison
```

Required verification during implementation:

- Neurohub backend unit, property, contract, and Gitea-container integration tests.
- Neurohub Dart client and native feature widget tests.
- CNL Studio workspace publish/import tests.
- `neurocli hub push/pull/search` compatibility tests.
- Root cross-module integration tests because the shared client and workspace handoff cross module boundaries.
- Launcher guardrails only if `modules.json`, deployment assets, startup semantics, or Backend Setup behavior changes.
- Security tests using two normal users, one organization/team, one admin, public/private repositories, revoked tokens, and malicious manifest/path inputs.

The implementation is not complete if tests only mock Gitea. At least one CI lane must run against a real pinned Gitea container.

## Observability and service objectives

Track:

- request count, latency, and error rate by Neurohub operation, not by raw token/user;
- Gitea API latency/status, pagination volume, rate limits, and version;
- workspace save conflict rate and failed retry count;
- release upload size, duration, and checksum failures;
- migration totals and unmatched source/target records;
- private-resource authorization denials and any visibility mismatch;
- backup age and last successful restore drill.

Initial targets:

- 99.9% monthly availability for read/open/download;
- 99.5% monthly availability for write/publish;
- p95 workspace metadata open under 1.5 seconds excluding large payload transfer;
- zero private-repository visibility leaks and zero accepted checksum mismatches.

## Parallel implementation lanes

The work crosses module contracts, so split only after Phase 1 freezes the manifest and API shapes.

- **Lane A, Neurohub backend:** contracts -> Gitea client/store -> routers -> migration command -> operations.
- **Lane B, NMTK/Flutter:** shared Dart client -> OAuth/secure storage -> native Neurohub surfaces.
- **Lane C, consumers:** CNL Studio plus neurocli compatibility after the shared client/contracts land.
- **Lane D, infrastructure/testing:** disposable Gitea, CI integration lane, monitoring, backup/restore rehearsal.

Launch A and D first. Once manifest/auth/API contracts are frozen, B and C can proceed in parallel; cutover and cleanup remain sequential.

## NOT in scope

- Hosting a separate Gitea instance inside every user's private NMTK backend; this would fragment discovery and burden end users.
- Allowing arbitrary Gitea Actions from shared repositories in the first release; Neurohub needs storage/versioning, not untrusted code execution.
- A general-purpose Git client UI, pull-request review UI, or full Gitea administration console inside NMTK.
- Transparent live collaborative editing; this plan provides revisioned saves and explicit conflict resolution.
- Moving module-specific runtime databases such as NeuroSense recordings or NeuroBench job state into Gitea. Only artefacts/workspaces intentionally saved or shared through Neurohub move.
- Fabricating equivalents for relational features Gitea does not natively support. v2 may simplify or remove ratings/download counters/follow feeds.
- Permanent deletion during the migration window. Archive first; purge is a later retention-policy feature.

## Final go/no-go checklist

Go only when all are true:

- [ ] Central Neurohub URL and Gitea hostname/TLS are production-ready.
- [ ] OAuth PKCE, SMTP recovery, and secure token storage work on every shipped platform.
- [ ] Real-Gitea contract/E2E suites are green.
- [ ] Private repository visibility and collaborator authorization security tests are green.
- [ ] Migration dry run and second idempotent run reconcile exactly.
- [ ] Cutover and rollback have both been rehearsed.
- [ ] Backup and empty-host restore have been verified by checksum.
- [ ] All clients use the central Neurohub API rather than the user's private backend.
- [ ] Supabase remains read-only and recoverable through the agreed rollback window.
- [ ] Operator docs and in-app user recovery messages are complete.

## Recommended first implementation slice

Build a vertical workspace-only slice before migrating every artefact type:

1. Freeze `NeurohubManifest` v1 and the central URL/auth contracts.
2. Run a real disposable Gitea and implement PKCE plus the typed Gitea client.
3. Create/open/save one private `studio_workspace` repository with atomic commits and conflict detection.
4. Add/remove one collaborator and verify access with a second user.
5. Wire CNL Studio to the shared Neurohub client.
6. Prove export/import migration for existing `studio_workspace` assets.

This slice validates the hardest architectural claims: identity, permissions, atomic revision history, central routing, cross-module client reuse, and migration. Once it passes, published artefact releases and community/discovery mappings are additive rather than another storage rewrite.
