# Requirements Document

## Introduction

The Neurohub Global Registry expands the existing `Neurohub` module from a local registry-and-metadata service into a production-grade, publicly-hostable backend service and community portal for the neuromorphic AI ecosystem. It provides a centralised registry for sharing and discovering neuromorphic AI artefacts — including `.cnl` templates, full `.cnlspace` workspace sessions, SNN models, and neuromorphic datasets — under a `neurohub://` URI scheme. The feature comprises three tightly-coupled workstreams: a scalable FastAPI registry backend, a community portal (Flutter/Next.js), and a universal `neurohub-cli` that integrates with `neurocli` to enable publish/pull workflows from within the NMTK development environment.

This registry is architecturally consistent with the existing Neurohub ownership boundaries: Neurohub owns artefact metadata, community interactions, and sharing surfaces; `nmtk` retains ownership of suite lifecycle, workspace hosting, and runtime health; and `neurocli` retains ownership of CLI scaffolding and launcher manifest semantics.

---

## Glossary

- **Registry**: The Neurohub Global Registry service — the publicly-hostable FastAPI backend that stores and serves artefact metadata, file blobs, and community data.
- **Artefact**: A versioned, typed, registry-managed resource. Concrete types are defined in the Artefact Type table below.
- **CNL_Template**: An artefact of type `cnl_template` — a reusable `.cnl` file or partial specification exported from neurocnl.
- **CNLspace**: An artefact of type `cnlspace` — a full `.cnlspace` workspace session bundle exported from the NMTK UI.
- **SNN_Model**: An artefact of type `snn_model` — pre-trained spike neural network weights and architecture in NIR format.
- **Dataset**: An artefact of type `dataset` — a neuromorphic dataset (event streams, spike recordings, EMG, DVS).
- **Model_Card**: A structured metadata document attached to an SNN_Model artefact that describes training details, benchmark results, hardware targets, and ethical considerations.
- **neurohub_URI**: A URI conforming to the scheme `neurohub://{type}/{owner}/{slug}@{version}`.
- **Owner**: A namespaced user or organisation identity in the Registry, expressed as `{username}` or `{org}/{username}` (1–64 lowercase alphanumeric characters and hyphens, starting with an alphanumeric character).
- **Slug**: A URL-safe, lowercase, hyphenated artefact identifier unique within the owner's namespace (1–64 lowercase alphanumeric characters and hyphens, starting with an alphanumeric character).
- **Version**: A semantic version string (MAJOR.MINOR.PATCH) identifying a specific artefact revision.
- **Community_Portal**: The web-based discovery and collaboration frontend — implemented in Flutter Web (primary NMTK integration surface) and a companion Next.js site (public-facing).
- **neurohub_CLI**: The `neurohub` sub-command group within `neurocli` (or a standalone `neurohub-cli` package) that provides `push`, `pull`, `search`, and `login` commands using `neurohub://` URIs.
- **Model_Zoo**: The curated collection of SNN_Model artefacts discoverable through the Community_Portal and Registry API.
- **Suite_Client**: The existing `neurohub/app/services/suite_client.py` — the single, centralised point for all outbound cross-module HTTP calls from Neurohub.
- **Object_Storage**: An S3-compatible storage backend (MinIO for self-hosted; AWS S3 for cloud) used to store artefact file blobs.
- **Search_Index**: A MeiliSearch-backed full-text and filtered search index over artefact metadata.
- **JWT**: A JSON Web Token used for authentication and authorisation within the Registry.
- **Rate_Limiter**: The existing `neurohub/app/limiter.py` extended to cover all public Registry endpoints.
- **Contract**: A Pydantic v2 model in `neurohub/contracts/` that defines the canonical payload shape for a Registry resource.

---

## Artefact Types

| Type Key | Description | File Extension |
|---|---|---|
| `cnl_template` | Reusable CNL specification template | `.cnl` |
| `cnlspace` | Full NMTK workspace session bundle | `.cnlspace` |
| `snn_model` | Pre-trained SNN weights + NIR architecture | `.nir` / `.pt` |
| `dataset` | Neuromorphic dataset (event streams, EMG, DVS) | `.h5` / `.zip` |
| `hardware_profile` | Extended public hardware profile + quantisation config | `.json` |
| `encoding_preset` | Spike encoding configuration | `.json` |
| `benchmark_baseline` | Community benchmark result set | `.json` |

