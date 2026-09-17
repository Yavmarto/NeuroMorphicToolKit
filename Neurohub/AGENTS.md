# Neurohub

Read first:
- `CODING_STYLE_GUIDE.md`
- `pyproject.toml`
- `frontend/pubspec.yaml`
- `frontend/analysis_options.yaml`
- `.pre-commit-config.yaml`
- `neurohub_spec.md`
- `docs/ADR-Codex/`, `docs/ADR-claude/`

Constraints:
- `neurohub/contracts/*.py` own project, workflow, bundle, and metadata payloads; update contracts and contract tests before changing routers or services.
- Neurohub is a registry and metadata layer, not the suite launcher or runtime control plane. `nmtk` owns install, startup, health, workspace, and runtime orchestration.
- Keep cross-app reads and writes centralized in `neurohub/app/services/suite_client.py`; do not reimplement product-module service logic here.
- Store references, metadata, workflow history, and cross-module links here; large artefacts and module-specific execution logic stay in the owning module.
- Any suite-visible workflow or asset metadata change requires reading the producer or consumer module first, not inferring the contract from old payloads.
- Verify touched surfaces with `PYTHONPATH=. pytest neurohub/tests/`, `ruff check neurohub/`, `mypy neurohub/`, and `cd frontend && flutter test`.

