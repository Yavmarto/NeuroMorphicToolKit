# Implementation Plan: Neurohub Global Registry

## Overview

Three tightly-coupled workstreams implemented in order of dependency:
**Workstream 1** (Registry Backend) lays the foundation; **Workstream 3** (neurohub-CLI)
can be built in parallel once contracts are stable; **Workstream 2** (Community Portal)
depends on both a running backend and the CLI pull workflow.

Each task builds on the previous and ends by wiring completed pieces together.
Property-based tests (Hypothesis / pytest) validate correctness properties from the design.
Optional test sub-tasks are marked `*` and may be skipped for a faster MVP pass.

---

## Tasks

### Workstream 1 — Registry Backend (FastAPI)

- [ ] 1. Bootstrap project structure and Pydantic v2 contracts
  - [ ] 1.1 Create `neurohub/contracts/registry_contracts.py` with all contract classes
    - Define `ArtefactType` enum (7 canonical type keys)
    - Define `ModelCard`, `NeuroBenchScore`, `ArtefactCreate`, `ArtefactUpdate`, `ArtefactResponse`, `ArtefactListItem` models
    - Define `RatingCreate`, `CommentCreate`, `SearchResponse`, `FollowCreate` models
    - Add `registryRefs` field to `ProjectLinks` in `neurohub/contracts/project_contracts.py`
    - _Requirements: 1.1, 1.7, 2.1, 4.1, 5.1, 6.3, 6.1_

  - [ ]* 1.2 Write property test for invalid artefact type rejection (Property 30)
    - **Property 30: Invalid artefact type rejection**
    - Use `hypothesis` strategies to generate arbitrary strings not in the 7 canonical keys
    - Assert `ArtefactCreate` raises `ValidationError` with field identified as `type`
    - **Validates: Requirements 1.7**

  - [ ]* 1.3 Write property test for identifier format validation (Property 6)
    - **Property 6: Identifier format validation**
    - Generate owner/slug violating 1–64 chars / lowercase-alnum-hyphen rule and invalid semver versions
    - Assert HTTP 422 with offending field named in error detail
    - **Validates: Requirements 2.1, 2.6**

- [ ] 2. Implement URI parser
  - [ ] 2.1 Create `neurohub/app/utils/uri_parser.py`
    - Implement `NeurohubURI` frozen dataclass with `scheme`, `type`, `owner`, `slug`, `version` fields
    - Implement `URIParseError(ValueError)` class
    - Implement `parse_uri(uri: str) -> NeurohubURI` raising `URIParseError` for wrong scheme, invalid segment count, missing type/slug, invalid semver in `@version`
    - Implement `build_uri(parsed: NeurohubURI) -> str` reconstructing the original URI
    - _Requirements: 16.1, 16.2, 16.3, 16.4, 16.5, 16.7_

  - [ ]* 2.2 Write property test: URI round-trip (Property 9)
    - **Property 9: URI round-trip**
    - Generate valid `neurohub://` URI strings with `hypothesis`; assert `build_uri(parse_uri(s)) == s`
    - **Validates: Requirements 2.7, 16.2**

  - [ ]* 2.3 Write property test: URI parse idempotence (Property 10)
    - **Property 10: URI parse idempotence**
    - Assert `parse_uri(build_uri(parse_uri(s)))` fields equal `parse_uri(s)` fields
    - **Validates: Requirements 16.3**

  - [ ]* 2.4 Write property test: URI parse error — wrong scheme (Property 11)
    - **Property 11: URI parse error — wrong scheme**
    - Generate strings with scheme prefix other than `neurohub://`; assert `URIParseError` message contains the actual received prefix
    - **Validates: Requirements 16.4**

  - [ ]* 2.5 Write property test: URI parse error — invalid semver in @version (Property 12)
    - **Property 12: URI parse error — invalid semver in @version**
    - Generate structurally valid URIs with non-semver `@version`; assert `URIParseError` names the invalid value
    - A URI with no `@version` segment must NOT raise
    - **Validates: Requirements 16.5**

  - [ ]* 2.6 Write property test: URI parse error — missing required fields (Property 13)
    - **Property 13: URI parse error — missing required fields**
    - Generate `neurohub://`-prefixed strings with missing type or slug; assert `URIParseError` identifies the missing field
    - **Validates: Requirements 16.7**


