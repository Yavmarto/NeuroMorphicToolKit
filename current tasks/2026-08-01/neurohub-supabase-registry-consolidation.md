# Neurohub: consolidate on Supabase-hosted registry backend

## IMPORTANT architecture correction (post-session-1 conversation)

The registry (`/api/v1`) must be **one centralized hub instance**, not something
each end user's self-deployed backend runs a copy of. End users deploy their
own private backend (via the app's SSH deploy flow) for their own
notebook/NeuroSense/NeuroChip work — that has nothing to do with the shared
public hub. Frontend's `ApiService.registryBaseUrl` currently resolves via
`NmtkApiBaseUrl.resolve(...)` (i.e. whatever host the user's Backend Setup
screen points at) — **this is wrong** and must be decoupled into its own fixed
constant pointing at the one centralized hub URL, the same way `SUPABASE_URL`
is already a fixed constant in `main.dart`. Not yet fixed — flagging for the
next session.

Decided (2026-08-01): centralized hub = the Python registry backend
(already built, Phases 0–5) deployed on **Cloud Run's free tier** (managed,
scale-to-zero, no server to patch), talking to **Supabase** for Postgres/
Storage/Auth. Firebase Auth — previously a parallel, never-actually-used
auth mode with its own GCP Cloud SQL + GCS + Memorystore Redis stack in
`infrastructure/cloud-run-service.yaml` — has been **fully removed** this
session: `firebase_auth_service.py` deleted, `registry_security.py`/
`registry_auth.py` simplified to `internal`/`supabase` only, `firebase-admin`
optional dependency removed, `cloud-run-service.yaml` and `cloudbuild.yaml`
rewritten for Supabase (DB/storage) instead of Cloud SQL/GCS, `minScale`
dropped to `0` for true free-tier cost. `firebase_uid` DB column/migration
left in place (harmless nullable leftover, not worth a migration to drop).

No GCP project exists yet — only a Supabase free-tier project. Cloud Run
deployment itself (creating the GCP project, Artifact Registry, Secret
Manager entries, actually running `gcloud run services replace`) is not done
and needs real GCP access someone has to do, not something achievable from
here without credentials. Full step-by-step guide for both sides written to
`gcp-supabase-deployment-guide.md` in this same folder.

Two more bugs found and fixed while writing that guide:
- `Neurohub/Dockerfile` installed the base package only (`pip install .`),
  missing the `[postgres]` extra — `psycopg2` would have been absent at
  runtime, so `NEUROHUB_DB_URL` pointed at Postgres would have failed
  immediately. Fixed to `pip install ".[postgres]"`.