Do NOT:
- Add launcher, install/start/stop, runtime health, or workspace-control behavior that duplicates `nmtk`.
- Monitor health of other suite services (GET /health is self-only — returns NeuroHub's own database connectivity and version only).
- Change workflow or project payload fields only in the frontend.
- Treat timeouts or partial service failure as impossible in suite-client code.

## Shell mode

Primary screen uses `NmtkShellMode.command`. Pass `mode: NmtkShellMode.command` to `NmtkDesktopScaffold` (or `NmtkTopAppBar` in embedded mode). This is the default, but always pass it explicitly for clarity.


---

## Pipeline Agent Directives

This document provides specific instructions and context for AI agents working on the NeuroHub module. NeuroHub is the suite registry and metadata layer. It is not the launcher or runtime control plane; that role belongs to `nmtk`.

## Tech Stack & Architecture

- **Backend**: Python 3.10+ using FastAPI.
- **Frontend**: Flutter (Dart) web application.
- **Port Assignment**: NeuroHub backend runs on port **8005**.
- **Suite Ports**: neurocnl (8000), NeuroSim (8001), NeuroChip (8002), NeuroBench (8003), NeuroSense (8004).
- **Database**: SQLite with SQLAlchemy ORM.

## Contract-Driven Development (CDD)

NeuroHub follows a strict CDD approach. Pydantic contracts in `neurohub/contracts/` define the data structures and validation rules for project metadata, workflow references, bundle payloads, and cross-app communication.
- **Validation**: Contracts enforce workflow and bundle integrity plus cross-module payload consistency.
- **Re-use**: Routers and schemas in `neurohub/app/` should re-export and utilize these centralized contracts.

## Testing & Quality Assurance

- **Property-Based Testing (PBT)**: Use Hypothesis for property tests in `neurohub/tests/properties/` to verify core contracts.
- **Unit & Integration Tests**: Use `pytest` for backend tests and `flutter test` for frontend tests.
- **CI Pipeline**: All changes must pass linting (Ruff/Flake8/flutter_lints) and type checking (MyPy/flutter analyze).

## Shared Assets & NIR

- **Models**: NIR (Neuromorphic Intermediate Representation) models are managed via `neurohub/app/services/nir_service.py`.
- **Storage**: Standard shared directory is `nmtk_workspace/models/`.

## Flutter Guidelines

- Follow Effective Dart and `flutter_lints`.
- Extract widgets instead of methods for better context and performance.
- Use the `provider` package for state management.
- External API communication is centralized in `frontend/lib/services/api_service.dart`.
- Do not add launcher-parallel workspace switching, install/start controls, or runtime health ownership to the NeuroHub frontend.

## Python Guidelines

- Follow PEP 8 and use Google-style docstrings.
- Strict type hints are mandatory.
- Use absolute imports from the `neurohub` root.
- Ensure `model_config = ConfigDict(from_attributes=True)` is used in Pydantic schemas mapped to SQLAlchemy models.

<directory_structure>
├── AGENTS.md
├── CHANGELOG.md
├── Dockerfile
├── LICENSE
├── Makefile
├── Neurohub_shell_adapter
│   ├── LICENSE
│   ├── lib
│   │   ├── neurohub_shell_adapter.dart
│   │   └── src
│   │       └── neurohub_shell_adapter.dart
│   ├── pubspec.lock
│   └── pubspec.yaml
├── README.md
├── SECURITY.md
├── UI migration.md
├── add-neokens-models.sh
├── alembic.ini
├── docker-compose.yml
├── docs
│   ├── 2026-05-11-neurohub-factory-mission-plan.md
│   ├── ADR-Codex
│   │   └── 0001-initial-architecture.md
│   ├── ADR-Gemini
│   │   └── 0001-initial-architecture.md
│   ├── ADR-claude
│   │   ├── 0001-postgresql-sqlalchemy-alembic.md
│   │   ├── 0002-jwt-authentication.md
│   │   ├── 0003-workflow-engine.md
│   │   ├── 0004-suite-service-discovery.md
│   │   └── 0005-artifact-versioning.md
│   ├── archive
│   │   ├── 02-Apr-2026-status-Jules.md
│   │   └── neurohub-plan.md
│   ├── hub-seed-guide.md
│   ├── neurohub
│   │   ├── api_reference.md
│   │   ├── developer_guide.md
│   │   └── user_guide.md
│   ├── neurohub_functional_testing_guide.md
│   └── unified-dev-pipeline
│       └── neurohub
│           └── GUARDRAILS.md
├── frontend
│   ├── Dockerfile
│   ├── LICENSE
│   ├── README.md
│   ├── analysis_options.yaml
│   ├── build_error.txt
│   ├── dart_test.yaml
│   ├── integration_test
│   │   └── app_test.dart
│   ├── lib
│   │   ├── app.dart
│   │   ├── main.dart
│   │   ├── models
│   │   │   ├── health_status.dart
│   │   │   ├── project.dart
│   │   │   ├── project_bundle.dart
│   │   │   └── shared_asset.dart
│   │   ├── providers
│   │   │   ├── asset_library_provider.dart
│   │   │   ├── auth_provider.dart
│   │   │   ├── dashboard_provider.dart
│   │   │   ├── riverpod_providers.dart
│   │   │   └── supabase_provider.dart
│   │   ├── routing
│   │   │   └── transitions.dart
│   │   ├── screens
│   │   │   ├── asset_library_screen.dart
│   │   │   ├── bundle_inspection_screen.dart
│   │   │   ├── dashboard_screen.dart
│   │   │   ├── feed_screen.dart
│   │   │   ├── live_test_screen.dart
│   │   │   ├── login_screen.dart
│   │   │   ├── my_shares_screen.dart
│   │   │   ├── new_project_screen.dart
│   │   │   ├── project_detail_screen.dart
│   │   │   ├── register_screen.dart
│   │   │   ├── settings_screen.dart
│   │   │   └── share_model_screen.dart
│   │   ├── services
│   │   │   ├── api_service.dart
│   │   │   └── supabase_service.dart
│   │   ├── shell
│   │   │   ├── neurohub_deep_link.dart
│   │   │   ├── neurohub_restoration_snapshot.dart
│   │   │   ├── neurohub_route_state.dart
│   │   │   └── neurohub_workspace_controller.dart
│   │   ├── shell_adapter.dart
│   │   ├── view_models
│   │   │   └── dashboard_shell_view_model.dart
│   │   └── widgets
│   │       ├── asset_card.dart
│   │       ├── bundle_export_dialog.dart
│   │       ├── config_panel.dart
│   │       ├── live_test_dashboard.dart
│   │       ├── member_manager.dart
│   │       ├── milestone_timeline.dart
│   │       ├── note_editor.dart
│   │       ├── onboarding_tour.dart
│   │       └── workflow_step_card.dart
│   ├── nginx.conf
│   ├── pubspec.lock
│   ├── pubspec.yaml
│   ├── test
│   │   ├── governance
│   │   │   └── material_icons_audit_test.dart
│   │   ├── helpers
│   │   │   └── fake_supabase_service.dart
│   │   ├── providers
│   │   │   ├── auth_provider_test.dart
│   │   │   ├── dashboard_provider_test.dart
│   │   │   └── feed_providers_test.dart
│   │   ├── screens
│   │   │   ├── asset_library_screen_test.dart
│   │   │   ├── bundle_inspection_screen_test.dart
│   │   │   ├── dashboard_screen_test.dart
│   │   │   ├── live_test_screen_test.dart
│   │   │   ├── login_screen_test.dart
│   │   │   ├── neurohub_responsive_audit_test.dart
│   │   │   ├── new_project_screen_test.dart
│   │   │   ├── project_detail_screen_test.dart
│   │   │   ├── settings_screen_test.dart
│   │   │   └── share_model_screen_test.dart
│   │   ├── services
│   │   │   ├── suite_api_base_test.dart
│   │   │   └── supabase_service_test.dart
│   │   ├── shell
│   │   │   └── neurohub_shell_adapter_test.dart
│   │   ├── widget_test.dart
│   │   └── widgets
│   │       ├── asset_card_test.dart
│   │       ├── bundle_export_dialog_test.dart
│   │       ├── config_panel_test.dart
│   │       ├── live_test_dashboard_test.dart
│   │       ├── member_manager_test.dart
│   │       ├── milestone_timeline_test.dart
│   │       ├── note_editor_test.dart
│   │       └── workflow_step_card_test.dart
│   └── web
│       ├── favicon.png
│       ├── icons
│       │   ├── Icon-192.png
│       │   ├── Icon-512.png
│       │   ├── Icon-maskable-192.png
│       │   └── Icon-maskable-512.png
│       ├── index.html
│       └── manifest.json
├── issues
│   └── 025-prod-responsive-dashboard-and-bundle-surfaces.md
├── issues-archive
│   ├── 001-align-suite-health-checks-with-real-module-routes.md
│   ├── 001-beta-unify-auth-stack-and-fix-undefined-auth-paths.md
│   ├── 002-beta-fix-frontend-analyzer-errors-and-url-launcher-dependency.md
│   ├── 003-beta-replace-mock-suite-with-real-orchestration-smoke.md
│   ├── 006-beta-rate-limiting.md
│   ├── 007-beta-authentication-layer.md
│   ├── 008-beta-structured-logging.md
│   ├── 009-beta-workflow-engine-completion.md
│   ├── 01-f811-redefined-names.md
│   ├── 010-beta-module-health-monitoring-dashboard.md
│   ├── 011-beta-security-md-and-changelog-md.md
│   ├── 012-prod-end-to-end-integration-tests.md
│   ├── 013-prod-database-migration-system.md
│   ├── 014-prod-multi-user-support.md
│   ├── 015-prod-container-hardening.md
│   ├── 016-prod-user-documentation.md
│   ├── 017-prod-auth-router-coverage-and-delete-flow.md
│   ├── 018-prod-project-access-negative-paths.md
│   ├── 019-prod-rate-limit-contract-and-header-tests.md
│   ├── 02-plw0602-global-state.md
│   ├── 020-prod-concurrency-test-isolation.md
│   ├── 021-prod-workflow-dag-edge-case-tests.md
│   ├── 022-prod-asset-integrity-and-type-validation.md
│   ├── 023-prod-export-bundle-handoff-contract-tests.md
│   ├── 024-prod-happy-path-functional-e2e.md
│   ├── 03-arg001-unused-router-args.md
│   ├── 04-g004-try401-logging.md
│   ├── 05-pt011-pytest-raises-match.md
│   ├── 06-pth-pathlib-modernization.md
│   ├── 07-sim117-nested-with.md
│   ├── 08-plc0206-era001-dict-and-deadcode.md
│   ├── 09-npy002-numpy-random.md
│   ├── 10-ann-type-hints.md
│   ├── 10-neurohub-shared-shell-theme-and-project-overview.md
│   ├── 11-d417-docstring-args.md
│   ├── 11-neurohub-shell-adapter-and-workflow-restoration.md
│   ├── 12-neurohub-bundle-inspection-and-orchestration-controls.md
│   ├── 12-plc0415-inline-imports.md
│   ├── 13-plr2004-magic-numbers.md
│   ├── 14-plr0915-oversized-functions.md
│   ├── README.md
│   └── test_coverage_plan.md
├── mypy_no_plugin.ini
├── neurohub
│   ├── GUARDRAILS.md
│   ├── __init__.py
│   ├── app
│   │   ├── __init__.py
│   │   ├── auth.py
│   │   ├── limiter.py
│   │   ├── logging_conf.py
│   │   ├── main.py
│   │   ├── middleware.py
│   │   ├── registry_security.py
│   │   ├── routers
│   │   │   ├── __init__.py
│   │   │   ├── assets.py
│   │   │   ├── auth.py
│   │   │   ├── config.py
│   │   │   ├── health.py
│   │   │   ├── projects.py
│   │   │   ├── registry_artefacts.py
│   │   │   ├── registry_auth.py
│   │   │   ├── registry_community.py
│   │   │   ├── registry_health.py
│   │   │   ├── registry_search.py
│   │   │   └── sharing.py
│   │   ├── schemas
│   │   │   ├── __init__.py
│   │   │   ├── activity.py
│   │   │   ├── assets.py
│   │   │   ├── bundles.py
│   │   │   ├── config.py
│   │   │   ├── dashboard.py
│   │   │   ├── health.py
│   │   │   ├── milestones.py
│   │   │   ├── notes.py
│   │   │   ├── projects.py
│   │   │   ├── users.py
│   │   │   └── workflows.py
│   │   ├── services
│   │   │   ├── __init__.py
│   │   │   ├── activity_feed.py
│   │   │   ├── asset_library.py
│   │   │   ├── auth_service.py
│   │   │   ├── bundle_service.py
│   │   │   ├── config_service.py
│   │   │   ├── model_zoo_manifest.py
│   │   │   ├── object_storage.py
│   │   │   ├── project_service.py
│   │   │   ├── registry_auth_service.py
│   │   │   ├── registry_service.py
│   │   │   ├── search_index.py
│   │   │   └── suite_client.py
│   │   └── utils
│   │       ├── __init__.py
│   │       └── uri_parser.py
│   ├── contracts
│   │   ├── __init__.py
│   │   ├── bundle_contracts.py
│   │   ├── project_contracts.py
│   │   ├── registry_contracts.py
│   │   └── workflow_contracts.py
│   ├── db
│   │   ├── __init__.py
│   │   ├── database.py
│   │   ├── migrations
│   │   │   ├── README
│   │   │   ├── env.py
│   │   │   ├── script.py.mako
│   │   │   └── versions
│   │   │       ├── 1c146618b802_add_status_to_projects.py
│   │   │       ├── 3426e94d3033_add_sha256_to_shared_assets.py
│   │   │       ├── a838fc1f0016_initial_migration.py
│   │   │       ├── b1d2e3f40001_add_global_registry_tables.py
│   │   │       └── c2d4e5f60002_drop_pm_workflow_tables.py
│   │   └── models.py
│   └── tests
│       ├── SMOKE_TESTS.md
│       ├── __init__.py
│       ├── conftest.py
│       ├── mock_suite_server.py
│       ├── properties
│       │   ├── __init__.py
│       │   ├── test_bundle_properties.py
│       │   ├── test_project_properties.py
│       │   ├── test_registry_properties.py
│       │   └── test_workflow_properties.py
│       ├── test_alembic_migrations.py
│       ├── test_all_endpoints.py
│       ├── test_artefact_type.py
│       ├── test_asset_library.py
│       ├── test_assets_router.py
│       ├── test_auth.py
│       ├── test_auth_service.py
│       ├── test_concurrency.py
│       ├── test_config_service.py
│       ├── test_contract_invariants.py
│       ├── test_contracts.py
│       ├── test_cors.py
│       ├── test_export_import.py
│       ├── test_handoff_integration.py
│       ├── test_model_zoo_manifest.py
│       ├── test_prod_integration.py
│       ├── test_projects.py
│       ├── test_rate_limiting.py
│       ├── test_registry_artefacts.py
│       ├── test_smoke.py
│       └── test_suite_client.py
├── neurohub.db
├── neurohub.egg-info
│   ├── PKG-INFO
│   ├── SOURCES.txt
│   ├── dependency_links.txt
│   ├── requires.txt
│   └── top_level.txt
├── neurohub_spec.md
├── patch_ci.py
├── patch_mypy.py
├── patch_precommit.py
├── pyproject.toml
├── run_dbg8.py
├── scripts
│   ├── run_smoke_test.sh
│   └── seed_hub_entries.py
├── shared_assets
│   ├── 066250df-f3a1-4e9e-92bc-92d8ba872a7e.json
│   ├── 1a4f1cc2-ec33-45d3-a2da-7322bd77c5c7.json
│   ├── 1ff89d26-ac0c-477c-84b2-36d0e33d853d.json
│   ├── 2413feaa-442a-4285-b46e-943e8f532f21.json
│   ├── 30d305e4-ad91-4107-9eae-6bed2023d283.json
│   ├── 4a6119c8-93f3-4ecc-b60a-260a013a63b7.json
│   ├── 547c695c-e03e-4f5a-8216-4b5cdd7d0003.nir
│   ├── 59476c54-fbb3-4916-96a6-cf879f6f64ac.json
│   ├── 5e266cca-9910-4a6e-8167-d36d9b9e97e0.json
│   ├── 61940329-4d2a-4095-98e3-29d0da695598.json
│   ├── 68e7917a-3eef-46d1-b89f-ccc76db5bac4.json
│   ├── 70d04c3d-7a5a-4da3-8b49-61b408aa2efb.json
│   ├── 763a04a1-20a0-4a6d-bc78-a9cba94d13bf.json
│   ├── 77dd2648-b373-42fb-af4a-528347cf0340.json
│   ├── 78ca816c-7cd4-43fe-a5ff-23222e3f45d6.json
│   ├── 7fc5e4fa-d5da-4548-88f3-a01931ffd74b.json
│   ├── 8d4bfe65-57b0-4793-9916-db2b71b3ccbd.json
│   ├── 919d228e-80fc-4781-80f6-2d1cf7bdc82b.json
│   ├── 95610392-3780-4197-9889-417d875538e6.json
│   ├── a5c7d5ba-14ff-4d4f-ab42-7a5273ec0358.json
│   ├── a878fcfa-a19d-4000-8d60-ede49c714839.json
│   ├── a8c3e900-7ce6-48b3-b4fd-86a58134a8ec.json
│   ├── bee8d89d-8490-4f11-aeb8-b7bfba33a000.json
│   ├── benchmark_definition
│   │   ├── dvs_gesture.json
│   │   ├── ecg_classification.json
│   │   ├── grip_stability.json
│   │   ├── keyword_spotting.json
│   │   ├── mackey_glass.json
│   │   └── primate_reaching.json
│   ├── c47fdc22-d7b5-4f44-b494-2445f6375751.json
│   ├── cnl_spec
│   │   ├── audio_wakeword.cnl
│   │   ├── cpg_rhythm.cnl
│   │   ├── dream_hand_reflex_arc.cnl
│   │   ├── dream_hand_sleep_arc.cnl
│   │   ├── eeg_attention.cnl
│   │   ├── emg_gripper.cnl
│   │   ├── looming_detector.cnl
│   │   ├── object_recognition.cnl
│   │   ├── prosthetic_reflex.cnl
│   │   ├── reflex_arc.cnl
│   │   ├── sleep_arc.cnl
│   │   ├── slip_reflex.cnl
│   │   └── visual_tracker.cnl
│   ├── d047c857-c6cb-4349-b098-b33a14eb81ff.json
│   ├── d0781705-0cec-4320-9af2-a3d8a473f330.json
│   ├── d3adae42-342c-4f74-abcb-fdef1f143682.json
│   ├── ed86b2ff-4a14-4d8d-a825-b32189651a7a.json
│   ├── encoding_preset
│   │   ├── audio_mfcc_rate.json
│   │   └── biomedical_delta.json
│   ├── f459d24f-682e-49fd-a21b-dd878e6789a8.json
│   ├── f944c7de-9e21-4314-90c2-7216d92912a7.json
│   └── shared
│       └── e2e_template.json
├── test_coverage_results.txt
├── uv.lock
└── verify-contracts-local.sh
</directory_structure>

## Remote Testing Configuration

For dev, `REMOTE_HOST=dev@<dev-host>` can be used. For example, when the agent wants to test run the app, you can use `<dev-host>` as the server address.