---

## Requirements

---

### Requirement 1: Registry Artefact CRUD

**User Story:** As a neuromorphic researcher, I want to publish, retrieve, update, and delete artefacts in the Registry, so that I can manage the lifecycle of my shared work.

#### Acceptance Criteria

1. WHEN a registered user submits a valid artefact payload with a unique `{owner}/{slug}@{version}` identifier, THE Registry SHALL create the artefact record, persist the metadata to the database, upload the associated file blob to Object_Storage, and return the created artefact with an HTTP 201 response.
2. WHEN a client requests an artefact by `{owner}/{slug}@{version}`, THE Registry SHALL retrieve and return the artefact metadata and a pre-signed download URL (valid for 15 minutes) for the blob within 500 ms under a load of up to 100 concurrent requests.
3. WHEN a registered user submits an update to an artefact they own, THE Registry SHALL replace the mutable metadata fields (description, tags, readme) while preserving the immutable fields (type, owner, slug, version, sha256, created_at) and return the updated artefact.
4. WHEN a registered user requests deletion of an artefact they own, THE Registry SHALL soft-delete the artefact record (making it immediately inaccessible to all clients) and schedule the Object_Storage blob for removal, returning HTTP 204.
5. IF a client submits an artefact payload where `{owner}/{slug}@{version}` already exists, THEN THE Registry SHALL return HTTP 409 with a conflict message identifying the duplicate identifier.
6. IF a client requests an artefact that does not exist or has been soft-deleted, THEN THE Registry SHALL return HTTP 404.
7. IF a client submits an artefact payload with a type value not in the seven keys defined in the Artefact Types table, THEN THE Registry SHALL return HTTP 422 with a Contract validation error identifying the invalid type.
8. WHEN an artefact blob is stored, THE Registry SHALL compute and persist the SHA-256 checksum; WHEN the blob is subsequently requested, THE Registry SHALL verify the checksum matches the stored value before serving the pre-signed URL and return HTTP 500 if the checksum does not match.
9. WHEN an authenticated user attempts to update or delete an artefact they do not own, THE Registry SHALL return HTTP 403 and SHALL NOT execute the modification.

---

### Requirement 2: Semantic Versioning and Artefact Namespacing

**User Story:** As a developer publishing CNL templates or models, I want my artefacts versioned under my namespace, so that consumers can pin to specific versions and track changes.

#### Acceptance Criteria

1. THE Registry SHALL enforce that every artefact identifier follows the `{owner}/{slug}@{version}` pattern, where `owner` and `slug` are each 1–64 lowercase alphanumeric characters and hyphens starting with an alphanumeric character, and `version` is a valid semantic version string (MAJOR.MINOR.PATCH).
2. WHEN a client requests `neurohub://{type}/{owner}/{slug}` without an explicit version and at least one non-prerelease version exists, THE Registry SHALL resolve the reference to the latest non-prerelease version of that artefact and return the resolved version in the response.
3. WHEN a client requests `neurohub://{type}/{owner}/{slug}` without an explicit version and no non-prerelease version exists, THE Registry SHALL return HTTP 404 with a message stating that no stable version is available.
4. WHEN a client requests `GET /api/v1/artefacts/{owner}/{slug}/versions` for an artefact that exists, THE Registry SHALL return all available versions in descending semantic order.
5. IF a client requests `GET /api/v1/artefacts/{owner}/{slug}/versions` for an artefact that does not exist, THEN THE Registry SHALL return HTTP 404.
6. WHEN an artefact creation or update request is submitted, THE Registry SHALL validate the version string against MAJOR.MINOR.PATCH semver format and return HTTP 422 with a validation error identifying the `version` field and the expected MAJOR.MINOR.PATCH format if invalid; version format validation is not applied to retrieval requests.
7. THE Registry SHALL be able to parse any conformant neurohub_URI string into its component fields (type, owner, slug, version) and reassemble the original URI from those components without loss of information (round-trip property).

---

### Requirement 3: neurohub:// URI Scheme Resolution