- `ApiService.registryBaseUrl` (the bug flagged at the end of the prior
  session) is now fixed — no longer derived from `NmtkApiBaseUrl.resolve(...)`
  (which resolves to whatever backend a user's own device points at). It's
  now its own fixed `String.fromEnvironment('NEUROHUB_REGISTRY_URL', ...)`
  constant in `api_service.dart`, same pattern as `SUPABASE_URL` in
  `main.dart` — currently a placeholder default
  (`https://REPLACE_WITH_DEPLOYED_NEUROHUB_REGISTRY_URL`) until the Cloud Run
  URL exists, per the deployment guide's Part 3.


Full plan: `/Users/yoshimartodihardjo/.claude/plans/what-does-still-need-hidden-salamander.md`
Detailed engineering rationale: `/Users/yoshimartodihardjo/.claude/plans/what-does-still-need-hidden-salamander-agent-a2fdaa49680bf9821.md`

## Status: Phases 0–5 + safe part of Phase 8 done and verified. Phases 6, 7, 9, 10, 11, and the rest of Phase 8 remain.

### Done (this session)
- **Phase 0**: Confirmed live Supabase project is on JWKS/ES256 signing (not legacy HS256) via direct curl to its `.well-known/jwks.json`.
- **Phase 1**: Added `benchmark_result` to `ArtefactType` (`Neurohub/neurohub/app/utils/uri_parser.py`, mirrored in `neurocli/neurocli/uri_parser.py` — also fixed a pre-existing drift where neurocli's copy was missing `custom_node` entirely, and its `hub.py` extension map).
- **Phase 2**: New `neurohub/app/services/supabase_auth_service.py` (JWKS fetch+cache+rotation, HS256 fallback). `registry_security.py`/`registry_auth.py` generalized to a third `supabase` provider mode alongside `internal`/`firebase`. `UserDB.supabase_uid` column + migration `e4f6a8b90004`. New tests `test_supabase_auth_service.py`, `test_registry_auth.py` (the latter also covers `firebase` mode, previously untested).
- **Phase 3**: `db/database.py` hardened with `pool_pre_ping=True` + opt-in `NEUROHUB_DB_POOL_MODE=nullpool`.
- **Phase 4**: `.env.supabase.example` corrected (was asserting false things about JWT verification) and documented for Storage.
- **Phase 5**: Frontend fully migrated — `api_service.dart` gained a `/api/v1` registry client (search/create/delete artefact, bearer auth via Supabase token); `models/shared_asset.dart` rewritten to match the registry's `ArtefactResponse`/`ArtefactListItem` shape; `share_model_screen.dart`, `asset_library_screen.dart`, `feed_screen.dart`, `my_shares_screen.dart` all repointed to the same registry-backed data source (previously 3 divergent paths); `supabase_service.dart` stripped to identity-only (kept sign-in/up/out, added `accessToken`, `sendPasswordResetEmail`, `updatePassword` for later Phase 10 use). All associated tests updated; new `test/helpers/fake_api_service.dart` added.
- **Phase 8 (partial, safe subset only)**: Deleted `app/routers/auth.py` (confirmed zero real callers — frontend never called it) and its `main.py` wiring; cleaned up `test_auth.py` accordingly. Deleted 3 orphaned frontend test files whose corresponding widgets/screens were already gone (`workflow_step_card_test.dart`, `milestone_timeline_test.dart`, `settings_screen_test.dart`).

### NOT done — Phase 8's bigger half (important finding)
`app/routers/assets.py`, `sharing.py`, `app/services/asset_library.py`, and `SharedAssetDB` were **NOT deleted** despite the plan's assumption they had no other callers. They do:
- `Neurohub/scripts/seed_hub_entries.py` (real seed tooling, see `docs/hub-seed-guide.md`)
- `tests/load/locustfile.py` (repo-root load test)
- `Neurohub/neurohub/tests/test_prod_integration.py`, `test_all_endpoints.py`, `test_smoke.py`

Retiring these properly means migrating the seed script and load test to the `/api/v1` registry API first — a real, separately-scoped piece of work, not a mechanical deletion. Flagging rather than doing it hastily.

### Remaining work (not started)
- **Phase 6**: Custom-node "Publish to Hub" action. Needs: locating the actual Flutter screen that calls `POST /api/neurosim/custom-nodes/save` (in `Neurosim/frontend/` or `neurocnl/frontend/` — not yet found), and deciding shared-Dart-package (`nmtk_module_contracts`) vs. duplication for the registry API client used cross-module.
- **Phase 7**: Benchmark-result "Share to Hub" action. Needs: locating the Neurobench Flutter results screen, a new `GET /api/neurobench/results/{id}/registry-export` endpoint (Python), and the same shared-package decision as Phase 6.
- **Phase 8 remainder**: as above — migrate `seed_hub_entries.py` + `locustfile.py` + the 3 backend test files off the legacy assets/shares surface, then delete `assets.py`/`sharing.py`/`asset_library.py`/`SharedAssetDB` (+ a reversible migration).
- **Phase 9**: Wire the generalized `/sync` endpoint into the Flutter sign-up flow (choose-a-username step) — currently nothing calls `/api/v1/auth/sync` from the frontend yet.
- **Phase 10**: Password-reset UI — `supabase_service.dart` already has `sendPasswordResetEmail`/`updatePassword`; still need `forgot_password_screen.dart`, `reset_password_screen.dart`, deep-link wiring in `shell/neurohub_deep_link.dart`, and `auth_provider.dart` wrapper methods.
- **Phase 11**: Docs cleanup — `neurohub_spec.md`'s stale "Future Vision" section, `CHANGELOG.md` entry, `neurohub_functional_testing_guide.md` if affected.

### Verification run each phase
- Backend: `PYTHONPATH=. pytest neurohub/tests/`, `ruff check neurohub/`, `mypy neurohub/` — all green except 2 confirmed pre-existing failures unrelated to this work (`test_auth.py::test_validate_startup_config_passes_with_valid_key` — missing an env var setup in the test itself; `test_concurrency.py::test_concurrent_dashboard_sessions` — a SQLite/cyextension threading flake).
- Frontend: `cd frontend && flutter analyze && flutter test` — all green except pre-existing failures unrelated to this work, all individually traced to root cause (see below).

### Pre-existing issues found but NOT part of this work (left alone, flagged for awareness)
- `neurohub_shell_adapter_test.dart` (x2): expects literal text `"Share a Model"` which doesn't exist anywhere in `lib/` — stale test predating this session.
- `neurohub_responsive_audit_test.dart` (x2) + `dashboard_screen_test.dart`'s icon assertion: `DashboardScreen`'s embedded `FeedScreen` needs `Supabase.instance` initialized or `apiServiceProvider`/`supabaseServiceProvider` overridden; this test provides neither, so `Supabase.instance`'s own `assert()` throws — true before this session too, since the old `feedAssetsProvider` also called `ref.read(supabaseServiceProvider)` unconditionally. Separately, `dashboard_screen.dart`'s FAB uses `ZetaIcons.add` while the test checks for `Icons.add` — an unrelated icon-library migration mismatch (see the repo's many `ZETA-MIGRATION-TODO` comments).
- Backend `mypy`: `firebase_auth_service.py` (3 unused type:ignore comments), `routers/sharing.py`/`assets.py` (a `SharedAsset` schema type mismatch) — all pre-existing, unrelated files.

### Accidental incident (resolved, no data lost)
Early in this session a malformed `git stash push` command accidentally triggered a `git stash pop` of a **pre-existing, unrelated** stash (`stash@{0}`, "pull-all.sh auto-stash before pull") that wasn't mine, causing merge conflicts in 4 `nmtk/neuro_toolkit` deployment files. Resolved by restoring those 4 files to HEAD (confirmed via `git status` they had zero prior modifications) — the stash itself was never dropped and remains in `git stash list` for the user to handle separately whenever they want.