- [ ] 3. Add SQLAlchemy models and Alembic migration
  - [ ] 3.1 Add new ORM models to `neurohub/db/models.py`
    - Add `ArtefactDB`, `RatingDB`, `CommentDB`, `FollowDB`, `RegistryActivityEntryDB` classes
    - Enforce unique constraints: `(owner, slug, version)` on `ArtefactDB`; `(artefact_id, user_id)` on `RatingDB`; `(follower_id, followed_user_id)` on `FollowDB`
    - Add check constraint `follower_id != followed_user_id` on `FollowDB`
    - _Requirements: 6.1, 6.3, 6.6, 10.1_

  - [ ] 3.2 Create Alembic migration file in `neurohub/db/migrations/`
    - Generate a single migration file that creates all five new tables with indexes
    - Implement both `upgrade()` and `downgrade()` with full reversibility
    - _Requirements: 10.1, 10.2, 10.4_

  - [ ]* 3.3 Write property test: Alembic migration reversibility (Property 29)
    - **Property 29: Alembic migration reversibility**
    - Apply `upgrade()` then `downgrade()` on an in-memory SQLite database; assert schema state matches pre-upgrade state
    - **Validates: Requirements 10.4**

- [ ] 4. Implement ObjectStorageService
  - [ ] 4.1 Create `neurohub/app/services/object_storage.py`
    - Wrap `aioboto3`/`boto3` for S3-compatible backend (MinIO dev / AWS S3 cloud)
    - Implement `upload_blob(stream, key, size) -> (storage_key, sha256)` with SHA-256 computation
    - Implement `generate_presigned_url(key) -> str` (max 1-hour validity) with pre-download checksum verification
    - Implement multipart upload for blobs ≥ 100 MB with per-part checksums and atomic assembly
    - Enforce 5 GB size guard; raise `BlobTooLargeError` (→ HTTP 413)
    - Raise `StorageUnavailableError` (→ HTTP 503) on unreachable endpoint
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7_

  - [ ]* 4.2 Write property test: blob checksum integrity round-trip (Property 4)
    - **Property 4: Blob checksum integrity round-trip**
    - Generate arbitrary byte payloads; assert stored SHA-256 equals `hashlib.sha256(payload).hexdigest()` and download endpoint serves URL only when values match
    - **Validates: Requirements 1.8, 9.2, 9.3**

  - [ ]* 4.3 Write property test: object storage key pattern (Property 24)
    - **Property 24: Object storage key pattern**
    - Generate valid `(type, owner, slug, version, filename)` tuples; assert constructed key matches `{type}/{owner}/{slug}/{version}/{filename}` and contains no `..` sequences
    - **Validates: Requirements 9.1**


- [ ] 5. Implement SearchIndexService
  - [ ] 5.1 Create `neurohub/app/services/search_index.py`
    - Wrap MeiliSearch Python client; configure index with fields: `name`, `description`, `tags`, `readme`, `owner`, `type`
    - Implement `index_artefact(artefact)` as fire-and-forget background task with ≤5 s commitment and 30 s retry on failure
    - Implement `search(q, filters, page, page_size) -> SearchResponse` with fallback to SQLAlchemy `ILIKE` on `name`+`description` when MeiliSearch unreachable
    - Set `search_degraded=True` in `SearchResponse` when fallback is active
    - _Requirements: 4.4, 4.7, 4.9_

  - [ ]* 5.2 Write property test: search filter consistency (Property 15)
    - **Property 15: Search filter consistency**
    - Generate artefact sets and filter combinations; assert every returned item satisfies all specified filters (case-insensitive exact match for type/owner; OR semantics for tags)
    - **Validates: Requirements 4.2, 4.8**

  - [ ]* 5.3 Write property test: search pagination invariant (Property 16)
    - **Property 16: Search pagination invariant**
    - For queries returning N total items across K pages, assert sum of items == N, last page has `next_cursor: null`, no artefact_id appears twice
    - **Validates: Requirements 4.2**

- [ ] 6. Implement RegistryAuthService and rate limiter extension
  - [ ] 6.1 Create `neurohub/app/services/registry_auth_service.py`
    - Implement `register_user`, `login_user` (returns signed JWT), `verify_token`, `refresh_token` using `python-jose`
    - Hash passwords with bcrypt (passlib); never store plaintext
    - Read `JWT_EXPIRY_HOURS` from env (default 24 h); store refresh tokens in Redis-compatible `CACHE_URL` store
    - _Requirements: 7.1, 7.2, 7.3, 7.8_

  - [ ]* 6.2 Write property test: JWT claims completeness (Property 22)
    - **Property 22: JWT claims completeness**
    - For any login, decode issued JWT and assert `user_id`, `username`, `roles`, `exp` all present; `exp` == issue_time + JWT_EXPIRY_HOURS seconds (±5 s tolerance)
    - **Validates: Requirements 7.1**

  - [ ]* 6.3 Write property test: password storage safety (Property 23)
    - **Property 23: Password storage safety**
    - Generate arbitrary password strings; register user; assert stored hash != plaintext and `bcrypt.checkpw(plaintext, hash)` returns True
    - **Validates: Requirements 7.3**

  - [ ] 6.4 Extend rate limiter in `neurohub/app/limiter.py`
    - Add per-endpoint keys: 60/60 s per IP for unauthenticated `/api/v1/*`; 300/60 s per `user_id` for authenticated; 10/60 s per IP for `POST /api/v1/auth/login`
    - On Redis counter persist failure: treat as zero (allow), log at WARN
    - Add middleware to inject `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` on every rate-enforced response
    - Return HTTP 429 with `Retry-After` header on limit exceeded
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_