**User Story:** As a developer working within the NMTK environment, I want to reference artefacts via `neurohub://` URIs, so that I can pull artefacts into my workflow without managing raw HTTP URLs.

#### Acceptance Criteria

1. THE neurohub_CLI SHALL accept `neurohub://{type}/{owner}/{slug}@{version}` as a valid artefact reference for `pull`, `push`, and `inspect` commands.
2. WHEN a `neurohub pull neurohub://{type}/{owner}/{slug}@{version}` command is executed, THE neurohub_CLI SHALL resolve the URI against the configured Registry endpoint, download the artefact blob to the specified local path (defaulting to `{slug}@{version}.{ext}` in the current working directory), verify the SHA-256 checksum, print success to stdout and exit 0 on match, or print a checksum mismatch error to stderr, delete the downloaded file, and exit 1 on mismatch.
3. WHEN a `neurohub push` command is executed with a local file and a target `neurohub://` URI, THE neurohub_CLI SHALL upload the file to the Registry, register the artefact metadata, and — only when both upload and metadata registration succeed — print the canonical neurohub_URI of the published artefact to stdout and exit with status code 0; IF either step fails, THE neurohub_CLI SHALL suppress all success indicators, print a descriptive error to stderr, and exit with a non-zero status code.
4. IF a `neurohub pull` command references a neurohub_URI where the artefact does not exist, THEN THE neurohub_CLI SHALL print a descriptive error message to stderr and exit with status code 1.
5. THE neurohub_CLI SHALL store the authenticated Registry endpoint URL and JWT token in the OS-appropriate credentials store so that repeated commands do not require re-authentication.
6. WHEN the NMTK UI triggers a "Share to Neurohub" action on a `.cnl` file or `.cnlspace` session, THE Suite_Client SHALL construct the neurohub_URI from user-supplied slug, version, and type metadata, and invoke the neurohub_CLI push workflow, returning the published URI to the UI for display.
7. IF the Suite_Client push workflow fails, THEN THE Suite_Client SHALL return the error response to the NMTK UI without retrying, and THE NMTK UI SHALL surface the failure to the user per Requirement 12 Criterion 4.

---

### Requirement 4: Full-Text Artefact Search and Discovery

**User Story:** As a researcher, I want to search the Registry for artefacts by keyword, type, hardware target, and neuron model, so that I can discover relevant models and datasets for my experiments.

#### Acceptance Criteria

1. THE Registry SHALL expose a `GET /api/v1/search` endpoint accepting: `q` (free-text, max 500 characters; omitting `q` or passing an empty string returns all artefacts), `type`, `hardware_target`, `neuron_model`, `tags`, `owner`, `page` (integer ≥1, default 1), and `page_size` (integer 1–100, default 20).
2. WHEN a search request is submitted with valid parameters, THE Registry SHALL return HTTP 200 with matching artefacts ranked by relevance and pagination metadata (`total`, `page`, `page_size`, `next_cursor`); `next_cursor` SHALL be null on the last page.
3. IF a search request contains invalid parameters (page or page_size out of range, or `q` exceeding 500 characters), THEN THE Registry SHALL return HTTP 422 with a validation error identifying the offending parameter.
4. THE Registry SHALL index artefact name, description, tags, readme, owner, and type fields in the Search_Index; WHEN an artefact is created, updated, or deleted, THE Registry SHALL update the Search_Index within 5 seconds.
5. WHEN a search query is submitted with no matching results, THE Registry SHALL return an empty result list with HTTP 200 and pagination metadata showing `total: 0`.
6. THE Community_Portal SHALL provide a search interface that debounces user input and issues a search request to THE Registry no more than once per 300 ms of inactivity.
7. WHERE full-text search is unavailable because all Search_Index nodes are unreachable within the connection timeout, THE Registry SHALL fall back to SQL `ILIKE` filtering on name and description fields and include a `"search_degraded": true` flag in the response; this flag SHALL NOT be set when the index is available but slow.
8. WHEN filter parameters (`type`, `hardware_target`, `neuron_model`, `owner`) are specified, THE Registry SHALL apply them as case-insensitive exact-match filters; when multiple `tags` values are specified, THE Registry SHALL return artefacts matching any of the specified tags (OR semantics).
9. IF Search_Index synchronisation fails after a successful artefact write, THEN THE Registry SHALL still persist the artefact, set `search_degraded: true` in subsequent search responses, and retry synchronisation within 30 seconds.

