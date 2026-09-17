# neurocnl

Read first:
- `CODING_STYLE_GUIDE.md`
- `pyproject.toml`
- `frontend/pubspec.yaml`
- `frontend/analysis_options.yaml`
- `.pre-commit-config.yaml`
- `docs/support_matrix.md`
- `docs/PRE_BETA_READINESS_REVIEW.md`
- `docs/ADR-Gemini/`, `docs/ADR-Codex/`, `docs/ADR-claude/`

Constraints:
- `neurocnl` owns CNL grammar, backend support verdicts, generated graph semantics, and deploy handoff claims; update the owning contracts, docs, and regression tests together.
- Any change to parser output, graph shape, export payloads, or support status requires reading the downstream consumer first: `Neurosim`, `Neurochip`, `Neuro-Dream-Hand`, `Neurobench`, `Neurohub`, or `Neurosense`, depending on the boundary touched.
- Do not promote a backend or export path from `unsupported` or `approximate` to stronger semantics unless `docs/support_matrix.md` and the corresponding tests are updated in the same change.
- Keep library behavior in `neurocnl/`, API behavior in `backend/`, and frontend behavior in `frontend/`; avoid hiding shared semantics inside only one surface.
- Verify touched surfaces with `PYTHONPATH=. pytest neurocnl/tests/`, `ruff check .`, `mypy .`, and `cd frontend && flutter test` when frontend contracts move.

Do NOT:
- Change support claims, target names, or export field names from memory.
- Edit a shared handoff format without checking the consumer repo first.
- Treat root integration tests as optional when suite-visible CNL behavior changes.

## State Machine Invariants

The SNN workflow uses a sequential step-unlock state machine. These invariants are non-negotiable:

- **`kStudioPipelineStepNames` (studio_pipeline_steps.dart) must exactly match
  `SnnWorkflowPhase.values.map((p) => p.name).toList()`**. Update both atomically. A test in
  `test/providers/step_unlock_provider_test.dart` asserts this; CI will fail if they diverge. An
  assert in `step_unlock_provider.dart` also fires in debug builds.
- **Every call site of `workspaceProvider.notifier.setActivePipelineStep()` must guard with
  `if (unlockedSteps.contains(stepName))` first**. The `WorkspaceController` has no lock awareness
  (adding it would create a circular dependency with `unlockedStepsProvider`); enforcement is the
  caller's responsibility. Current guarded call sites: `onStepSelected`, `onStepChanged`,
  `onSplitNavigate`, `onCollapse` in `studio_screen.dart`.
- **`lockedPhasesProvider` is the canonical source for UI lock state.** Do not recompute
  "is step X locked?" inline — watch the provider.
- **Do not add a new `SnnWorkflowPhase` value** without simultaneously adding its `.name` to
  `kStudioPipelineStepNames` and adding unlock logic in `unlockedStepsProvider`.

## Shell mode

Primary screen uses `NmtkShellMode.studio`. Pass `mode: NmtkShellMode.studio` to `NmtkDesktopScaffold` (or `NmtkTopAppBar` in embedded mode). Do not use `.command` or `.instrument`.

The 12 px outer padding on `StudioScreen` is an intentional IDE-compact exception — mark it with a `// studio-compact` comment and do not upgrade to the suite default of 24 px.


---

## Pipeline Agent Directives

## Non-Negotiable

1. **NEVER modify `layers/layer1_invariants.py`** without explicit human approval. These are physics laws, not business rules.
2. **NEVER hard-code physics constants** — they come from contracts or invariant functions.
3. **ALWAYS run `pytest` and `mypy --strict`** before considering a task complete.
4. **ALWAYS check GUARDRAILS.md** before starting implementation.
5. **NEVER delete or weaken existing test assertions** — if a test fails, fix the code, not the test.
6. **NEVER modify CNL grammar patterns** in `cnl_parser.py` without human approval. Grammar changes affect all downstream modules.

## Domain Rules

7. All neuron parameters must validate against Layer 1 invariants before use.
8. All hardware exports must satisfy target-specific contracts (Loihi, SpiNNaker, Teensy).
9. Simulation results must be compared against golden baselines when available.
10. The CNL parser uses regex only — no LLM calls in the parse path.
11. Layer 3 assertions must test exactly one behavioral rule per test function.
12. Export code must produce files that compile/validate on the target platform.

## When to Stop and Ask

- Any change that affects Layer 1 invariants or their validator
- Any new CNL concept or grammar extension
- Any new hardware target not covered by existing contracts
- Any simulation result that deviates >10% from golden baseline
- Any change to the `pipeline.py` orchestration flow
- Any modification to the Anthropic API integration in assertion generator

