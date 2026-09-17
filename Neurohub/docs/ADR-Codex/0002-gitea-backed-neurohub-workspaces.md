# ADR 0002: Gitea-backed Neurohub workspaces

## Status

Accepted

## Context

Neurohub's relational database, object store, search service, and Supabase client design split a
single user concept across several persistence systems. The suite also needs workspace backup,
revision history, sharing, and publishing, which already match repository behavior.

Neurohub must remain the product and API boundary. Desktop clients should not learn Gitea API
details, and users should not enter server ports, personal access tokens, or storage credentials.

## Decision

Neurohub workspace persistence uses one Gitea repository per workspace. Repositories are private by
default, `.neurohub/manifest.json` is the schema-versioned metadata source, and
`workspace.nmtk.json` is the editable payload.

The stateless Neurohub FastAPI service validates contracts and translates a user-scoped Gitea OAuth
token into repository operations. It uses one atomic multi-file commit per explicit save, requires
the caller's base commit, returns HTTP 409 for concurrent changes, maps collaborators to Gitea
permissions, and maps deletion to repository archive.

Clients use OAuth2 Authorization Code with PKCE against a centrally configured Gitea 1.26.x or
newer instance. Neurohub never stores user tokens or uses an administrator token for normal
requests; Gitea repository visibility and permissions are authoritative.

This decision supersedes the persistence and identity direction in the PostgreSQL, Firebase,
Supabase, and JWT ADRs for the new workspace surface. Historical ADRs remain unchanged, and legacy
SQL-backed endpoints stay available only during the migration window.

## Consequences

- Workspace history, access control, backup, and restore use Gitea's native primitives.
- `neurohub://studio_workspace/{owner}/{slug}` remains stable if the Gitea host moves.
- A Gitea outage prevents remote sync but must not prevent local workspace saves.
- Existing SQL/object-storage registry data needs a separate, resumable migration before those
  legacy services can be removed from production deployment.
- Large immutable artefacts will use release attachments; they are not stored in workspace Git
  history.

## Verification

Contract tests cover manifest validation, safe repository paths, checksums, and stable conflict
responses. Adapter tests cover pagination, error translation, atomic commit payloads, sharing,
visibility, and archive behavior; the disposable compose file pins the supported Gitea baseline for
live capability tests.