---

### Requirement 5: Model Cards

**User Story:** As a model publisher, I want to attach a structured Model Card to my SNN model artefact, so that consumers can understand training context, performance benchmarks, hardware compatibility, and ethical considerations.

#### Acceptance Criteria

1. WHEN an artefact of type `snn_model` is created or updated, THE Registry SHALL accept an optional `model_card` object where all fields (`architecture`, `training_framework`, `training_dataset`, `hardware_targets`, `neurobench_scores`, `licence`, `ethical_considerations`, `readme_md`) are individually optional; `readme_md` SHALL be capped at 65,535 characters.
2. THE Registry SHALL store the Model_Card as a structured JSON field associated with the artefact record and return it as a nested object in artefact detail responses.
3. WHEN the artefact detail page loads, THE Community_Portal SHALL render Model_Card fields, displaying `neurobench_scores` as a sortable table and `ethical_considerations` under a visible section heading labelled "Ethical Considerations".
4. WHEN `neurobench_scores` contains entries, THE Community_Portal SHALL display each score with its benchmark name, metric, value, and hardware_target; entries with a missing `metric` or `value` field SHALL be rendered with a warning indicator and greyed-out value cells.
5. IF a `model_card` payload contains an unrecognised field, THEN THE Registry SHALL accept the artefact, strip the unrecognised field from storage, and return a `warnings` array in the response body identifying each stripped field name.

---

### Requirement 6: Community Interactions — Ratings, Comments, and Follows

**User Story:** As a community member, I want to rate artefacts, leave comments, and follow other users, so that I can participate in the neuromorphic AI ecosystem and surface high-quality work.

#### Acceptance Criteria

1. WHEN an authenticated user submits a rating for an artefact (integer 1–5), THE Registry SHALL record the rating, recompute the artefact's `average_rating` (rounded to 2 decimal places) and `rating_count`, and return the updated aggregates; IF the artefact does not exist, THE Registry SHALL return HTTP 404.
2. IF an authenticated user submits a second rating for the same artefact, THEN THE Registry SHALL replace the previous rating with the new value and recalculate the aggregates.
3. WHEN an authenticated user posts a comment on an artefact, where the comment content is a non-empty string of 1–4000 characters, THE Registry SHALL persist the comment with `author_id`, `created_at` (UTC ISO 8601), and `content`, and return the persisted comment with HTTP 201; IF the artefact does not exist, THE Registry SHALL return HTTP 404.
4. IF a comment payload is empty (zero characters) or exceeds 4000 characters, THEN THE Registry SHALL return HTTP 422 with a validation error stating the 1–4000 character constraint and SHALL NOT persist the comment.
5. WHEN `GET /api/v1/artefacts/{owner}/{slug}/comments` is requested, THE Registry SHALL return comments in descending `created_at` order with pagination (default page_size 20, max 100); IF no comments exist, THE Registry SHALL return an empty list with HTTP 200.
6. WHEN an authenticated user follows another user, THE Registry SHALL record the follow relationship; WHEN the followed user publishes a new artefact, THE Registry SHALL add an activity feed entry containing `follower_id`, `followed_user_id`, `artefact_id`, and `event_type: "new_artefact"` within 10 seconds.
7. IF a user attempts to follow themselves, THEN THE Registry SHALL return HTTP 400 with a message stating that self-follows are not permitted.
8. WHEN an authenticated user deletes their own comment, THE Registry SHALL permanently remove the comment record and return HTTP 204.
9. IF a user attempts to follow a user they already follow, THEN THE Registry SHALL return HTTP 409 with a message stating the follow relationship already exists.
10. IF an unauthenticated user or a user who does not own the comment attempts to delete a comment, THEN THE Registry SHALL return HTTP 401 or HTTP 403 respectively and SHALL NOT remove the comment.

---

### Requirement 7: Authentication and Authorisation

**User Story:** As a Registry operator, I want all mutating operations to require authentication, and all user-specific resources to be protected by ownership checks, so that artefacts and community data remain secure.

#### Acceptance Criteria