- [ ] 7. Implement ActivityFeedService
  - [ ] 7.1 Create `neurohub/app/services/activity_feed.py`
    - Implement `record_follow(follower_id, followed_user_id)` and `record_new_artefact(follower_id, followed_user_id, artefact_id)` as background tasks
    - Write `RegistryActivityEntryDB` entries within 10 s of triggering event
    - _Requirements: 6.6_

- [ ] 8. Implement registry routers
  - [ ] 8.1 Create `neurohub/app/routers/registry_artefacts.py`
    - `POST /api/v1/artefacts` — validate payload, upload blob via `ObjectStorageService`, insert `ArtefactDB` record, fire `SearchIndexService.index_artefact` as background task; return 201 with `ArtefactResponse` including `neurohub_URI`
    - `GET /api/v1/artefacts/{owner}/{slug}/{version}` — retrieve active record; generate pre-signed URL (verify checksum first); return 200 or 404
    - `GET /api/v1/artefacts/{owner}/{slug}` — resolve to latest non-prerelease version; return 404 if none exists
    - `PUT /api/v1/artefacts/{owner}/{slug}/{version}` — update mutable fields only; enforce ownership (403); return 200
    - `DELETE /api/v1/artefacts/{owner}/{slug}/{version}` — soft-delete (set `deleted_at`); schedule blob removal; enforce ownership; return 204
    - `GET /api/v1/artefacts/{owner}/{slug}/versions` — return all versions in descending semver order
    - Apply `Depends(get_current_user)` to all mutating endpoints; apply rate-limit decorators
    - _Requirements: 1.1–1.9, 2.2–2.5_

  - [ ]* 8.2 Write property test: artefact creation round-trip (Property 1)
    - **Property 1: Artefact creation round-trip**
    - Generate valid artefact payloads; POST then GET by same identifier; assert all submitted metadata fields are identical in response
    - **Validates: Requirements 1.1, 1.2**

  - [ ]* 8.3 Write property test: immutable field preservation under update (Property 2)
    - **Property 2: Immutable field preservation under update**
    - Create artefact; record immutable fields; issue PUT with mutable field changes; assert `type`, `owner`, `slug`, `version`, `sha256`, `created_at` unchanged
    - **Validates: Requirements 1.3**

  - [ ]* 8.4 Write property test: soft-delete visibility invariant (Property 3)
    - **Property 3: Soft-delete visibility invariant**
    - Create artefact; DELETE it; assert subsequent GET returns 404 and artefact absent from all search result pages
    - **Validates: Requirements 1.4, 1.6**

  - [ ]* 8.5 Write property test: latest-version resolution (Property 7)
    - **Property 7: Latest-version resolution**
    - Register multiple semver versions under same `{owner}/{slug}`; assert version-less GET resolves to semantic maximum of non-prerelease versions
    - **Validates: Requirements 2.2**

  - [ ]* 8.6 Write property test: version list descending order (Property 8)
    - **Property 8: Version list descending order**
    - Register N versions; assert `GET /versions` returns all N in strictly descending semver order (`versions[i] > versions[i+1]` for all i)
    - **Validates: Requirements 2.4**


  - [ ] 8.7 Create `neurohub/app/routers/registry_search.py`
    - `GET /api/v1/search` — accept `q`, `type`, `hardware_target`, `neuron_model`, `tags`, `owner`, `page`, `page_size`; validate params (HTTP 422 on out-of-range); delegate to `SearchIndexService`; return `SearchResponse`
    - _Requirements: 4.1, 4.2, 4.3, 4.5, 4.7, 4.8_

  - [ ] 8.8 Create `neurohub/app/routers/registry_auth.py`
    - `POST /api/v1/auth/register` — create user; hash password; return 201 or 409 on duplicate username/email
    - `POST /api/v1/auth/login` — validate credentials; issue JWT; return 200 (rate-limited 10/60 s per IP)
    - `POST /api/v1/auth/refresh` — accept refresh token; issue new JWT; return 401 on invalid/expired token
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.7, 7.8_

  - [ ] 8.9 Create `neurohub/app/routers/registry_community.py`
    - `POST /api/v1/artefacts/{owner}/{slug}/ratings` — record or replace rating (1–5); recompute `average_rating` and `rating_count`; return updated aggregates
    - `POST /api/v1/artefacts/{owner}/{slug}/comments` — persist comment (1–4000 chars); return 201 or 422
    - `GET /api/v1/artefacts/{owner}/{slug}/comments` — paginated comments in descending `created_at` order
    - `DELETE /api/v1/artefacts/{owner}/{slug}/comments/{comment_id}` — owner or admin only; return 204
    - `POST /api/v1/users/{username}/follow` — record follow; dispatch `ActivityFeedService`; return 201 or 400 (self-follow) or 409 (duplicate)
    - `DELETE /api/v1/users/{username}/follow` — remove follow relationship
    - _Requirements: 6.1–6.10_

  - [ ]* 8.10 Write property test: rating aggregate invariant (Property 20)
    - **Property 20: Rating aggregate invariant**
    - Submit sequences of ratings from distinct users including re-submissions; assert `average_rating == round(sum(latest_per_user) / distinct_raters, 2)` and `rating_count == distinct_raters`
    - **Validates: Requirements 6.1, 6.2**

  - [ ]* 8.11 Write property test: comment content round-trip (Property 17)
    - **Property 17: Comment content round-trip**
    - Generate non-empty Unicode strings of length 1–4000; POST comment; GET comments; assert `content` field byte-for-byte identical
    - **Validates: Requirements 6.3**

  - [ ]* 8.12 Write property test: comment length boundary enforcement (Property 18)
    - **Property 18: Comment length boundary enforcement**
    - Generate strings of length 0 and > 4000; assert HTTP 422 and no record persisted; strings 1–4000 must succeed
    - **Validates: Requirements 6.4**

  - [ ]* 8.13 Write property test: comments returned in descending order (Property 19)
    - **Property 19: Comments returned in descending order**
    - Post N comments; assert `GET /comments` returns them with `created_at[i] >= created_at[i+1]` for all i
    - **Validates: Requirements 6.5**

  - [ ] 8.14 Create `neurohub/app/routers/registry_health.py`
    - `GET /api/v1/health` — probe DB connectivity and Object_Storage connectivity; return `{"status": "ok"|"degraded", "db": "connected"|"disconnected", "storage": "connected"|"disconnected", "version": "<semver>"}` within 200 ms
    - _Requirements: 14.4, 15.4_