<directory_structure>
├── AGENTS.md
├── CHANGELOG.md
├── COMPARISON.md
├── LICENSE
├── Makefile
├── PORTFOLIO_ROADMAP.md
├── README.md
├── ROADMAP.md
├── SECURITY.md
├── SECURITY_REVIEW.md
├── UI migration.md
├── agent_execution_guide.md
├── backend
│   ├── Dockerfile
│   ├── OPS.md
│   ├── __init__.py
│   ├── app
│   │   ├── __init__.py
│   │   ├── main.py
│   │   ├── middleware
│   │   │   ├── __init__.py
│   │   │   ├── auth.py
│   │   │   ├── metrics.py
│   │   │   ├── rate_limit.py
│   │   │   ├── request_id.py
│   │   │   └── response_time.py
│   │   ├── routers
│   │   │   ├── __init__.py
│   │   │   ├── datasets.py
│   │   │   ├── deploy.py
│   │   │   ├── export.py
│   │   │   ├── generate.py
│   │   │   ├── jobs.py
│   │   │   ├── neurosim_handoff.py
│   │   │   ├── nir_inspect.py
│   │   │   ├── notebook.py
│   │   │   ├── parse.py
│   │   │   ├── prosthetic
│   │   │   │   ├── __init__.py
│   │   │   │   ├── analysis.py
│   │   │   │   ├── export.py
│   │   │   │   ├── hardware.py
│   │   │   │   ├── simulate.py
│   │   │   │   └── sleep.py
│   │   │   ├── simulate.py
│   │   │   ├── simulators.py
│   │   │   ├── templates.py
│   │   │   ├── training.py
│   │   │   └── validate.py
│   │   ├── schemas
│   │   │   ├── __init__.py
│   │   │   ├── common.py
│   │   │   ├── datasets.py
│   │   │   ├── generate.py
│   │   │   ├── jobs.py
│   │   │   ├── neurosim_handoff.py
│   │   │   ├── parse.py
│   │   │   ├── prosthetic.py
│   │   │   ├── runtime.py
│   │   │   ├── simulate.py
│   │   │   ├── simulators.py
│   │   │   ├── training.py
│   │   │   └── validate.py
│   │   ├── scratch.py
│   │   ├── services
│   │   │   ├── __init__.py
│   │   │   ├── dataset_cache.py
│   │   │   ├── dataset_catalog.py
│   │   │   ├── energy_service.py
│   │   │   ├── fault_injection_service.py
│   │   │   ├── hardware_service.py
│   │   │   ├── job_store.py
│   │   │   ├── lava_deploy_service.py
│   │   │   ├── nengo_code_exporter.py
│   │   │   ├── network_serializer.py
│   │   │   ├── neurocnl_bridge.py
│   │   │   ├── neurosense_artifact.py
│   │   │   ├── nir_code_exporter.py
│   │   │   ├── nir_graph_serializer.py
│   │   │   ├── progress_bus.py
│   │   │   ├── prosthetic_runner.py
│   │   │   ├── sleep_runner.py
│   │   │   └── training_service.py
│   │   ├── templates
│   │   │   ├── audio_wakeword.cnl
│   │   │   ├── coincidence_detector.cnl
│   │   │   ├── cpg_rhythm.cnl
│   │   │   ├── dopamine_stp_decision.cnl
│   │   │   ├── edge_enhancement.cnl
│   │   │   ├── eeg_attention.cnl
│   │   │   ├── emg_gripper.cnl
│   │   │   ├── looming_detector.cnl
│   │   │   ├── object_recognition.cnl
│   │   │   ├── prosthetic_reflex.cnl
│   │   │   ├── prosthetic_sleep.cnl
│   │   │   ├── reflex_arc.cnl
│   │   │   ├── slip_reflex.cnl
│   │   │   ├── stochastic_decision.cnl
│   │   │   ├── visual_homeostasis_gate.cnl
│   │   │   └── visual_tracker.cnl
│   │   └── utils
│   │       └── cnl_errors.py
│   ├── assets
│   │   └── datasets
│   │       ├── catalog.json
│   │       └── description.txt
│   ├── datasets
│   ├── datasets.db
│   ├── logs
│   │   └── neurocnl.log
│   ├── projects.db
│   ├── requirements.in
│   ├── requirements.txt
│   ├── test.db
│   ├── test_all.py
│   ├── test_db.py
│   ├── test_download_crash.py
│   ├── test_download_new.py
│   ├── test_fetch_size_local.py
│   ├── test_fetch_sizes.py
│   ├── test_find.py
│   ├── test_find_all.py
│   ├── test_firebase.py
│   ├── test_firebase_api.py
│   ├── test_firebase_full.py
│   ├── test_firebase_meta.py
│   ├── test_gcs_api.py
│   ├── test_get_row.py
│   ├── test_hash.py
│   ├── test_items.py
│   ├── test_json.py
│   ├── test_list_entries.py
│   ├── test_paginate.py
│   ├── test_pingpong.py
│   ├── test_pydantic_mut.py
│   ├── test_sizes.py
│   ├── test_threadpool.py
│   └── tests
│       ├── __init__.py
│       ├── conftest.py
│       ├── pytest.ini
│       ├── test_app_core.py
│       ├── test_auth.py
│       ├── test_common_schema.py
│       ├── test_cors_config.py
│       ├── test_dataset_cache.py
│       ├── test_dataset_catalog.py
│       ├── test_datasets_import_local.py
│       ├── test_deploy_endpoints.py
│       ├── test_e2e_pipeline.py
│       ├── test_energy_service.py
│       ├── test_export_router.py
│       ├── test_generate_router.py
│       ├── test_hardware_service.py
│       ├── test_health.py
│       ├── test_job_store_service.py
│       ├── test_jobs_router.py
│       ├── test_metrics.py
│       ├── test_neurosim_handoff_router.py
│       ├── test_nir_graph_serializer_dt.py
│       ├── test_nir_graph_serializer_fusion.py
│       ├── test_nir_graph_serializer_round_trip.py
│       ├── test_nir_graph_serializer_stale_fields.py
│       ├── test_notebook_generate_v2.py
│       ├── test_parse_router.py
│       ├── test_preflight_exploration.py
│       ├── test_preflight_properties.py
│       ├── test_progress_bus.py
│       ├── test_prosthetic_analysis.py
│       ├── test_prosthetic_export.py
│       ├── test_prosthetic_hardware.py
│       ├── test_prosthetic_runner_service.py
│       ├── test_prosthetic_simulate.py
│       ├── test_prosthetic_sleep.py
│       ├── test_request_id.py
│       ├── test_simulate_router.py
│       ├── test_simulator_schemas.py
│       ├── test_simulators_logging_exploration.py
│       ├── test_simulators_logging_preservation.py
│       ├── test_simulators_router.py
│       ├── test_sleep_runner_service.py
│       ├── test_templates_export.py
│       ├── test_training_dataset_resolution.py
│       ├── test_training_router.py
│       └── test_validate_router.py
├── cnl_expansion_plan.md
├── cnl_explained.md
├── cnl_hardware_semantics_plan.md
├── datasets
├── datasets.db
├── debug_screenshot.png
├── debug_studio.png
├── debug_studio_2.png
├── debug_studio_ls.png
├── demos
│   ├── README.md
│   ├── bci_neurofeedback
│   │   ├── README.md
│   │   ├── __init__.py
│   │   └── firmware
│   │       ├── bci_neurofeedback.ino
│   │       └── snn_network.h
│   ├── classical_conditioning
│   │   ├── README.md
│   │   ├── __init__.py
│   │   └── firmware
│   │       └── classical_conditioning.ino
│   ├── emg_prosthetic
│   │   ├── README.md
│   │   ├── __init__.py
│   │   └── firmware
│   │       └── emg_prosthetic.ino
│   ├── gripper_reflex
│   │   ├── README.md
│   │   ├── __init__.py
│   │   └── firmware
│   │       └── gripper_reflex.ino
│   ├── habituation
│   │   ├── README.md
│   │   ├── __init__.py
│   │   └── firmware
│   │       ├── habituation.ino
│   │       └── snn_network.h
│   └── tactile_explorer
│       ├── README.md
│       ├── __init__.py
│       └── firmware
│           └── tactile_explorer.ino
├── deprecated
│   ├── TODO.md
│   └── issues-archive
│       ├── 001-poc-expand-edge-case-invariants.md
│       ├── 001-poc-invariant-coverage-final-pass.md
│       ├── 002-poc-expand-frontend-dart-test-coverage.md
│       └── 003-poc-deprecate-old-automation-workflows.md
├── docker-compose.dev.yml
├── docker-compose.yml
├── docs
│   ├── ADR-Codex
│   │   └── 0001-initial-architecture.md
│   ├── ADR-Gemini
│   │   ├── 0001-initial-architecture.md
│   │   ├── 0002-multi-stage-translation-pipeline.md
│   │   └── 0003-invariant-constraint-checking.md
│   ├── ADR-claude
│   │   ├── 0001-regex-based-cnl-parser.md
│   │   ├── 0002-three-layer-validation.md
│   │   ├── 0003-intermediate-representation.md
│   │   ├── 0004-backend-capability-system.md
│   │   ├── 0005-multi-format-export.md
│   │   └── 0006-unified-pipeline-orchestration.md
│   ├── CNL_NIR_ARRAY_SUPPORT_PLAN.md
│   ├── CODE_REVIEW_CRITICAL_2026-05-14.md
│   ├── DEPLOYMENT_GUIDE.md
│   ├── PRE_BETA_READINESS_REVIEW.md
│   ├── PYNQ_FINN_Integration_Plan.md
│   ├── RELEASE_CHECKLIST.md
│   ├── UI_PLAN.md
│   ├── UI_SPEC.md
│   ├── USER_HAPPY_FLOW.md
│   ├── USER_TEST_GUIDE.md
│   ├── api
│   │   ├── cnl.md
│   │   ├── export.md
│   │   ├── generation.md
│   │   └── pipeline.md
│   ├── api_reference.md
│   ├── archive
│   │   ├── 02-Apr-2026-status-Jules.md
│   │   ├── lava_integration_plan.md
│   │   ├── rockpool_integration_plan.md
│   │   └── sinabs_integration_plan.md
│   ├── cnl_and_nir_explained.md
│   ├── cnl_to_nir_developer_guide.md
│   ├── code_review_critical.md
│   ├── current-tasks
│   │   ├── 2026-06-07
│   │   │   ├── frontend-migration-plan.md
│   │   │   └── studio-single-source-of-truth-remaining-implementation-plan.md
│   │   └── studio_screen_refactor.md
│   ├── datasets.md
│   ├── developer_guide.md
│   ├── ecosystem_status_2026-04-08.md
│   ├── index.md
│   ├── neurocnl_functional_testing_guide.md
│   ├── nir_to_cnl_translation_plan.md
│   ├── overlay_linux.md
│   ├── plans
│   │   └── nir_canvas_integration_plan.md
│   ├── poc_demo_readiness_assessment_2026-04-08.md
│   ├── recent_commits_analysis.md
│   ├── spinnaker2_integration_plan.md
│   ├── superpowers
│   │   └── plans
│   │       ├── 2026-05-14-t1-2-canonical-studio-graph-model.md
│   │       └── 2026-05-14-t1-3-nir-to-cnl-translation-bridge.md
│   ├── support_matrix.md
│   ├── tasks
│   │   └── 12-june
│   │       └── canvas-drawing-model.md
│   └── user_guide.md
├── examples
│   ├── 03_generate_and_train_braille.py
│   ├── 04_full_pipeline_poc.py
│   ├── README.md
│   ├── audio_wakeword.cnl
│   ├── custom_params.cnl
│   ├── eeg_attention.cnl
│   ├── emg_gripper.cnl
│   ├── reflex_arc.cnl
│   ├── slip_reflex.cnl
│   └── working_examples.md
├── fix_akida.py
├── fix_akida2.py
├── fix_grid.py
├── fix_learning.py
├── fix_learning2.py
├── fix_nir.py
├── fix_nir2.py
├── fix_property_panel.py
├── fix_simulator.py
├── fix_simulator2.py
├── fix_simulator3.py
├── fix_types.patch
├── frontend
│   ├── Dockerfile
│   ├── LICENSE
│   ├── README.md
│   ├── analysis_options.yaml
│   ├── analyze.txt
│   ├── android
│   │   ├── app
│   │   │   ├── build.gradle.kts
│   │   │   └── src
│   │   │       ├── debug
│   │   │       │   └── AndroidManifest.xml
│   │   │       ├── main
│   │   │       │   ├── AndroidManifest.xml
│   │   │       │   ├── java
│   │   │       │   │   └── io
│   │   │       │   │       └── flutter
│   │   │       │   │           └── plugins
│   │   │       │   │               └── GeneratedPluginRegistrant.java
│   │   │       │   ├── kotlin
│   │   │       │   │   └── com
│   │   │       │   │       └── example
│   │   │       │   │           └── neurocnl_studio
│   │   │       │   │               └── MainActivity.kt
│   │   │       │   └── res
│   │   │       │       ├── drawable
│   │   │       │       │   └── launch_background.xml
│   │   │       │       ├── drawable-v21
│   │   │       │       │   └── launch_background.xml
│   │   │       │       ├── mipmap-hdpi
│   │   │       │       │   └── ic_launcher.png
│   │   │       │       ├── mipmap-mdpi
│   │   │       │       │   └── ic_launcher.png
│   │   │       │       ├── mipmap-xhdpi
│   │   │       │       │   └── ic_launcher.png
│   │   │       │       ├── mipmap-xxhdpi
│   │   │       │       │   └── ic_launcher.png
│   │   │       │       ├── mipmap-xxxhdpi
│   │   │       │       │   └── ic_launcher.png
│   │   │       │       ├── values
│   │   │       │       │   └── styles.xml
│   │   │       │       └── values-night
│   │   │       │           └── styles.xml
│   │   │       └── profile
│   │   │           └── AndroidManifest.xml
│   │   ├── build.gradle.kts
│   │   ├── gradle
│   │   │   └── wrapper
│   │   │       └── gradle-wrapper.properties
│   │   ├── gradle.properties
│   │   ├── local.properties
│   │   └── settings.gradle.kts
│   ├── build_error.txt
│   ├── build_log.txt
│   ├── clean_pynq_tests.py
│   ├── clean_pynq_tests_v2.py
│   ├── dart_test.yaml
│   ├── dump2.txt
│   ├── fix_akida_test.py
│   ├── fix_all_state_inits.py
│   ├── fix_autodispose.py
│   ├── fix_checked_out2.py
│   ├── fix_final_few.py
│   ├── fix_final_really.py
│   ├── fix_final_tests.py
│   ├── fix_lava_test.py
│   ├── fix_mirror_test.py
│   ├── fix_mock_controllers.py
│   ├── fix_noop_pipeline.py
│   ├── fix_p8e_and_pbt.py
│   ├── fix_remaining.py
│   ├── fix_remnants.py
│   ├── fix_states.py
│   ├── fix_studio_screen_test.py
│   ├── fix_studio_screen_test2.py
│   ├── fix_studio_test.py
│   ├── fix_studio_test2.py
│   ├── fix_syntax.py
│   ├── fix_test_nir.py
│   ├── fix_tests.py
│   ├── fix_tracking.py
│   ├── fix_training.py
│   ├── fix_training_v2.py
│   ├── fix_training_v3.py
│   ├── fix_training_v4.py
│   ├── fix_training_v5.py
│   ├── fix_training_v6.py
│   ├── fix_validation_tests.py
│   ├── ios
│   │   ├── Flutter
│   │   │   ├── AppFrameworkInfo.plist
│   │   │   ├── Debug.xcconfig
│   │   │   ├── Generated.xcconfig
│   │   │   ├── Release.xcconfig
│   │   │   └── flutter_export_environment.sh
│   │   ├── Podfile
│   │   ├── Runner
│   │   │   ├── AppDelegate.swift
│   │   │   ├── Assets.xcassets
│   │   │   │   ├── AppIcon.appiconset
│   │   │   │   │   ├── Contents.json
│   │   │   │   │   ├── Icon-App-1024x1024@1x.png
│   │   │   │   │   ├── Icon-App-20x20@1x.png
│   │   │   │   │   ├── Icon-App-20x20@2x.png
│   │   │   │   │   ├── Icon-App-20x20@3x.png
│   │   │   │   │   ├── Icon-App-29x29@1x.png
│   │   │   │   │   ├── Icon-App-29x29@2x.png
│   │   │   │   │   ├── Icon-App-29x29@3x.png
│   │   │   │   │   ├── Icon-App-40x40@1x.png
│   │   │   │   │   ├── Icon-App-40x40@2x.png
│   │   │   │   │   ├── Icon-App-40x40@3x.png
│   │   │   │   │   ├── Icon-App-60x60@2x.png
│   │   │   │   │   ├── Icon-App-60x60@3x.png
│   │   │   │   │   ├── Icon-App-76x76@1x.png
│   │   │   │   │   ├── Icon-App-76x76@2x.png
│   │   │   │   │   └── Icon-App-83.5x83.5@2x.png
│   │   │   │   └── LaunchImage.imageset
│   │   │   │       ├── Contents.json
│   │   │   │       ├── LaunchImage.png
│   │   │   │       ├── LaunchImage@2x.png
│   │   │   │       ├── LaunchImage@3x.png
│   │   │   │       └── README.md
│   │   │   ├── Base.lproj
│   │   │   │   ├── LaunchScreen.storyboard
│   │   │   │   └── Main.storyboard
│   │   │   ├── GeneratedPluginRegistrant.h
│   │   │   ├── GeneratedPluginRegistrant.m
│   │   │   ├── Info.plist
│   │   │   └── Runner-Bridging-Header.h
│   │   ├── Runner.xcodeproj
│   │   │   ├── project.pbxproj
│   │   │   ├── project.xcworkspace
│   │   │   │   ├── contents.xcworkspacedata
│   │   │   │   └── xcshareddata
│   │   │   │       ├── IDEWorkspaceChecks.plist
│   │   │   │       ├── WorkspaceSettings.xcsettings
│   │   │   │       └── swiftpm
│   │   │   │           └── configuration
│   │   │   └── xcshareddata
│   │   │       └── xcschemes
│   │   │           └── Runner.xcscheme
│   │   ├── Runner.xcworkspace
│   │   │   ├── contents.xcworkspacedata
│   │   │   └── xcshareddata
│   │   │       ├── IDEWorkspaceChecks.plist
│   │   │       ├── WorkspaceSettings.xcsettings
│   │   │       └── swiftpm
│   │   │           └── configuration
│   │   └── RunnerTests
│   │       └── RunnerTests.swift
│   ├── jobs.db
│   ├── l10n.yaml
│   ├── lib
│   │   ├── app.dart
│   │   ├── config
│   │   │   ├── app_config.dart
│   │   │   └── feature_flags.dart
│   │   ├── l10n
│   │   │   ├── app_en.arb
│   │   │   ├── app_localizations.dart
│   │   │   └── app_localizations_en.dart
│   │   ├── main.dart
│   │   ├── models
│   │   │   ├── canonical_editor_document.dart
│   │   │   ├── canvas
│   │   │   │   ├── canvas.dart
│   │   │   │   ├── canvas.g.dart
│   │   │   │   ├── component.dart
│   │   │   │   ├── component.g.dart
│   │   │   │   ├── imported_cnl_spec.dart
│   │   │   │   ├── neurocnl_import_contract.dart
│   │   │   │   ├── pipeline_config.dart
│   │   │   │   ├── pipeline_dag.dart
│   │   │   │   ├── preview.dart
│   │   │   │   ├── preview.g.dart
│   │   │   │   ├── project.dart
│   │   │   │   ├── project.g.dart
│   │   │   │   ├── sweep.dart
│   │   │   │   ├── sweep.g.dart
│   │   │   │   ├── validation.dart
│   │   │   │   └── validation.g.dart
│   │   │   ├── crossbar_export.dart
│   │   │   ├── crossbar_export_result.dart
│   │   │   ├── dataset_catalog.dart
│   │   │   ├── energy_report.dart
│   │   │   ├── error_detail.dart
│   │   │   ├── fault_injection_report.dart
│   │   │   ├── flash_job_status.dart
│   │   │   ├── health_status.dart
│   │   │   ├── job_status.dart
│   │   │   ├── launcher_diagnostics.dart
│   │   │   ├── layer2_check.dart
│   │   │   ├── network_graph.dart
│   │   │   ├── nir_hdf5_tree.dart
│   │   │   ├── nir_node_type.dart
│   │   │   ├── parsed_spec.dart
│   │   │   ├── prosthetic_sim.dart
│   │   │   ├── quantization_report.dart
│   │   │   ├── sc_neurocore_synthesis_target.dart
│   │   │   ├── sensor_frame.dart
│   │   │   ├── simulation_result.dart
│   │   │   ├── simulator.dart
│   │   │   ├── simulator_preflight.dart
│   │   │   ├── sleep_train.dart
│   │   │   ├── studio_pipeline_steps.dart
│   │   │   ├── template.dart
│   │   │   ├── training.dart
│   │   │   ├── validation_result.dart
│   │   │   └── workspace_file.dart
│   │   ├── providers
│   │   │   ├── akida_deploy_provider.dart
│   │   │   ├── akida_deploy_provider.g.dart
│   │   │   ├── analysis_provider.dart
│   │   │   ├── analysis_provider.g.dart
│   │   │   ├── api_provider.dart
│   │   │   ├── canonical_doc_provider.dart
│   │   │   ├── canonical_doc_provider.g.dart
│   │   │   ├── canonical_update_origin.dart
│   │   │   ├── canvas
│   │   │   │   ├── canvas_export_provider.dart
│   │   │   │   ├── canvas_provider.dart
│   │   │   │   ├── canvas_provider.g.dart
│   │   │   │   ├── canvas_selectors.dart
│   │   │   │   ├── cnl_import_provider.dart
│   │   │   │   ├── cnl_import_provider.g.dart
│   │   │   │   ├── component_provider.dart
│   │   │   │   ├── nir_types_provider.dart
│   │   │   │   ├── project_provider.dart
│   │   │   │   ├── project_provider.g.dart
│   │   │   │   ├── simulation_provider.dart
│   │   │   │   ├── simulation_provider.g.dart
│   │   │   │   ├── sweep_provider.dart
│   │   │   │   ├── sweep_provider.g.dart
│   │   │   │   ├── sync_provider.dart
│   │   │   │   ├── sync_provider.g.dart
│   │   │   │   ├── validation_provider.dart
│   │   │   │   └── validation_provider.g.dart
│   │   │   ├── dataset_catalog_provider.dart
│   │   │   ├── export_provider.dart
│   │   │   ├── export_provider.g.dart
│   │   │   ├── hardware_config_provider.dart
│   │   │   ├── hardware_config_provider.g.dart
│   │   │   ├── hardware_provider.dart
│   │   │   ├── hardware_provider.g.dart
│   │   │   ├── hub_asset_provider.dart
│   │   │   ├── launcher_diagnostics_provider.dart
│   │   │   ├── learning_provider.dart
│   │   │   ├── learning_provider.g.dart
│   │   │   ├── native_file_adapter_provider.dart
│   │   │   ├── neurobench_panel_provider.dart
│   │   │   ├── neurobench_panel_provider.g.dart
│   │   │   ├── nir_import_provider.dart
│   │   │   ├── nir_import_provider.g.dart
│   │   │   ├── nir_ui_state_provider.dart
│   │   │   ├── nir_ui_state_provider.g.dart
│   │   │   ├── pipeline_provider.dart
│   │   │   ├── pipeline_provider.g.dart
│   │   │   ├── prosthetic_sim_provider.dart
│   │   │   ├── prosthetic_sim_provider.g.dart
│   │   │   ├── server_config_provider.dart
│   │   │   ├── server_config_provider.g.dart
│   │   │   ├── simulator_preflight_provider.dart
│   │   │   ├── simulator_preflight_provider.g.dart
│   │   │   ├── simulator_provider.dart
│   │   │   ├── simulator_provider.g.dart
│   │   │   ├── spec_provider.dart
│   │   │   ├── spec_provider.g.dart
│   │   │   ├── step_unlock_provider.dart
│   │   │   ├── studio_akida_deploy_provider.dart
│   │   │   ├── studio_akida_deploy_provider.g.dart
│   │   │   ├── studio_lava_deploy_provider.dart
│   │   │   ├── studio_lava_deploy_provider.g.dart
│   │   │   ├── studio_sync_notifier.dart
│   │   │   ├── studio_sync_notifier.g.dart
│   │   │   ├── studio_view_mode_provider.dart
│   │   │   ├── studio_view_mode_provider.g.dart
│   │   │   ├── target_availability_provider.dart
│   │   │   ├── target_availability_provider.g.dart
│   │   │   ├── template_provider.dart
│   │   │   ├── template_provider.g.dart
│   │   │   ├── training_provider.dart
│   │   │   ├── training_provider.g.dart
│   │   │   ├── workspace_provider.dart
│   │   │   └── workspace_provider.g.dart
│   │   ├── routing
│   │   │   ├── app_router.dart
│   │   │   └── canvas
│   │   │       ├── canvas_shell_adapter.dart
│   │   │       ├── neurosim_app.dart
│   │   │       ├── neurosim_deep_link.dart
│   │   │       ├── neurosim_nav_section.dart
│   │   │       ├── neurosim_restoration_snapshot.dart
│   │   │       ├── neurosim_route_state.dart
│   │   │       ├── neurosim_workspace_controller.dart
│   │   │       └── neurosim_workspace_controller.g.dart
│   │   ├── screens
│   │   │   ├── analysis_screen.dart
│   │   │   ├── canvas
│   │   │   │   ├── canvas_screen.dart
│   │   │   │   ├── export_screen.dart
│   │   │   │   ├── project_screen.dart
│   │   │   │   └── sweep_screen.dart
│   │   │   ├── canvas_host_screen.dart
│   │   │   ├── hardware_screen.dart
│   │   │   ├── server_setup_screen.dart
│   │   │   ├── studio
│   │   │   │   ├── compiled_artifacts
│   │   │   │   │   └── compiled_artifacts_panel.dart
│   │   │   │   ├── deploy
│   │   │   │   │   ├── akida_workspace.dart
│   │   │   │   │   ├── deploy_target_catalog.dart
│   │   │   │   │   ├── deploy_target_workspace.dart
│   │   │   │   │   ├── deploy_workspace_panel.dart
│   │   │   │   │   ├── lava_workspace.dart
│   │   │   │   │   └── sc_neurocore_fpga_workspace.dart
│   │   │   │   ├── file_tab_strip.dart
│   │   │   │   ├── hardware_target
│   │   │   │   │   ├── add_hardware_target_form.dart
│   │   │   │   │   └── hardware_target_dialog.dart
│   │   │   │   ├── pipeline_stage_area.dart
│   │   │   │   ├── play_stop_button.dart
│   │   │   │   ├── shared
│   │   │   │   │   └── studio_widgets.dart
│   │   │   │   ├── steps
│   │   │   │   │   ├── notebook_step.dart
│   │   │   │   │   └── setup_step.dart
│   │   │   │   ├── studio_top_bar.dart
│   │   │   │   └── workspace_open_overlay.dart
│   │   │   └── studio_screen.dart
│   │   ├── services
│   │   │   ├── akida_handoff.dart
│   │   │   ├── akida_handoff_coordinator.dart
│   │   │   ├── api_client.dart
│   │   │   ├── backend_issue_formatter.dart
│   │   │   ├── canvas_api_client.dart
│   │   │   ├── deploy_error_formatter.dart
│   │   │   ├── export_artifact.dart
│   │   │   ├── export_artifact_saver.dart
│   │   │   ├── file_adapter.dart
│   │   │   ├── file_picker_native_file_backend.dart
│   │   │   ├── host_module_navigation.dart
│   │   │   ├── hub_asset_client.dart
│   │   │   ├── import_cnl_payload.dart
│   │   │   ├── import_text_file_picker.dart
│   │   │   ├── import_text_file_picker_stub.dart
│   │   │   ├── import_text_file_picker_web.dart
│   │   │   ├── neurochip_client.dart
│   │   │   ├── neurochip_handoff.dart
│   │   │   ├── neurochip_handoff_coordinator.dart
│   │   │   ├── neurosim_handoff.dart
│   │   │   ├── neurosim_handoff_coordinator.dart
│   │   │   ├── neurosim_import_contract.dart
│   │   │   ├── notebook_generate_service.dart
│   │   │   ├── open_external_url.dart
│   │   │   ├── open_external_url_stub.dart
│   │   │   ├── open_external_url_web.dart
│   │   │   ├── picked_save_path_writer.dart
│   │   │   ├── picked_save_path_writer_io.dart
│   │   │   ├── picked_save_path_writer_stub.dart
│   │   │   ├── platform_download_result.dart
│   │   │   ├── platform_helper.dart
│   │   │   ├── platform_helper_stub.dart
│   │   │   ├── platform_helper_web.dart
│   │   │   ├── sc_neurocore_target_service.dart
│   │   │   ├── server_config_service.dart
│   │   │   ├── simulator_service.dart
│   │   │   ├── studio_akida_deploy_service.dart
│   │   │   ├── studio_lava_deploy_service.dart
│   │   │   ├── studio_target_registry_service.dart
│   │   │   └── template_load_guard.dart
│   │   ├── shell_adapter.dart
│   │   ├── src
│   │   │   ├── common_widgets
│   │   │   ├── constants
│   │   │   ├── features
│   │   │   │   └── studio
│   │   │   │       ├── application
│   │   │   │       ├── data
│   │   │   │       ├── domain
│   │   │   │       │   ├── nir_import_state.dart
│   │   │   │       │   ├── nir_import_state.freezed.dart
│   │   │   │       │   ├── nir_import_state.g.dart
│   │   │   │       │   ├── pipeline_state.dart
│   │   │   │       │   ├── pipeline_state.freezed.dart
│   │   │   │       │   ├── pipeline_state.g.dart
│   │   │   │       │   ├── simulator_state.dart
│   │   │   │       │   ├── simulator_state.freezed.dart
│   │   │   │       │   ├── workspace_file.dart
│   │   │   │       │   ├── workspace_file.freezed.dart
│   │   │   │       │   └── workspace_file.g.dart
│   │   │   │       └── presentation
│   │   │   └── routing
│   │   ├── theme
│   │   │   ├── app_theme.dart
│   │   │   └── nir_node_styles.dart
│   │   ├── utils
│   │   │   ├── canonical_canvas_support.dart
│   │   │   ├── canvas_component_utils.dart
│   │   │   └── canvas_projection_utils.dart
│   │   └── widgets
│   │       ├── akida_deploy_panel.dart
│   │       ├── canvas
│   │       │   ├── animated_snn_playback.dart
│   │       │   ├── backend_support_banner.dart
│   │       │   ├── canvas_cnl_editor.dart
│   │       │   ├── canvas_parameter_text_field.dart
│   │       │   ├── canvas_shared_widgets.dart
│   │       │   ├── canvas_simulation_surface.dart
│   │       │   ├── component_library_sidebar.dart
│   │       │   ├── export_dialog.dart
│   │       │   ├── loss_curve_chart.dart
│   │       │   ├── mobile_canvas_chrome.dart
│   │       │   ├── network_canvas.dart
│   │       │   ├── pipeline_node_property_panel.dart
│   │       │   ├── pipeline_overview_canvas.dart
│   │       │   ├── pipeline_palette.dart
│   │       │   ├── pipeline_phase_canvas.dart
│   │       │   ├── property_panel.dart
│   │       │   ├── shell_panel.dart
│   │       │   ├── simulation_control_panel.dart
│   │       │   ├── snn_dynamics_view.dart
│   │       │   ├── spike_raster_plot.dart
│   │       │   └── time_series_chart.dart
│   │       ├── cnl_editor.dart
│   │       ├── cnl_sentence_builder_dialog.dart
│   │       ├── energy_bar_chart.dart
│   │       ├── error_boundary.dart
│   │       ├── export_menu.dart
│   │       ├── hardware_connection_panel.dart
│   │       ├── hardware_sensor_panel.dart
│   │       ├── labeled_parameter_grid.dart
│   │       ├── learning_config_panel.dart
│   │       ├── loading_shimmer.dart
│   │       ├── mujoco_stream_view.dart
│   │       ├── network_graph_view.dart
│   │       ├── neurobench_panel.dart
│   │       ├── nir_importer_tab.dart
│   │       ├── ownership_boundary_card.dart
│   │       ├── parameter_explorer.dart
│   │       ├── parse_results_table.dart
│   │       ├── pipeline_bar.dart
│   │       ├── quantization_curve_chart.dart
│   │       ├── sensor_time_series_chart.dart
│   │       ├── serial_port_selector.dart
│   │       ├── shell_surface.dart
│   │       ├── simulation_dashboard.dart
│   │       ├── simulator_panel.dart
│   │       ├── stable_zeta_text_input.dart
│   │       ├── template_gallery.dart
│   │       ├── training_inspector_panel.dart
│   │       ├── validation_overlay.dart
│   │       ├── validation_panel.dart
│   │       └── workspace_comparison_panel.dart
│   ├── linux
│   │   ├── CMakeLists.txt
│   │   ├── flutter
│   │   │   ├── CMakeLists.txt
│   │   │   ├── generated_plugin_registrant.cc
│   │   │   ├── generated_plugin_registrant.h
│   │   │   └── generated_plugins.cmake
│   │   └── runner
│   │       ├── CMakeLists.txt
│   │       ├── main.cc
│   │       ├── my_application.cc
│   │       └── my_application.h
│   ├── logs
│   │   └── neurocnl.log
│   ├── macos
│   │   ├── Flutter
│   │   │   ├── Flutter-Debug.xcconfig
│   │   │   ├── Flutter-Release.xcconfig
│   │   │   └── GeneratedPluginRegistrant.swift
│   │   ├── Podfile
│   │   ├── Podfile.lock
│   │   ├── Pods
│   │   │   ├── Headers
│   │   │   ├── Local Podspecs
│   │   │   │   ├── FlutterMacOS.podspec.json
│   │   │   │   ├── file_picker.podspec.json
│   │   │   │   └── shared_preferences_foundation.podspec.json
│   │   │   ├── Pods.xcodeproj
│   │   │   │   ├── project.pbxproj
│   │   │   │   └── xcuserdata
│   │   │   │       └── yoshimartodihardjo.xcuserdatad
│   │   │   │           └── xcschemes
│   │   │   │               ├── FlutterMacOS.xcscheme
│   │   │   │               ├── Pods-Runner.xcscheme
│   │   │   │               ├── Pods-RunnerTests.xcscheme
│   │   │   │               ├── file_picker-file_picker_privacy.xcscheme
│   │   │   │               ├── file_picker.xcscheme
│   │   │   │               ├── shared_preferences_foundation-shared_preferences_foundation_privacy.xcscheme
│   │   │   │               ├── shared_preferences_foundation.xcscheme
│   │   │   │               └── xcschememanagement.plist
│   │   │   └── Target Support Files
│   │   │       ├── FlutterMacOS
│   │   │       │   ├── FlutterMacOS.debug.xcconfig
│   │   │       │   └── FlutterMacOS.release.xcconfig
│   │   │       ├── Pods-Runner
│   │   │       │   ├── Pods-Runner-Info.plist
│   │   │       │   ├── Pods-Runner-acknowledgements.markdown
│   │   │       │   ├── Pods-Runner-acknowledgements.plist
│   │   │       │   ├── Pods-Runner-dummy.m
│   │   │       │   ├── Pods-Runner-frameworks-Debug-input-files.xcfilelist
│   │   │       │   ├── Pods-Runner-frameworks-Debug-output-files.xcfilelist
│   │   │       │   ├── Pods-Runner-frameworks-Profile-input-files.xcfilelist
│   │   │       │   ├── Pods-Runner-frameworks-Profile-output-files.xcfilelist
│   │   │       │   ├── Pods-Runner-frameworks-Release-input-files.xcfilelist
│   │   │       │   ├── Pods-Runner-frameworks-Release-output-files.xcfilelist
│   │   │       │   ├── Pods-Runner-frameworks.sh
│   │   │       │   ├── Pods-Runner-umbrella.h
│   │   │       │   ├── Pods-Runner.debug.xcconfig
│   │   │       │   ├── Pods-Runner.modulemap
│   │   │       │   ├── Pods-Runner.profile.xcconfig
│   │   │       │   └── Pods-Runner.release.xcconfig
│   │   │       ├── Pods-RunnerTests
│   │   │       │   ├── Pods-RunnerTests-Info.plist
│   │   │       │   ├── Pods-RunnerTests-acknowledgements.markdown
│   │   │       │   ├── Pods-RunnerTests-acknowledgements.plist
│   │   │       │   ├── Pods-RunnerTests-dummy.m
│   │   │       │   ├── Pods-RunnerTests-umbrella.h
│   │   │       │   ├── Pods-RunnerTests.debug.xcconfig
│   │   │       │   ├── Pods-RunnerTests.modulemap
│   │   │       │   ├── Pods-RunnerTests.profile.xcconfig
│   │   │       │   └── Pods-RunnerTests.release.xcconfig
│   │   │       ├── file_picker
│   │   │       │   ├── ResourceBundle-file_picker_privacy-file_picker-Info.plist
│   │   │       │   ├── file_picker-Info.plist
│   │   │       │   ├── file_picker-dummy.m
│   │   │       │   ├── file_picker-prefix.pch
│   │   │       │   ├── file_picker-umbrella.h
│   │   │       │   ├── file_picker.debug.xcconfig
│   │   │       │   ├── file_picker.modulemap
│   │   │       │   └── file_picker.release.xcconfig
│   │   │       └── shared_preferences_foundation
│   │   │           ├── ResourceBundle-shared_preferences_foundation_privacy-shared_preferences_foundation-Info.plist
│   │   │           ├── shared_preferences_foundation-Info.plist
│   │   │           ├── shared_preferences_foundation-dummy.m
│   │   │           ├── shared_preferences_foundation-prefix.pch
│   │   │           ├── shared_preferences_foundation-umbrella.h
│   │   │           ├── shared_preferences_foundation.debug.xcconfig
│   │   │           ├── shared_preferences_foundation.modulemap
│   │   │           └── shared_preferences_foundation.release.xcconfig
│   │   ├── Runner
│   │   │   ├── AppDelegate.swift
│   │   │   ├── Assets.xcassets
│   │   │   │   └── AppIcon.appiconset
│   │   │   │       ├── Contents.json
│   │   │   │       ├── app_icon_1024.png
│   │   │   │       ├── app_icon_128.png
│   │   │   │       ├── app_icon_16.png
│   │   │   │       ├── app_icon_256.png
│   │   │   │       ├── app_icon_32.png
│   │   │   │       ├── app_icon_512.png
│   │   │   │       └── app_icon_64.png
│   │   │   ├── Base.lproj
│   │   │   │   └── MainMenu.xib
│   │   │   ├── Configs
│   │   │   │   ├── AppInfo.xcconfig
│   │   │   │   ├── Debug.xcconfig
│   │   │   │   ├── Release.xcconfig
│   │   │   │   └── Warnings.xcconfig
│   │   │   ├── DebugProfile.entitlements
│   │   │   ├── Info.plist
│   │   │   ├── MainFlutterWindow.swift
│   │   │   └── Release.entitlements
│   │   ├── Runner.xcodeproj
│   │   │   ├── project.pbxproj
│   │   │   ├── project.xcworkspace
│   │   │   │   └── xcshareddata
│   │   │   │       ├── IDEWorkspaceChecks.plist
│   │   │   │       └── swiftpm
│   │   │   │           └── configuration
│   │   │   └── xcshareddata
│   │   │       └── xcschemes
│   │   │           └── Runner.xcscheme
│   │   ├── Runner.xcworkspace
│   │   │   ├── contents.xcworkspacedata
│   │   │   └── xcshareddata
│   │   │       ├── IDEWorkspaceChecks.plist
│   │   │       └── swiftpm
│   │   │           └── configuration
│   │   └── RunnerTests
│   │       └── RunnerTests.swift
│   ├── nginx.conf
│   ├── original_nir_importer_tab.dart
│   ├── patch_header.py
│   ├── projects.db
│   ├── pubspec.lock
│   ├── pubspec.yaml
│   ├── server.log
│   ├── test
│   │   ├── app_dark_theme_test.dart
│   │   ├── governance
│   │   │   ├── material_icons_audit_test.dart
│   │   │   ├── no_section_card_in_lib_test.dart
│   │   │   └── zeta_first_audit_test.dart
│   │   ├── integration
│   │   │   └── nir_three_way_sync_test.dart
│   │   ├── models
│   │   │   ├── dataset_catalog_test.dart
│   │   │   ├── pipeline_config_test.dart
│   │   │   └── pipeline_dag_test.dart
│   │   ├── models_serialization_test.dart
│   │   ├── pipeline_integration_test.dart
│   │   ├── pipeline_provider_exploration_test.dart
│   │   ├── preservation_property_test.dart
│   │   ├── providers
│   │   │   ├── canonical_doc_provider_test.dart
│   │   │   ├── canonical_editor_provider_test.dart
│   │   │   ├── canvas
│   │   │   │   ├── canvas_echo_loop_test.dart
│   │   │   │   ├── canvas_provider_dopush_preservation_test.dart
│   │   │   │   ├── canvas_provider_nir_test.dart
│   │   │   │   ├── mirror_projection_validation_pbt_test.dart
│   │   │   │   ├── mirror_projection_validation_test.dart
│   │   │   │   ├── simulation_provider_test.dart
│   │   │   │   ├── sweep_provider_test.dart
│   │   │   │   └── sync_provider_test.dart
│   │   │   ├── dataset_catalog_provider_test.dart
│   │   │   ├── launcher_diagnostics_provider_test.dart
│   │   │   ├── nir_editor_sync_preservation_test.dart
│   │   │   ├── server_config_provider_test.dart
│   │   │   ├── step_unlock_provider_test.dart
│   │   │   ├── studio_akida_deploy_provider_test.dart
│   │   │   ├── studio_document_revision_test.dart
│   │   │   ├── studio_document_revision_test.mocks.dart
│   │   │   ├── studio_document_state_test.dart
│   │   │   ├── studio_lava_deploy_provider_test.dart
│   │   │   ├── studio_sync_notifier_nir_test.dart
│   │   │   └── studio_sync_validation_preservation_test.dart
│   │   ├── providers_test.dart
│   │   ├── providers_test.mocks.dart
│   │   ├── routing
│   │   │   └── neurosim_workspace_controller_test.dart
│   │   ├── screens
│   │   │   ├── canvas
│   │   │   │   ├── export_screen_test.dart
│   │   │   │   └── project_screen_test.dart
│   │   │   ├── hardware_screen_test.dart
│   │   │   ├── ownership_boundary_test.dart
│   │   │   ├── server_setup_screen_test.dart
│   │   │   ├── setup_step_local_import_test.dart
│   │   │   ├── studio_responsive_audit_test.dart
│   │   │   └── studio_screen_test.dart
│   │   ├── services
│   │   │   ├── akida_handoff_coordinator_test.dart
│   │   │   ├── api_client_fault_injection_test.dart
│   │   │   ├── api_client_health_test.dart
│   │   │   ├── api_client_test.dart
│   │   │   ├── apply_template_validation_test.dart
│   │   │   ├── backend_issue_formatter_test.dart
│   │   │   ├── canvas_api_client_test.dart
│   │   │   ├── deploy_error_formatter_test.dart
│   │   │   ├── file_adapter_test.dart
│   │   │   ├── file_picker_native_file_backend_test.dart
│   │   │   ├── neurochip_client_test.dart
│   │   │   ├── neurochip_handoff_coordinator_test.dart
│   │   │   ├── neurochip_handoff_test.dart
│   │   │   ├── neurosim_handoff_coordinator_test.dart
│   │   │   ├── neurosim_handoff_test.dart
│   │   │   ├── platform_helper_stub_test.dart
│   │   │   ├── sc_neurocore_target_service_test.dart
│   │   │   ├── studio_neurochip_target_test.dart
│   │   │   └── studio_target_registry_service_test.dart
│   │   ├── simulator_preflight_provider_test.dart
│   │   ├── utils
│   │   │   ├── canvas_projection_utils_edge_count_pbt_test.dart
│   │   │   ├── canvas_projection_utils_lif_preservation_pbt_test.dart
│   │   │   ├── canvas_projection_utils_nir_type_bug_exploration_test.dart
│   │   │   ├── canvas_projection_utils_preservation_test.dart
│   │   │   ├── canvas_projection_utils_type_resolution_pbt_test.dart
│   │   │   └── fake_webview.dart
│   │   ├── widget_test.dart
│   │   └── widgets
│   │       ├── akida_deploy_panel_test.dart
│   │       ├── canvas
│   │       │   ├── property_panel_test.dart
│   │       │   ├── snn_dynamics_view_test.dart
│   │       │   ├── spike_raster_plot_test.dart
│   │       │   └── time_series_chart_test.dart
│   │       ├── canvas_parameter_text_field_test.dart
│   │       ├── cnl_editor_test.dart
│   │       ├── cnl_sentence_builder_dialog_no_side_stripe_test.dart
│   │       ├── deploy_targets_no_nested_cards_test.dart
│   │       ├── deploy_workspace_no_section_card_test.dart
│   │       ├── error_reporting_test.dart
│   │       ├── export_menu_test.dart
│   │       ├── fault_injection_tab_test.dart
│   │       ├── mujoco_stream_view_test.dart
│   │       ├── network_graph_view_test.dart
│   │       ├── nir_graph_editor_panel_test.dart
│   │       ├── nir_importer_tab_error_selectable_test.dart
│   │       ├── nir_importer_tab_no_legacy_pills_test.dart
│   │       ├── nir_inspector_no_nested_cards_test.dart
│   │       ├── nir_node_card_test.dart
│   │       ├── parameter_explorer_test.dart
│   │       ├── parse_results_table_uses_item_card_test.dart
│   │       ├── sc_neurocore_lava_workspace_no_section_card_test.dart
│   │       ├── simulation_dashboard_test.dart
│   │       ├── simulator_panel_test.dart
│   │       ├── template_gallery_test.dart
│   │       ├── training_inspector_panel_test.dart
│   │       ├── validation_panel_deploy_blocked_test.dart
│   │       └── validation_panel_no_nested_cards_test.dart
│   ├── test_errors.txt
│   ├── test_panel_output.txt
│   ├── test_project_output.txt
│   ├── test_widget_output.txt
│   ├── web
│   │   ├── index.html
│   │   └── manifest.json
│   └── windows
│       ├── CMakeLists.txt
│       ├── flutter
│       │   ├── CMakeLists.txt
│       │   ├── generated_plugin_registrant.cc
│       │   ├── generated_plugin_registrant.h
│       │   └── generated_plugins.cmake
│       └── runner
│           ├── CMakeLists.txt
│           ├── Runner.rc
│           ├── flutter_window.cpp
│           ├── flutter_window.h
│           ├── main.cpp
│           ├── resource.h
│           ├── resources
│           │   └── app_icon.ico
│           ├── runner.exe.manifest
│           ├── utils.cpp
│           ├── utils.h
│           ├── win32_window.cpp
│           └── win32_window.h
├── frontend_tester.dart
├── generate_nir_importer_tab.py
├── issues
│   └── 15-neurostudio-pipeline-pane-responsive-audit.md
├── issues-archive
│   ├── 001-beta-fix-provider-template-analyzer-errors.md
│   ├── 001-fix-rockpool-nameerror.md
│   ├── 002-beta-reduce-dynamic-types-in-studio-models.md
│   ├── 002-fix-sinabs-branching.md
│   ├── 003-beta-add-real-studio-backend-integration-smoke.md
│   ├── 003-fix-nir-weight-placeholder.md
│   ├── 004-beta-restrict-cors-origins.md
│   ├── 004-spinnaker2-all-to-all-connector.md
│   ├── 005-beta-add-authentication-layer.md
│   ├── 005-pynq-finn-compilation-pipeline.md
│   ├── 006-beta-frontend-error-handling-offline-mode.md
│   ├── 006-loihi-placement-aware-mapping.md
│   ├── 007-beta-performance-benchmarking.md
│   ├── 007-implement-spinnaker2-runtime-io-mapping.md
│   ├── 007-sse-streaming-hardware-provider.md
│   ├── 008-beta-accessibility-i18n-prep.md
│   ├── 008-expose-backend-capability-manifest-api.md
│   ├── 008-fault-injection-analysis-tab.md
│   ├── 009-make-cnl-studio-target-selection-first-class.md
│   ├── 009-mujoco-stream-view-widget.md
│   ├── 009-prod-end-to-end-integration-tests.md
│   ├── 01-f811-redefined-names.md
│   ├── 010-prod-structured-logging-observability.md
│   ├── 010-wire-selected-target-into-cnl-validation.md
│   ├── 010a-pynq-studio-ui-components.md
│   ├── 010b-pynq-studio-backend-wiring.md
│   ├── 011-filter-cnl-sentence-builder-by-target.md
│   ├── 011-prod-database-persistence-for-jobs.md
│   ├── 011a-akida-studio-ui-components.md
│   ├── 011b-akida-studio-backend-wiring.md
│   ├── 012-add-target-aware-free-typing-linting.md
│   ├── 012-fix-teensy-serial-port-frontend-contract.md
│   ├── 012-prod-container-hardening.md
│   ├── 013-prod-documentation-site.md
│   ├── 013-synchronize-cnl-concept-support-contract.md
│   ├── 014-backend-export-router-test-coverage.md
│   ├── 015-backend-generate-router-test-coverage.md
│   ├── 016-backend-job-store-and-common-schemas-test-coverage.md
│   ├── 017-neurocnl-parser-core-test-coverage.md
│   ├── 018-neurocnl-nir-exporter-test-coverage.md
│   ├── 019-neurocnl-nengo-generator-test-coverage.md
│   ├── 02-plw0602-global-state.md
│   ├── 020-neurocnl-simulation-and-visualization-test-coverage.md
│   ├── 021-backend-hardware-service-test-coverage.md
│   ├── 022-backend-prosthetic-runner-test-coverage.md
│   ├── 023-backend-energy-and-sleep-services-test-coverage.md
│   ├── 024-neurocnl-framework-exporters-test-coverage.md
│   ├── 025-neurocnl-assertion-generator-test-coverage.md
│   ├── 026-neurocnl-spike-encoding-and-logging-test-coverage.md
│   ├── 027-functional-happy-path-smoke-tests.md
│   ├── 028-functional-validation-and-failure-flows.md
│   ├── 029-functional-export-and-job-handoff.md
│   ├── 03-arg001-unused-router-args.md
│   ├── 030-frontend-live-stream-placeholders.md
│   ├── 031-frontend-fault-injection-analysis.md
│   ├── 032-neurocnl-vocabulary-expansion-wave-1.md
│   ├── 033-frontend-platform-helper-native-behavior.md
│   ├── 034-cnl-semantics-docs-baseline.md
│   ├── 035-cnl-ir-types-foundation.md
│   ├── 036-cnl-ir-core-lowering.md
│   ├── 037-cnl-pipeline-ir-compat.md
│   ├── 038-cnl-timing-declarations.md
│   ├── 039-cnl-backend-capability-registry.md
│   ├── 04-g004-try401-logging.md
│   ├── 040-cnl-backend-planner-minimal.md
│   ├── 041-cnl-loihi-constraint-expansion.md
│   ├── 042-cnl-generator-fidelity-metadata.md
│   ├── 043-cnl-backend-api-surfacing.md
│   ├── 044-frontend-backend-support-panel.md
│   ├── 045-cnl-docs-refresh-backend-fidelity.md
│   ├── 048-akida-native-snn-generator.md
│   ├── 049-akida-validator-invariants.md
│   ├── 05-pt011-pytest-raises-match.md
│   ├── 06-pth-pathlib-modernization.md
│   ├── 065-sinabs-from-nir-implement-properly.md
│   ├── 066-spinnaker2-exporter-fix-sim-mode.md
│   ├── 067-rockpool-exporter-remove-tempfile.md
│   ├── 068-lava-exporter-du-formula-and-run-stop.md
│   ├── 069-sinabs-exporter-fail-at-export-time.md
│   ├── 07-sim117-nested-with.md
│   ├── 070-register-exporters-and-fix-extensions.md
│   ├── 071-pynq-exporter-nibble-range-validation.md
│   ├── 072-bptt-rockpool-tuple-assumption.md
│   ├── 073-spinnaker2-io-implement-stubs.md
│   ├── 074-akida-capabilities-dfs-deduplication.md
│   ├── 075-planner-remove-dead-elif-block.md
│   ├── 076-akida2-contract-validation-gap.md
│   ├── 077-akida-validator-indirect-cycle-detection.md
│   ├── 078-backend-capabilities-inconsistencies.md
│   ├── 079-reduce-static-analysis-suppressions.md
│   ├── 08-plc0206-era001-dict-and-deadcode.md
│   ├── 080-integration-exporter-test-coverage-gaps.md
│   ├── 081-sinabs-traversal-deduplication.md
│   ├── 082-sinabs-rockpool-io-code-quality.md
│   ├── 09-npy002-numpy-random.md
│   ├── 10-ann-type-hints.md
│   ├── 10-neurocnl-shared-shell-theme-and-diagnostics.md
│   ├── 11-d417-docstring-args.md
│   ├── 11-neurocnl-shell-adapter-and-editor-workspace.md
│   ├── 12-neurocnl-export-and-handoff-desktop-surfaces.md
│   ├── 12-plc0415-inline-imports.md
│   ├── 13-neurostudio-cnl-canvas-live-sync.md
│   ├── 13-plr2004-magic-numbers.md
│   ├── 14-neurostudio-run-sim-play-button.md
│   ├── 14-plr0915-oversized-functions.md
│   ├── 23-opus-support-matrix-and-doc-truthfulness.md
│   ├── 24-opus-eliminate-production-stubs-and-fail-closed-unsupported-paths.md
│   ├── 25-sonnet-raise-core-quality-gates-toward-pre-beta.md
│   ├── 26-opus-end-to-end-pipeline-and-export-regression-suite.md
│   ├── 27-sonnet-replace-primary-workflow-ui-placeholders.md
│   ├── 28-opus-operational-hardening-for-jobs-logs-and-metrics.md
│   ├── 29-sonnet-pre-beta-packaging-versioning-and-install-smoke.md
│   ├── 30-opus-final-pre-beta-readiness-review.md
│   ├── NCNL-001-unblocked-issues-matrix-evaluation.md
│   ├── NCNL-002-auto-merge-syntax-error.md
│   ├── README.md
│   ├── semantics-implementation-order.md
│   ├── sent-046-akida-backend-capabilities.md
│   ├── sent-047-akida-cnl-parser-updates.md
│   ├── sent-050-lava-integration-plan.md
│   ├── sent-051-spinncloud-spinnaker2-exporter.md
│   ├── sent-052-synsense-sinabs-converter.md
│   ├── sent-053-synsense-rockpool-converter.md
│   ├── sent-054-pynq-z2-finn-compilation-target.md
│   ├── sent-055-fix-capabilities-syntax-error.md
│   ├── sent-056-docs-refresh-completion.md
│   ├── sent-057-loihi-planner-validator-integration.md
│   ├── sent-058-akida-capability-checker-topology.md
│   ├── sent-059-akida-validator-invariant-expansion.md
│   ├── sent-060-lava-runtime-validation.md
│   ├── sent-061-spinnaker2-constraint-validation.md
│   ├── sent-062-sinabs-direct-layer-mapping.md
│   ├── sent-063-rockpool-fix-import-and-converter.md
│   ├── sent-064-pynq-finn-exporter-implementation.md
│   ├── sent-akida-topological-drift.md
│   ├── sent-lava_integration.md
│   ├── sent-pynq_finn_integration.md
│   ├── sent-rockpool_integration.md
│   ├── sent-sinabs_integration.md
│   ├── sent-spinnaker-hardware-validation.md
│   └── spinnaker2_integration.md
├── jobs.db
├── jules-roadmap.md
├── logs
│   └── neurocnl.log
├── mkdocs.yml
├── neurocnl
│   ├── __init__.py
│   ├── _nir_compat.py
│   ├── backends
│   │   ├── __init__.py
│   │   ├── akida_capabilities.py
│   │   ├── capabilities.py
│   │   ├── lava_capabilities.py
│   │   ├── rockpool_capabilities.py
│   │   ├── sinabs_capabilities.py
│   │   ├── spinnaker2_capabilities.py
│   │   └── test_capabilities.py
│   ├── cnl
│   │   ├── __init__.py
│   │   ├── document.py
│   │   └── types.py
│   ├── compile.py
│   ├── conftest.py
│   ├── contracts
│   │   ├── __init__.py
│   │   ├── akida_deployment_contract.py
│   │   ├── akida_mapping_contract.py
│   │   ├── hardware_export.py
│   │   ├── neuron_params.py
│   │   ├── pipeline_contracts.py
│   │   ├── pynq_deployment_contract.py
│   │   ├── pynq_runtime_artifact_contract.py
│   │   ├── teensy_deployment_contract.py
│   │   ├── test_akida_deployment_contract.py
│   │   ├── test_contracts.py
│   │   ├── test_pynq_deployment_contract.py
│   │   └── test_pynq_runtime_artifact_contract.py
│   ├── converter
│   │   ├── __init__.py
│   │   ├── akida_adapter.py
│   │   ├── brian2_io.py
│   │   ├── brian2_runtime.py
│   │   ├── lava_io.py
│   │   ├── nengo_io.py
│   │   ├── pivot.py
│   │   ├── pynn_io.py
│   │   ├── rockpool_io.py
│   │   ├── run_conversion.py
│   │   ├── sinabs_io.py
│   │   ├── spinnaker2_io.py
│   │   ├── test_akida_adapter.py
│   │   ├── test_brian2_io.py
│   │   ├── test_lava_io.py
│   │   ├── test_rockpool.py
│   │   ├── test_rockpool_io.py
│   │   ├── test_sinabs_io.py
│   │   └── test_spinnaker2_io.py
│   ├── export
│   │   ├── c_header_exporter.py
│   │   ├── lava_exporter.py
│   │   ├── loihi_exporter.py
│   │   ├── neuroml_exporter.py
│   │   ├── nir_exporter.py
│   │   ├── pynq_exporter.py
│   │   ├── rockpool_exporter.py
│   │   ├── sinabs_exporter.py
│   │   ├── spinnaker2_exporter.py
│   │   ├── spinnaker_exporter.py
│   │   ├── test_lava_integration.py
│   │   ├── test_lava_sim_path.py
│   │   ├── test_pynq_exporter.py
│   │   ├── test_rockpool_exporter.py
│   │   ├── test_sinabs_exporter.py
│   │   └── test_spinnaker2_exporter.py
│   ├── generation
│   │   ├── __init__.py
│   │   ├── akida_generator.py
│   │   ├── assertion_generator.py
│   │   ├── test_akida_generator.py
│   │   └── test_assertion_generator.py
│   ├── handoff
│   │   ├── __init__.py
│   │   ├── dreamhand_learning_sync.py
│   │   ├── dreamhand_verification_hook.py
│   │   ├── neurochip_pynq_handoff.py
│   │   ├── neurochip_teensy_mapper.py
│   │   ├── neurosim_cnl_handoff.py
│   │   ├── test_dreamhand_learning_sync.py
│   │   ├── test_dreamhand_verification_hook.py
│   │   ├── test_neurochip_pynq_handoff.py
│   │   └── test_neurochip_teensy_mapper.py
│   ├── ir
│   │   ├── __init__.py
│   │   ├── lowering.py
│   │   ├── materializer.py
│   │   ├── metadata_schema.py
│   │   ├── test_ir_types.py
│   │   ├── test_metadata_schema.py
│   │   ├── test_timing_validator.py
│   │   ├── timing_validator.py
│   │   ├── topology.py
│   │   └── types.py
│   ├── layers
│   │   ├── __init__.py
│   │   ├── akida_validator.py
│   │   ├── layer1_invariants.py
│   │   ├── layer1_validator.py
│   │   ├── layer2_validator.py
│   │   ├── spinnaker2_validator.py
│   │   ├── teensy_validator.py
│   │   ├── test_akida_validator.py
│   │   ├── test_layer2_validator.py
│   │   └── test_teensy_validator.py
│   ├── locale
│   │   └── en.json
│   ├── logging_config.py
│   ├── mapping
│   │   ├── __init__.py
│   │   ├── akida_mapper.py
│   │   └── test_akida_mapper.py
│   ├── nir_cnl
│   │   ├── __init__.py
│   │   ├── compiler.py
│   │   ├── errors.py
│   │   ├── grammar_tables.py
│   │   ├── ir_types.py
│   │   ├── parser.py
│   │   ├── renderer.py
│   │   └── validator.py
│   ├── pipeline.py
│   ├── planner.py
│   ├── runtime
│   │   ├── __init__.py
│   │   ├── cnl_nodes.py
│   │   ├── lava_simulator.py
│   │   ├── nir_support.py
│   │   ├── sc_neurocore_simulator.py
│   │   ├── snntorch_simulator.py
│   │   ├── stimulus.py
│   │   ├── test_lava_simulator.py
│   │   ├── test_nir_support.py
│   │   ├── test_sc_neurocore_simulator.py
│   │   ├── test_snntorch_simulator.py
│   │   ├── test_snntorch_simulator_primitives.py
│   │   └── test_stimulus.py
│   ├── runtime_dependencies.py
│   ├── simulation
│   │   ├── __init__.py
│   │   ├── bptt.py
│   │   └── run_simulation.py
│   ├── spike_encoding.py
│   ├── spike_encoding.py.orig
│   ├── test_spike_encoding.py
│   ├── test_utils.py
│   ├── test_visualization.py
│   ├── tests
│   │   ├── README.md
│   │   ├── __init__.py
│   │   ├── conftest_training.py
│   │   ├── nir_native_cnl
│   │   │   ├── LEGACY_MANIFEST.md
│   │   │   ├── __init__.py
│   │   │   ├── _round_trip.py
│   │   │   ├── _strategies.py
│   │   │   ├── test_compiler_weight_init.py
│   │   │   ├── test_diagnostic_properties.py
│   │   │   ├── test_grammar_tables.py
│   │   │   ├── test_legacy_token_properties.py
│   │   │   ├── test_reference_fixtures.py
│   │   │   ├── test_renderer_examples.py
│   │   │   ├── test_round_trip_properties.py
│   │   │   ├── test_shape_properties.py
│   │   │   ├── test_static_repo_invariants.py
│   │   │   └── test_weight_init_properties.py
│   │   ├── properties
│   │   │   ├── __init__.py
│   │   │   ├── conftest.py
│   │   │   └── test_teensy_deployment_properties.py
│   │   ├── test_array_serialisation.py
│   │   ├── test_compile.py
│   │   ├── test_converter.py
│   │   ├── test_dataset_loader.py
│   │   ├── test_lazy_visualization_import.py
│   │   ├── test_logging_config.py
│   │   ├── test_nir_compat_metadata.py
│   │   ├── test_nir_to_cnl.py
│   │   ├── test_run_simulation.py
│   │   ├── test_teensy_deployment_contract.py
│   │   └── test_training_registry.py
│   ├── training
│   │   ├── 2026-05-11-neurotraining-factory-mission-plan.md
│   │   ├── __init__.py
│   │   ├── dataset_fixtures.py
│   │   ├── dataset_loader.py
│   │   ├── factory.py
│   │   ├── sleep_pes_adapter.py
│   │   └── snntorch_adapter.py
│   ├── training_api.py
│   ├── training_registry.py
│   ├── transforms
│   │   ├── quantise.py
│   │   └── test_quantise.py
│   ├── utils.py
│   └── visualization.py
├── neuromorphic_spec_plan.md
├── neurosim
│   ├── GUARDRAILS.md
│   ├── __init__.py
│   ├── app
│   │   ├── __init__.py
│   │   ├── backends
│   │   │   ├── __init__.py
│   │   │   └── spinnaker2_backend.py
│   │   ├── limiter.py
│   │   ├── main.py
│   │   ├── middleware
│   │   │   ├── __init__.py
│   │   │   └── logging.py
│   │   ├── routers
│   │   │   ├── __init__.py
│   │   │   ├── components.py
│   │   │   ├── custom_nodes.py
│   │   │   ├── export.py
│   │   │   ├── generation.py
│   │   │   ├── nir_canvas.py
│   │   │   ├── preview.py
│   │   │   ├── projects.py
│   │   │   ├── simulation_ws.py
│   │   │   ├── spinnaker2.py
│   │   │   ├── sweep.py
│   │   │   ├── templates.py
│   │   │   └── validation.py
│   │   ├── schemas
│   │   │   ├── __init__.py
│   │   │   ├── canvas.py
│   │   │   ├── components.py
│   │   │   ├── export.py
│   │   │   ├── preview.py
│   │   │   ├── projects.py
│   │   │   ├── runtime.py
│   │   │   ├── sweep.py
│   │   │   └── templates.py
│   │   ├── services
│   │   │   ├── __init__.py
│   │   │   ├── canonical_editor_projection.py
│   │   │   ├── cnl_to_graph.py
│   │   │   ├── components.py
│   │   │   ├── export_generators.py
│   │   │   ├── job_store.py
│   │   │   ├── nir_support.py
│   │   │   ├── preview_runner.py
│   │   │   ├── project_store.py
│   │   │   ├── spinnaker2_store.py
│   │   │   ├── sweep_runner.py
│   │   │   └── validation_service.py
│   │   └── utils
│   │       ├── __init__.py
│   │       └── logging.py
│   ├── components
│   │   ├── __init__.py
│   │   ├── encoders
│   │   │   ├── delta_encoder.json
│   │   │   ├── rate_encoder.json
│   │   │   └── temporal_encoder.json
│   │   ├── neurons
│   │   │   ├── adaptive_lif.json
│   │   │   └── lif_population.json
│   │   ├── patterns
│   │   │   ├── cpg_oscillator.json
│   │   │   ├── lateral_inhibition.json
│   │   │   ├── reflex_arc.json
│   │   │   └── winner_take_all.json
│   │   └── synapses
│   │       ├── pes_synapse.json
│   │       ├── static_synapse.json
│   │       └── stdp_synapse.json
│   ├── contracts
│   │   ├── __init__.py
│   │   ├── canonical_editor_contracts.py
│   │   ├── canvas_contracts.py
│   │   ├── design_contracts.py
│   │   ├── project_contracts.py
│   │   └── simulation_contracts.py
│   ├── templates
│   │   ├── __init__.py
│   │   ├── cpg_oscillator.json
│   │   └── reflex_arc.json
│   └── tests
│       ├── __init__.py
│       ├── conftest.py
│       ├── properties
│       │   ├── __init__.py
│       │   ├── test_design_properties.py
│       │   └── test_pbt_nir_type_round_trip.py
│       ├── routers
│       │   ├── __init__.py
│       │   ├── test_canvas_to_canonical.py
│       │   ├── test_components.py
│       │   ├── test_export.py
│       │   ├── test_generation.py
│       │   ├── test_generation_canonical.py
│       │   ├── test_main.py
│       │   ├── test_nir_to_cnl_endpoint.py
│       │   ├── test_projects.py
│       │   ├── test_rate_limiting.py
│       │   ├── test_simulation_ws.py
│       │   ├── test_simulations.py
│       │   ├── test_spinnaker2.py
│       │   ├── test_sweep_lifecycle.py
│       │   ├── test_tau_invariant.py
│       │   ├── test_templates.py
│       │   └── test_validation.py
│       ├── services
│       │   ├── __init__.py
│       │   ├── test_canonical_editor_projection.py
│       │   ├── test_cnl_precision.py
│       │   ├── test_graph_to_cnl.py
│       │   ├── test_neurocnl_bridge_bootstrap.py
│       │   ├── test_preview_runner.py
│       │   ├── test_project_to_canvas_nir_type.py
│       │   └── test_sweep_runner.py
│       ├── test_concurrency.py
│       ├── test_contracts.py
│       ├── test_integration.py
│       ├── test_neurocnl_integration.py
│       ├── test_preview_validation.py
│       ├── test_router_generation_endpoints.py
│       ├── test_simulation_integration.py
│       └── test_sweep_smoke_e2e.py
├── old_nir_importer_tab.dart
├── original_nir_importer_tab.dart
├── patch_nir.py
├── project_knowledge_base.md
├── projects.db
├── pyproject.toml
├── recent_commits.patch
├── requirements-neurotraining.txt
├── requirements-training-test.txt
├── scripts
│   └── poc_round_trip.py
├── server.log
├── simulation_report.json
├── sonnet-explains-cnl.md
├── test_stash_output.txt
├── tests
│   ├── e2e
│   │   ├── test_debug.py
│   │   ├── test_export_and_jobs.py
│   │   ├── test_pipeline_failure_flows.py
│   │   └── test_production_pipeline.py
│   ├── nir_native_cnl
│   │   ├── __init__.py
│   │   └── test_nir_validation.py
│   ├── test_backend_smoke.py
│   ├── test_install_smoke.py
│   ├── test_nir_compat.py
│   ├── test_nir_to_cnl.py
│   ├── test_notebook_kernels.py
│   └── test_sinabs_io.py
├── unimplemented_stubs.md
└── update_grammar.patch
</directory_structure>

## Remote Testing Configuration

For dev, `REMOTE_HOST=dev@<dev-host>` can be used. The server address is `<dev-host>`.

To run the app, use:
```
flutter run -d macos
```
This runs the Flutter macOS app directly, matching the end-user experience as closely as possible. Do not suggest or use `make docker-ex-m` or `scripts/run_dev.sh` — those workflows are no longer used.