1. WHEN a user submits valid credentials to `POST /api/v1/auth/login`, THE Registry SHALL issue a signed JWT containing `user_id`, `username`, `roles`, and `exp` claims with expiry configurable via `JWT_EXPIRY_HOURS` (defaulting to 24 hours), and return HTTP 200.
2. WHEN a user submits a registration request to `POST /api/v1/auth/register` with a unique `username`, `email`, and `password`, THE Registry SHALL create the user account and return HTTP 201.
3. THE Registry SHALL hash all passwords with bcrypt before storage and SHALL NOT store plaintext passwords under any circumstances.
4. IF a registration request uses a `username` or `email` that already exists in the Registry, THEN THE Registry SHALL return HTTP 409 with a message identifying which field conflicts.
5. WHEN an unauthenticated request is made to a mutating endpoint (POST, PUT, PATCH, DELETE), THE Registry SHALL return HTTP 401 with a `WWW-Authenticate: Bearer` header and SHALL NOT execute the mutation.
6. WHEN an authenticated user attempts to modify or delete a resource owned by a different user, THE Registry SHALL return HTTP 403 and SHALL NOT execute the modification.
7. IF a JWT presented on an authenticated request is expired, structurally invalid, missing required claims, or has an invalid signature, THEN THE Registry SHALL return HTTP 401.
8. WHEN a valid, non-expired refresh token is submitted to `POST /api/v1/auth/refresh`, THE Registry SHALL issue a new JWT without requiring re-entry of credentials; IF the refresh token is invalid or expired, THE Registry SHALL return HTTP 401.
9. WHERE the admin role is assigned to a user, THE Registry SHALL allow that user to delete any artefact or comment regardless of ownership.

---

### Requirement 8: Rate Limiting

**User Story:** As a Registry operator, I want API rate limits applied to all public endpoints, so that the service remains available to all users under high load or abuse.

#### Acceptance Criteria

1. THE Rate_Limiter SHALL enforce a limit of 60 requests per 60-second fixed window per IP address on all unauthenticated endpoints.
2. THE Rate_Limiter SHALL enforce a limit of 300 requests per 60-second fixed window per authenticated user on all authenticated endpoints.
3. THE Rate_Limiter SHALL enforce a limit of 10 requests per 60-second fixed window per IP address on `POST /api/v1/auth/login`.
4. WHEN a rate limit is exceeded, THE Registry SHALL return HTTP 429 with `Retry-After`, `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` (UTC epoch seconds, reset at window boundary) headers.
5. THE Registry SHALL include `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` headers on every response from a rate-enforced endpoint, regardless of whether the limit has been reached.
6. THE Rate_Limiter SHALL track all rate-limit counters in the Redis-compatible store configured via `CACHE_URL`; a counter that fails to persist SHALL be treated as zero (allow the request) and logged at WARN level.

---

### Requirement 9: Object Storage and Blob Integrity

**User Story:** As a Registry operator, I want all artefact file blobs stored in S3-compatible Object_Storage with integrity verification, so that published artefacts are durable, corruption-free, and efficiently served.

#### Acceptance Criteria

1. THE Registry SHALL store all artefact file blobs in Object_Storage using the key pattern `{artefact_type}/{owner}/{slug}/{version}/{filename}`.
2. WHEN a blob upload completes, THE Registry SHALL compute the SHA-256 checksum of the uploaded bytes and persist it alongside the artefact metadata in the database.
3. WHEN a download URL is requested, THE Registry SHALL verify the stored checksum against the blob in Object_Storage before generating a pre-signed URL valid for a maximum of 1 hour; IF the checksum does not match, THE Registry SHALL return HTTP 500 and log the integrity failure.
4. IF Object_Storage is unreachable during an artefact creation request, THEN THE Registry SHALL return HTTP 503 with a message indicating Object_Storage is unavailable and SHALL NOT persist any artefact metadata record.
5. THE Registry SHALL enforce a maximum blob size of 5 GB per artefact.
6. IF an upload exceeds the 5 GB limit, THEN THE Registry SHALL return HTTP 413 and SHALL NOT store any part of the blob.
7. THE Registry SHALL support multipart uploads for blobs larger than 100 MB; each part acknowledgement SHALL return a part identifier and its checksum; WHEN all parts are received, THE Registry SHALL assemble the final object as a single complete object only after all parts are successfully received; IF any part upload or assembly step fails, THE Registry SHALL return an error identifying the failed step and SHALL NOT store a partial object.