- [ ] 9. Implement auth middleware, ownership guard, and startup sequence
  - [ ] 9.1 Create/extend `neurohub/app/auth.py` JWT middleware
    - Implement `get_current_user` dependency that validates Bearer token, checks `exp`, verifies signature and required claims; returns `HTTP 401` with `WWW-Authenticate: Bearer` on any failure
    - _Requirements: 7.5, 7.6, 7.7_

  - [ ]* 9.2 Write property test: authentication enforcement on mutating endpoints (Property 21)
    - **Property 21: Authentication enforcement on mutating endpoints**
    - For every mutating endpoint, send requests with: no token, expired JWT, missing claim, invalid signature; assert HTTP 401 + `WWW-Authenticate: Bearer` header returned and mutation not executed
    - **Validates: Requirements 7.5, 7.7**

  - [ ]* 9.3 Write property test: non-owner modification forbidden (Property 5)
    - **Property 5: Non-owner modification forbidden**
    - Create artefact as user A; attempt PUT and DELETE as user B (non-admin); assert HTTP 403 and record unchanged
    - **Validates: Requirements 1.9, 6.10, 7.6**

  - [ ] 9.4 Implement startup fast-fail sequence in `neurohub/main.py`
    - Guard order: validate `JWT_SECRET` → validate `UVICORN_WORKERS` range (1–64) → DB connectivity → Alembic pending migrations → begin accepting requests
    - Emit structured FATAL/ERROR log and exit non-zero on each failure
    - Register all five new routers under `/api/v1` prefix
    - _Requirements: 10.2, 10.5, 10.6, 15.1, 15.5, 15.6_

- [ ] 10. Implement structured logging and request-ID propagation
  - [ ] 10.1 Add structured JSON logging middleware to `neurohub/main.py`
    - Emit log entry per request: `timestamp`, `method`, `path`, `status_code`, `duration_ms`, `request_id`, `user_id` (omit when unauthenticated — do not set to null)
    - Log unhandled exceptions at ERROR level with traceback + `request_id`; return HTTP 500 with no stack trace in body
    - Log artefact create/update/delete/download events at INFO level with `artefact_id`, `owner`, `type`, `action`, `request_id`
    - _Requirements: 14.1, 14.2, 14.3_

  - [ ] 10.2 Implement `X-Request-ID` propagation
    - Middleware reads `X-Request-ID` header; generates UUID v4 (≤128 chars) if absent; propagates to all `suite_client.py` outbound calls; echoes in response headers
    - _Requirements: 14.5_

  - [ ]* 10.3 Write property test: structured log entry completeness (Property 27)
    - **Property 27: Structured log entry completeness**
    - For arbitrary HTTP requests, capture emitted JSON log; assert `timestamp`, `method`, `path`, `status_code`, `duration_ms`, `request_id` present; `user_id` present iff authenticated
    - **Validates: Requirements 14.1**

  - [ ]* 10.4 Write property test: request ID propagation (Property 28)
    - **Property 28: Request ID propagation**
    - Send requests with and without `X-Request-ID`; assert provided value echoed unchanged in response; absent → generated UUID v4 in response and all outbound calls
    - **Validates: Requirements 14.5**