---

### Requirement 10: Database Schema and Migration

**User Story:** As a backend developer, I want the Registry database schema managed through Alembic migrations, so that schema changes are versioned, repeatable, and safe to apply in production.

#### Acceptance Criteria

1. THE Registry SHALL manage all schema changes through Alembic migration files stored in `neurohub/db/migrations/`; no schema change SHALL be applied by modifying SQLAlchemy model definitions without a corresponding migration file.
2. WHEN the Registry starts, THE Registry SHALL apply all pending Alembic migrations before any non-health-check endpoint begins accepting requests.
3. THE Registry SHALL support both SQLite (development/local) and PostgreSQL (production) as database backends, selectable via the `DATABASE_URL` environment variable.
4. FOR EVERY Alembic migration file that includes a downgrade implementation (a reversible migration), applying the upgrade followed by the downgrade SHALL return the database schema to its state prior to the upgrade without data loss.
5. IF the database is unreachable at startup, THEN THE Registry SHALL emit a structured log error including the error reason and the database host extracted from `DATABASE_URL` (excluding credentials) and exit with a non-zero status code.
6. IF an Alembic migration fails during startup, THEN THE Registry SHALL emit a structured log error identifying the failed migration revision and exit with a non-zero status code.

---

### Requirement 11: Community Portal — Artefact Discovery UI

**User Story:** As a researcher using the NMTK desktop application, I want an in-app browsing panel for the Global Registry, so that I can discover, preview, and import artefacts into my active project without leaving the NMTK environment.

#### Acceptance Criteria

1. THE Community_Portal SHALL render the artefact discovery feed as a paginated card grid (default page_size 20), where each card displays artefact name, type badge, owner, version, average rating, and download count.
2. WHEN a user selects an artefact card, THE Community_Portal SHALL display the full artefact detail view with two distinct controls: a "Download" action (saves blob to local filesystem) and an "Import to Project" action (adds artefact reference to the active project).
3. THE Community_Portal SHALL implement responsive layouts: two-column grid at ≥1440 px, single-column at <768 px.
4. THE Community_Portal SHALL use `NmtkShellMode.command` and the `NmtkShellTokens` semantic colour palette for all status indicators, consistent with existing Neurohub shell conventions.
5. WHEN a user triggers "Import to Project" on an artefact, THE Community_Portal SHALL invoke the neurohub_CLI pull workflow, display a progress indicator until the operation completes or errors; upon success, add the artefact's neurohub_URI to the active project's `ProjectLinks.registryRefs` field; upon failure, display the error from the CLI and a dismissal action.
6. WHEN the import operation does not complete within 120 seconds, THE Community_Portal SHALL cancel the operation, display a timeout error, and provide a dismissal action.
7. THE Community_Portal SHALL display artefact type badges using the seven canonical type keys; unrecognised type values SHALL render as a neutral "unknown" badge.
8. WHEN the Registry search endpoint returns `"search_degraded": true`, THE Community_Portal SHALL display a non-blocking informational banner indicating that search results may be incomplete.

---

### Requirement 12: NMTK UI — Share to Neurohub Integration

**User Story:** As an NMTK user, I want to publish a `.cnl` template or `.cnlspace` workspace session to the Global Registry directly from the NMTK UI, so that I can share my work with the community without switching to a separate tool.

#### Acceptance Criteria

1. WHEN a user selects "Share to Neurohub" on a `.cnl` file within neurocnl, THE NMTK UI SHALL prompt the user for slug, version, and optional description before submission; IF the selected file is not a `.cnl` file, THE NMTK UI SHALL take no action and produce no visible state change.
2. WHEN a user selects "Share to Neurohub" on a `.cnlspace` session, THE NMTK UI SHALL prompt the user for slug, version, and optional description; IF the selected item is not a `.cnlspace` file, THE NMTK UI SHALL take no action and produce no visible state change.
3. WHEN a share submission succeeds, THE NMTK UI SHALL display the canonical neurohub_URI of the published artefact in a panel that persists until explicitly dismissed, and offer a one-click "Copy URI" action.
4. IF a share submission fails due to a network error, Registry error, or an expired JWT (requiring re-authentication), THEN THE NMTK UI SHALL display a non-blocking error toast with the failure reason and a "Retry" action.
5. WHILE a share submission is in progress, THE NMTK UI SHALL display a progress indicator and disable the "Share to Neurohub" action to prevent duplicate submissions.
6. IF a share submission does not receive a response within 30 seconds, THEN THE NMTK UI SHALL treat it as a failure and apply criterion 4.
7. THE Suite_Client SHALL perform all Registry HTTP calls via the existing `neurohub/app/services/suite_client.py`; no new outbound HTTP paths SHALL be added outside that service.

---

### Requirement 13: neurohub-CLI — publish/pull/search Commands

**User Story:** As a developer working from the command line within the NMTK workflow, I want `neurohub push`, `neurohub pull`, and `neurohub search` commands, so that I can manage artefacts from scripts and CI pipelines.

#### Acceptance Criteria

1. THE neurohub_CLI SHALL implement `neurohub push <file> --type <type> --slug <slug> --version <version> [--description <desc>] [--tag <tag>]...` where `--type` must be one of the seven canonical type keys (exit 1 on invalid type), `--slug` must match the slug format constraint, `--description` is capped at 1000 characters, and `--tag` is accepted up to 20 times.
2. THE neurohub_CLI SHALL implement `neurohub pull <neurohub_URI> [--output <path>]` where, when `--output` is omitted, the blob is saved to `{slug}@{version}.{ext}` in the current working directory, and `{ext}` is derived from the artefact type's canonical file extension.
3. THE neurohub_CLI SHALL implement `neurohub search <query> [--type <type>] [--hardware <target>] [--limit <n>]` where `--limit` defaults to 20 and is capped at 100, and prints results as a formatted table with columns: name, type, owner, version, rating.
4. THE neurohub_CLI SHALL implement `neurohub login --registry <url>` to authenticate with a Registry instance and persist the JWT and endpoint URL in the OS credentials store.
5. WHEN `neurohub push` succeeds (both upload and metadata registration complete), THE neurohub_CLI SHALL print the canonical neurohub_URI of the published artefact to stdout and exit 0; IF the push is rejected with HTTP 409 or HTTP 422, THE neurohub_CLI SHALL print the Registry error to stderr and exit 1; IF the push fails due to a network or infrastructure error, THE neurohub_CLI SHALL print a descriptive error to stderr and exit 2.
6. IF `neurohub pull` encounters a SHA-256 checksum mismatch after download, THEN THE neurohub_CLI SHALL delete the downloaded file, print a checksum mismatch error to stderr, and exit with a non-zero status code only after both the deletion and the error message have completed.
7. THE neurohub_CLI SHALL read module identifiers from `nmtk/neuro_toolkit/assets/modules.json` and SHALL NOT introduce a separate module registry or endpoint catalog.
8. THE neurohub_CLI SHALL exit with status code 0 on success, status code 1 on user error (bad arguments, invalid type, artefact not found, HTTP 401, HTTP 403), and status code 2 on infrastructure error (network failure, Registry unavailable, HTTP 5xx).

---

### Requirement 14: Structured Logging and Observability

**User Story:** As a Registry operator, I want all API requests and significant events logged in structured JSON format, so that I can monitor service health, debug issues, and analyse usage patterns.

#### Acceptance Criteria

1. THE Registry SHALL emit a structured JSON log entry for every incoming HTTP request, including `timestamp`, `method`, `path`, `status_code`, `duration_ms`, `request_id`, and `user_id` (omitted, not null, when the request is unauthenticated).
2. WHEN an unhandled exception occurs within a request handler, THE Registry SHALL log the full exception traceback at ERROR level with the `request_id` included, return HTTP 500, and SHALL NOT include stack traces, internal file paths, or internal hostnames in the response body.
3. WHEN an artefact creation, update, deletion, or download event occurs, THE Registry SHALL emit a structured JSON log entry at INFO level including `timestamp`, `artefact_id`, `owner`, `type`, `action`, and `request_id`.
4. THE Registry SHALL expose a `GET /api/v1/health` endpoint returning `{"status": "ok"|"degraded", "db": "connected"|"disconnected", "storage": "connected"|"disconnected", "version": "<semver>"}` where `status` is `"degraded"` if either `db` or `storage` is `"disconnected"`, reflecting only Neurohub's own connectivity.
5. WHILE THE Registry is actively processing a request, THE Registry SHALL propagate the `X-Request-ID` header value (or generate a UUID v4 of at most 128 characters if absent) through all outbound HTTP calls to other Neurohub services and include it in the response headers.