- [ ] 11. Implement CORS policy and Docker/docker-compose deployment
  - [ ] 11.1 Add CORS middleware to `neurohub/main.py`
    - Read `ALLOWED_ORIGINS` and `ENVIRONMENT` env vars; restrict to comma-separated list when set; allow all when `ENVIRONMENT=development` and unset; reject all cross-origin when unset and not development
    - _Requirements: 15.3_

  - [ ] 11.2 Write `Neurohub/Dockerfile` (or extend existing)
    - Multi-stage build; start FastAPI via Uvicorn; read `UVICORN_WORKERS` (default 1, max 64)
    - Accept all config via environment variables: `DATABASE_URL`, `OBJECT_STORAGE_URL`, `OBJECT_STORAGE_BUCKET`, `JWT_SECRET`, `SEARCH_INDEX_URL`, `ALLOWED_ORIGINS`, `CACHE_URL`, `LOG_LEVEL`
    - _Requirements: 15.1_

  - [ ] 11.3 Write `Neurohub/docker-compose.yml`
    - Services: registry backend, PostgreSQL, MinIO, MeiliSearch, Redis
    - Wire all environment variables; expose registry on port 8005 consistent with `modules.json`
    - Add Next.js frontend-nextjs as a separate service
    - _Requirements: 15.2_

- [ ] 12. Backend checkpoint
  - Ensure all backend tests pass: `PYTHONPATH=. pytest neurohub/tests/ -v`
  - Run `ruff check neurohub/` and `mypy neurohub/` with zero errors
  - Ask the user if questions arise before proceeding.

---

### Workstream 3 — neurohub-CLI (neurocli)

- [ ] 13. Bootstrap neurohub-CLI package structure
  - [ ] 13.1 Create `neurocli/neurohub_cli/` package with `__init__.py`, `__main__.py`, and `pyproject.toml`
    - Set up package entry point: `python -m neurohub_cli` and `neurohub` console script
    - Add dependencies: `typer`, `httpx`, `keyring`, `python-jose`, `hypothesis` (dev)
    - _Requirements: 13.1_

  - [ ] 13.2 Copy/import `uri_parser.py` into `neurocli/neurohub_cli/uri_parser.py`
    - Must expose identical `parse_uri` / `build_uri` / `NeurohubURI` / `URIParseError` interface as backend module
    - _Requirements: 16.6, 3.1_

  - [ ]* 13.3 Write property test: CLI–backend URI parse equivalence (Property 14)
    - **Property 14: CLI–backend URI parse equivalence**
    - For any `neurohub://` URI string, assert CLI `uri_parser` and backend `uri_parser` produce identical field values; for invalid inputs, both raise equivalent error type
    - Place in `neurocli/tests/properties/test_uri_properties.py`
    - **Validates: Requirements 16.6**

  - [ ]* 13.4 Write CLI URI property tests (Properties 9–13 parity)
    - Re-run Properties 9, 10, 11, 12, 13 against CLI `uri_parser` in `neurocli/tests/properties/test_uri_properties.py`
    - Ensures behavioural equivalence is maintained independently of backend
    - **Validates: Requirements 16.2, 16.3, 16.4, 16.5, 16.7**


- [ ] 14. Implement credentials store and HTTP client
  - [ ] 14.1 Create `neurocli/neurohub_cli/credentials.py`
    - Use `keyring` to store and retrieve `registry_url` and `jwt_token` per registry URL
    - Fall back to `~/.config/neurohub/credentials.json` when keyring unavailable
    - _Requirements: 3.5, 13.4_

  - [ ] 14.2 Create `neurocli/neurohub_cli/http_client.py`
    - Thin `httpx` wrapper that reads base URL and JWT from credentials store
    - Reads Registry module endpoint from `nmtk/neuro_toolkit/assets/modules.json` — no separate catalog
    - _Requirements: 13.7_