---

### Requirement 15: Registry Backend — Production Deployment

**User Story:** As a Registry operator, I want the Registry deployable as a containerised service with environment-driven configuration, so that I can host it reliably in a production environment.

#### Acceptance Criteria

1. THE Registry SHALL be packaged as a Docker image that starts the FastAPI application via Uvicorn with a number of worker processes configurable via `UVICORN_WORKERS` (integer 1–64, defaulting to 1), accepting all application configuration exclusively through environment variables: `DATABASE_URL`, `OBJECT_STORAGE_URL`, `OBJECT_STORAGE_BUCKET`, `JWT_SECRET`, `SEARCH_INDEX_URL`, `ALLOWED_ORIGINS`, `CACHE_URL`, `LOG_LEVEL`.
2. THE Registry SHALL provide a `docker-compose.yml` that orchestrates the Registry, PostgreSQL, MinIO, and MeiliSearch services for local production-equivalent testing.
3. WHEN `ALLOWED_ORIGINS` is set, THE Registry SHALL restrict CORS to the comma-separated list of origin values it contains; WHEN `ALLOWED_ORIGINS` is unset and `ENVIRONMENT` is not `development`, THE Registry SHALL reject all cross-origin requests; WHEN `ALLOWED_ORIGINS` is unset and `ENVIRONMENT` is `development`, THE Registry SHALL allow all cross-origin requests.
4. WHEN `GET /api/v1/health` is requested with no other requests concurrently in flight, THE Registry SHALL respond with HTTP 200 within 200 ms.
5. IF `JWT_SECRET` is absent or empty at startup, THEN THE Registry SHALL emit a structured log error at FATAL level and exit with a non-zero status code.
6. IF `UVICORN_WORKERS` is set to a value outside the range 1–64 at startup, THEN THE Registry SHALL emit a structured log error at FATAL level and exit with a non-zero status code.
7. THE Registry SHALL support horizontal scaling by maintaining no in-process session state; all session and rate-limit state SHALL be persisted in the store configured via the `CACHE_URL` environment variable.

---

### Requirement 16: Artefact URI Parser — Round-Trip Correctness

**User Story:** As a developer, I want the neurohub_URI parser to reliably parse and reconstruct URIs, so that URI handling is consistent across the CLI, backend, and frontend without silent data corruption.

#### Acceptance Criteria

1. THE Registry SHALL expose a URI parser utility that decomposes a neurohub_URI string into its component fields: `scheme`, `type`, `owner` (supporting both `{username}` and `{org}/{username}` forms), `slug`, and `version` (null/None when no `@version` segment is present).
2. FOR ANY conformant neurohub_URI string, parsing the URI then reconstructing it from its component fields SHALL produce a byte-for-byte identical string to the original input with no normalisation applied (round-trip property).
3. FOR ANY conformant neurohub_URI string, parsing the URI twice SHALL produce component fields identical to parsing it once (idempotence property).
4. IF a URI string does not begin with `neurohub://`, THEN THE Registry SHALL raise a `URIParseError` whose message identifies the actual received scheme prefix.
5. IF a URI string contains a `@version` segment that does not conform to MAJOR.MINOR.PATCH semver format, THEN THE Registry SHALL raise a `URIParseError` whose message identifies the invalid version value; a missing `@version` segment SHALL NOT raise a `URIParseError`.
6. WHEN the neurohub_CLI and the Registry backend parse the same neurohub_URI string, BOTH SHALL produce identical component field values and raise identical error types for invalid inputs (behavioural equivalence).
7. IF a URI string has a structurally invalid segment count or is missing required fields (type or slug), THEN THE Registry SHALL raise a `URIParseError` identifying the missing or malformed field.