- [ ] 15. Implement CLI commands
  - [ ] 15.1 Implement `neurocli/neurohub_cli/commands/login.py`
    - `neurohub login --registry <url>`: prompt username + password; POST to `/api/v1/auth/login`; persist JWT + URL via `credentials.py`
    - _Requirements: 13.4, 3.5_

  - [ ] 15.2 Implement `neurocli/neurohub_cli/commands/push.py`
    - `neurohub push <file> --type <type> --slug <slug> --version <version> [--description] [--tag]...`
    - Validate type (exit 1 on invalid), slug format, description ≤1000 chars, ≤20 tags
    - Upload file blob; register metadata; print canonical `neurohub://` URI to stdout on success (exit 0)
    - HTTP 409/422/401/403 → print Registry error to stderr, exit 1
    - Network / HTTP 5xx → print error to stderr, exit 2
    - _Requirements: 13.1, 13.5, 3.3_

  - [ ] 15.3 Implement `neurocli/neurohub_cli/commands/pull.py`
    - `neurohub pull <neurohub_URI> [--output <path>]`
    - Resolve URI; download blob; verify SHA-256 checksum; on mismatch delete file, print to stderr, exit non-zero
    - Default output filename: `{slug}@{version}.{ext}` from artefact type canonical extension
    - Artefact not found → print to stderr, exit 1
    - _Requirements: 13.2, 13.6, 3.2, 3.4_

  - [ ] 15.4 Implement `neurocli/neurohub_cli/commands/search.py`
    - `neurohub search <query> [--type] [--hardware] [--limit]`: GET `/api/v1/search`; print formatted table (columns: name, type, owner, version, rating); limit default 20, max 100
    - _Requirements: 13.3_

  - [ ] 15.5 Wire all commands into `__main__.py` entry point via `typer` app
    - Register `login`, `push`, `pull`, `search` sub-commands
    - Ensure exit code semantics: 0 = success, 1 = user error, 2 = infrastructure error
    - _Requirements: 13.8_

- [ ] 16. CLI checkpoint
  - Ensure all CLI tests pass: `PYTHONPATH=. pytest neurocli/tests/ -v`
  - Ask the user if questions arise before proceeding.


---

### Workstream 2 — Community Portal

#### 2a. Flutter In-App Panel

- [ ] 17. Implement Flutter widgets
  - [ ] 17.1 Create `frontend/lib/widgets/artefact_card.dart`
    - Display: name, type badge, owner, version, average rating, download count
    - Use `NmtkShellTokens` colour palette for status indicators
    - _Requirements: 11.1, 11.4_

  - [ ] 17.2 Create `frontend/lib/widgets/type_badge.dart`
    - Render distinct badge for each of the 7 canonical type keys
    - Render neutral "unknown" badge for unrecognised type values
    - _Requirements: 11.7_

  - [ ] 17.3 Create `frontend/lib/widgets/model_card_view.dart`
    - Render all `ModelCard` defined fields
    - Display `neurobench_scores` as a sortable `DataTable` with columns: benchmark name, metric, value, hardware_target
    - Entries missing `metric` or `value` → warning indicator + greyed-out value cells
    - Always render "Ethical Considerations" section heading when field is present
    - _Requirements: 5.3, 5.4_

  - [ ] 17.4 Create `frontend/lib/widgets/search_degraded_banner.dart`
    - Non-blocking informational banner shown when API response contains `"search_degraded": true`
    - _Requirements: 11.8_

  - [ ] 17.5 Create `frontend/lib/widgets/import_progress_indicator.dart`
    - Wraps CLI pull operation; shows progress indicator
    - Cancel and show timeout error after 120 s; provide dismissal action
    - On success: add neurohub_URI to active project's `ProjectLinks.registryRefs`
    - On failure: display CLI error and dismissal action
    - _Requirements: 11.5, 11.6_

- [ ] 18. Implement Flutter screens
  - [ ] 18.1 Create `frontend/lib/screens/registry_discovery_screen.dart`
    - Paginated card grid (default page_size 20) using `ArtefactCard` and `TypeBadge`
    - Search bar with 300 ms debounce before issuing search request
    - Type filter dropdown
    - Responsive layout: two-column grid at ≥1440 px, single-column at <768 px
    - `NeurohubShellSection.registry` activates this screen; pass `mode: NmtkShellMode.command`
    - _Requirements: 11.1, 11.3, 11.4, 4.6_

  - [ ] 18.2 Create `frontend/lib/screens/artefact_detail_screen.dart`
    - Full detail view with `ModelCardView`, comments section, rating widget
    - Two distinct controls: "Download" (save blob to filesystem) and "Import to Project" (triggers `ImportProgressIndicator`)
    - _Requirements: 11.2, 11.5_

  - [ ] 18.3 Create `frontend/lib/screens/share_to_neurohub_sheet.dart` (bottom sheet / dialog)
    - Prompt for slug, version, optional description before submission
    - Show progress indicator and disable "Share to Neurohub" action while submission in progress
    - On success: display canonical neurohub_URI with "Copy URI" action in persistent panel
    - On failure: non-blocking error toast with failure reason and "Retry" action
    - 30 s timeout → treat as failure, apply error toast
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6_


  - [ ] 18.4 Wire `suite_client.py` share-to-neurohub integration
    - Add `share_artefact(slug, version, type, description, file_path) -> str` method to `neurohub/app/services/suite_client.py`
    - Construct neurohub_URI from user-supplied metadata; invoke CLI push workflow; return published URI to NMTK UI on success; return error response without retry on failure
    - _Requirements: 3.6, 3.7, 12.7_

- [ ] 19. Flutter frontend checkpoint
  - Run `cd frontend && flutter test` with zero failures
  - Ask the user if questions arise before proceeding.

#### 2b. Next.js Public-Facing Site

- [ ] 20. Bootstrap Next.js site
  - [ ] 20.1 Create `Neurohub/frontend-nextjs/` Next.js 14 (App Router) project
    - Install dependencies: `next`, `react`, `react-dom`, `vitest`, `@testing-library/react`
    - Configure `next.config.js` to proxy `/api/v1/*` to the Registry backend
    - _Requirements: 15.2_

- [ ] 21. Implement Next.js pages and components
  - [ ] 21.1 Implement `/` landing page with search hero (`Neurohub/frontend-nextjs/app/page.tsx`)
    - Search input with 300 ms debounce; routes to `/artefacts?q=<query>` on submit
    - _Requirements: 4.6_

  - [ ] 21.2 Implement `/artefacts` discovery page (`app/artefacts/page.tsx`)
    - SSR-rendered paginated feed; client-side search with 300 ms debounce
    - Artefact card grid with type badges; show `SearchDegradedBanner` when `search_degraded: true`
    - _Requirements: 4.1, 4.6, 11.8_

  - [ ] 21.3 Implement `/artefacts/[type]/[owner]/[slug]` detail page
    - Render full artefact detail; model card with neurobench scores table; "Ethical Considerations" section
    - _Requirements: 5.3, 5.4_

  - [ ] 21.4 Implement `/artefacts/[type]/[owner]/[slug]/versions` version history page
    - Fetch and display version list from `GET /api/v1/artefacts/{owner}/{slug}/versions`
    - _Requirements: 2.4_

  - [ ] 21.5 Implement `/u/[username]` publisher profile page
    - Display user's published artefacts as paginated list
    - _Requirements: 4.8_

  - [ ]* 21.6 Write Vitest unit tests for Next.js components
    - Cover: search debounce (300 ms), artefact card data projection, model card rendering, empty result state
    - Place in `__tests__/` alongside each component
    - Run with `cd Neurohub/frontend-nextjs && npx vitest --run`
    - _Requirements: 4.6, 5.3, 4.5_

- [ ] 22. Next.js checkpoint
  - Run `cd Neurohub/frontend-nextjs && npx vitest --run` with zero failures
  - Ask the user if questions arise before proceeding.


---

### Cross-Workstream Integration and Smoke Tests

- [ ] 23. Write backend unit and integration test files
  - [ ] 23.1 Create `neurohub/tests/test_registry_artefacts.py`
    - CRUD happy-path: create → retrieve → update → delete
    - Error cases: 409 duplicate, 404 not found, 403 non-owner, 422 invalid type
    - _Requirements: 1.1–1.9_

  - [ ] 23.2 Create `neurohub/tests/test_registry_versioning.py`
    - Semver resolution, version listing in descending order, 404 on no stable version
    - _Requirements: 2.2–2.5_

  - [ ] 23.3 Create `neurohub/tests/test_registry_search.py`
    - Search + filter + degraded fallback; pagination; empty results; 422 on invalid params
    - _Requirements: 4.1–4.9_

  - [ ] 23.4 Create `neurohub/tests/test_registry_auth.py`
    - JWT issue/verify/refresh; bcrypt storage; duplicate registration 409; expired token 401
    - _Requirements: 7.1–7.8_

  - [ ] 23.5 Create `neurohub/tests/test_registry_community.py`
    - Ratings aggregation, comment CRUD, follow/unfollow, self-follow 400, duplicate follow 409
    - _Requirements: 6.1–6.10_

  - [ ] 23.6 Create `neurohub/tests/test_registry_rate_limiting.py`
    - Limit counters, 429 + headers, Redis counter failure → allow + WARN log
    - _Requirements: 8.1–8.6_

  - [ ] 23.7 Create `neurohub/tests/test_registry_object_storage.py`
    - Upload, checksum verification, presigned URL, 5 GB guard (413), Storage unavailable (503)
    - _Requirements: 9.1–9.7_

  - [ ] 23.8 Create `neurohub/tests/test_registry_model_cards.py`
    - Model card validation, unknown field stripping with `warnings` array, round-trip storage
    - _Requirements: 5.1–5.5_

  - [ ] 23.9 Create `neurohub/tests/test_registry_health.py`
    - Health endpoint format; degraded status when DB or storage disconnected; response ≤200 ms
    - _Requirements: 14.4, 15.4_

  - [ ] 23.10 Create `neurohub/tests/test_registry_migrations.py`
    - Upgrade/downgrade cycle on in-memory SQLite; assert schema restoration
    - _Requirements: 10.1–10.6_

  - [ ]* 23.11 Write all 30 backend property-based tests in `neurohub/tests/properties/test_registry_properties.py`
    - One test function per property (Properties 1–30 as listed in the design document)
    - Each tagged with `# Feature: neurohub-global-registry, Property <N>: <text>`
    - Minimum 100 examples per test (`@settings(max_examples=100)`)
    - Properties 9–14 use pure-function tests against `uri_parser.py` (no I/O)
    - Properties 4, 5, 21, 22, 23 use `httpx.AsyncClient` with mocked storage and search
    - **Validates: Requirements 1.1–16.7 (all 30 properties)**


- [ ] 24. Write Flutter widget and screen tests
  - [ ]* 24.1 Create `test/screens/registry_discovery_screen_test.dart`
    - Card grid rendering; type badges; search debounce; responsive layout breakpoints
    - _Requirements: 11.1, 11.3, 11.7_

  - [ ]* 24.2 Create `test/screens/artefact_detail_screen_test.dart`
    - Model card rendering; neurobench scores table; comments list; rating widget
    - _Requirements: 5.3, 5.4, 11.2_

  - [ ]* 24.3 Create `test/widgets/search_degraded_banner_test.dart`
    - Banner shown iff `search_degraded: true`; absent when false
    - _Requirements: 11.8_

  - [ ]* 24.4 Create `test/widgets/import_progress_indicator_test.dart`
    - 120 s timeout triggers cancellation and error display; success adds to `registryRefs`
    - _Requirements: 11.5, 11.6_

  - [ ]* 24.5 Create `test/screens/registry_responsive_test.dart`
    - Two-column grid at ≥1440 px viewport; single-column at <768 px viewport
    - _Requirements: 11.3_

- [ ] 25. Final integration checkpoint
  - Run full test suite: `PYTHONPATH=. pytest neurohub/tests/ -v`
  - Run CLI tests: `PYTHONPATH=. pytest neurocli/tests/ -v`
  - Run Flutter tests: `cd frontend && flutter test`
  - Run Next.js tests: `cd Neurohub/frontend-nextjs && npx vitest --run`
  - Run linters: `ruff check neurohub/` and `mypy neurohub/`
  - Verify smoke test against running stack: `python3 scripts/backend_endpoint_smoke.py`
  - Ask the user if questions arise before declaring the workstream complete.

---

## Notes

- Tasks marked `*` are optional and can be skipped for a faster MVP pass; property-based tests are the primary optional surface.
- Each task references specific requirements for full traceability.
- Checkpoints (tasks 12, 16, 19, 22, 25) ensure incremental validation before crossing workstream boundaries.
- All 30 correctness properties from the design are covered: Properties 1–8 (artefact lifecycle), 9–14 (URI parser), 15–16 (search), 17–20 (community), 21–23 (auth), 24 (storage), 25–26 (model cards), 27–28 (observability), 29 (migrations), 30 (type validation).
- Property tests use `hypothesis>=6.0.0` already in dev dependencies; `@settings(max_examples=100)` is the minimum run count.
- The `uri_parser.py` module is the only code shared between backend and CLI — all other modules remain within their ownership boundaries per `AGENTS.md`.
- Object Storage atomicity: if blob upload fails → 503, no `ArtefactDB` record written; if DB insert fails after successful upload → attempt blob deletion (dead-letter log on double failure).


## Task Dependency Graph

```json
{
  "waves": [
    {
      "id": 0,
      "tasks": ["1.1", "2.1", "13.1"]
    },
    {
      "id": 1,
      "tasks": ["1.2", "1.3", "2.2", "2.3", "2.4", "2.5", "2.6", "3.1", "13.2"]
    },
    {
      "id": 2,
      "tasks": ["3.2", "4.1", "6.1", "13.3", "13.4"]
    },
    {
      "id": 3,
      "tasks": ["3.3", "4.2", "4.3", "5.1", "6.2", "6.3", "6.4", "7.1", "14.1", "14.2"]
    },
    {
      "id": 4,
      "tasks": ["5.2", "5.3", "8.1", "8.7", "8.8", "9.1", "15.1", "15.2", "15.3", "15.4"]
    },
    {
      "id": 5,
      "tasks": ["8.2", "8.3", "8.4", "8.5", "8.6", "8.9", "8.14", "9.2", "9.3", "9.4", "15.5"]
    },
    {
      "id": 6,
      "tasks": ["8.10", "8.11", "8.12", "8.13", "10.1", "10.2"]
    },
    {
      "id": 7,
      "tasks": ["10.3", "10.4", "11.1", "11.2", "11.3", "17.1", "17.2", "17.3", "17.4", "17.5", "20.1"]
    },
    {
      "id": 8,
      "tasks": ["18.1", "18.2", "18.3", "18.4", "21.1", "21.2", "21.3", "21.4", "21.5"]
    },
    {
      "id": 9,
      "tasks": ["21.6", "23.1", "23.2", "23.3", "23.4", "23.5", "23.6", "23.7", "23.8", "23.9", "23.10"]
    },
    {
      "id": 10,
      "tasks": ["23.11", "24.1", "24.2", "24.3", "24.4", "24.5"]
    }
  ]
}
```
