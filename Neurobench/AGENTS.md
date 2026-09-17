# Neurobench

Read first:
- `CODING_STYLE_GUIDE.md`
- `neurobench/pyproject.toml`
- `frontend/pubspec.yaml`
- `frontend/analysis_options.yaml`
- `neurobench_spec.md`
- `docs/ADR-Gemini/`, `docs/ADR-Codex/`, `docs/ADR-claude/`

Constraints:
- `neurobench/contracts/*.py` own request, report, comparison, regression, and robustness payloads; update contracts and contract tests before changing services or routers.
- Keep benchmark execution logic in `app/services/`; routers are transport only. If behavior changes, update service tests or property tests with it.
- Optional `simulation`, `reports`, `spinnaker2`, `synsense`, and `pynq` extras in `neurobench/pyproject.toml` must stay optional; core server startup must not depend on them.
- Any change to benchmark inputs or suite-visible result schemas requires reading the upstream or downstream owner first: `neurocnl`, `Neurosense`, or `Neurohub`.
- Verify touched surfaces with `cd neurobench && poetry run pytest -v --cov=app tests/`, `cd neurobench && poetry run ruff check .`, `cd neurobench && poetry run mypy --strict .`, and `cd ../frontend && flutter test`.

Do NOT:
- Encode benchmark or report schema changes only in frontend models.
- Make optional heavy dependencies mandatory just to satisfy a local code path.
- Move metric logic into routers or widget code.

## Shell mode

Primary screen uses `NmtkShellMode.command`. Pass `mode: NmtkShellMode.command` to `NmtkDesktopScaffold` (or `NmtkTopAppBar` in embedded mode). This is the default, but always pass it explicitly for clarity.

NeuroBench uses GoRouter (Pattern B from `UI_AUDIT_AND_FIX_PLAN.md §M.3`): `NmtkDesktopScaffold` wraps the router's navigator via `ShadApp.material.router`'s `builder:` callback. The `NmtkWorkspaceSwitcherBar` (Summary / Comparison / Reports / Robustness) lives inside the content area `child`, not in the top app bar. The utility panel width must use `NmtkShellTokens.of(context).utilityPanelWidth` — never a hardcoded pixel value.


---

## Pipeline Agent Directives

This document provides instructions and context for AI agents (like Jules) working on the Neurobench project. Neurobench is a testing and benchmarking workbench for evaluating Spiking Neural Network (SNN) performance.

## 🏗 Project Architecture

Neurobench is divided into two main components:

1.  **Backend (`neurobench/`):** A FastAPI-based Python application that handles benchmark execution, data persistence, and result analysis.
    - `app/`: Contains the FastAPI application, routers, schemas, and services.
    - `contracts/`: Pydantic models defining the core data contracts for benchmarks and results.
    - `cli/`: Click-based CLI for running benchmarks from the command line.
    - `benchmarks/`: JSON definitions for built-in and custom benchmarks.
2.  **Frontend (`frontend/`):** A Flutter application for visualizing benchmark results, comparing targets, and managing benchmarks.

## 🛠 Tech Stack

- **Backend:** Python 3.11+, FastAPI, Pydantic v2, SQLite, Poetry, Pytest, Hypothesis.
- **Frontend:** Flutter, Dart, Riverpod (state management).
- **External Libraries:** `neurocnl` (simulation), `nengo`, `numpy`, `mujoco`.

## 🤖 General Instructions for Agents

1.  **Read the Style Guide:** Always adhere to the global coding standards defined in `CODING_STYLE_GUIDE.md` at the repository root.
2.  **Contract-First Development:** When modifying benchmark data structures, always start with the Pydantic contracts in `neurobench/contracts/`.
3.  **Strict Typing:** Maintain strict typing in both Python (MyPy) and Dart. Avoid `Any` and `dynamic` wherever possible.
4.  **Property-Based Testing:** Use `hypothesis` for testing complex logic, especially for data validation and metric calculations.
5.  **Simulations:** Understand that the `BenchmarkRunner` interacts with `neurocnl` to execute real SNN simulations.

## 🚀 Development Workflows

### Backend
- **Install dependencies:** `cd neurobench && poetry install`
- **Run tests:** `cd neurobench && poetry run pytest -v --cov=app tests/`
- **Linting:** `cd neurobench && poetry run ruff check .`
- **Type checking:** `cd neurobench && poetry run mypy --strict .`

### Frontend
- **Install dependencies:** `cd frontend && flutter pub get`
- **Run analysis:** `cd frontend && flutter analyze`
- **Run tests:** `cd frontend && flutter test`

## 🧩 Key Directories

- `neurobench/app/routers/`: API endpoints.
- `neurobench/app/services/`: Business logic and core services (e.g., `benchmark_runner.py`).
- `neurobench/contracts/`: Shared data models.
- `frontend/lib/providers/`: Riverpod state management logic.
- `frontend/lib/screens/`: Flutter UI screens.

<directory_structure>
├── AGENTS.md
├── CHANGELOG.md
├── Dockerfile
├── LICENSE
├── Makefile
├── PLAN.md
├── README.md
├── SECURITY.md
├── UI migration.md
├── docker-compose.yml
├── docs
│   ├── ADR-Codex
│   │   └── 0001-initial-architecture.md
│   ├── ADR-Gemini
│   │   ├── 0001-initial-architecture.md
│   │   └── 0002-standardized-metrics-schema.md
│   ├── ADR-claude
│   │   ├── 0001-standardized-metrics-framework.md
│   │   ├── 0002-pluggable-hardware-backends.md
│   │   ├── 0003-regression-detection-engine.md
│   │   ├── 0004-report-generation.md
│   │   └── 0005-robustness-testing.md
│   ├── api_reference.md
│   ├── archive
│   │   ├── 02-Apr-2026-status-Jules.md
│   │   ├── integration
│   │   │   └── synsense_integration_plan.md
│   │   ├── pynq_integration_plan.md
│   │   └── spinnaker2_integration_plan.md
│   ├── data-generation
│   │   ├── NSBI_execution_guide.md
│   │   └── synthetic_dataset_generation_plan.md
│   ├── developer
│   │   └── adding_new_metric.md
│   ├── unified-dev-pipeline
│   │   └── neurobench
│   │       └── GUARDRAILS.md
│   └── user
│       └── running_first_benchmark.md
├── frontend
│   ├── LICENSE
│   ├── README.md
│   ├── analysis_options.yaml
│   ├── build_error.txt
│   ├── dart_test.yaml
│   ├── integration_test
│   │   └── e2e_test.dart
│   ├── lib
│   │   ├── app.dart
│   │   ├── main.dart
│   │   ├── models
│   │   │   ├── benchmark.dart
│   │   │   ├── benchmark_job.dart
│   │   │   ├── result.dart
│   │   │   ├── workbench_tab.dart
│   │   │   ├── workspace_destination.dart
│   │   │   └── workspace_route_state.dart
│   │   ├── providers
│   │   │   ├── benchmarks_provider.dart
│   │   │   ├── benchmarks_provider.g.dart
│   │   │   ├── compare_selection_provider.dart
│   │   │   ├── compare_selection_provider.g.dart
│   │   │   ├── dismissed_job_provider.dart
│   │   │   ├── dismissed_job_provider.g.dart
│   │   │   ├── execution_provider.dart
│   │   │   ├── execution_provider.g.dart
│   │   │   └── results_provider.dart
│   │   ├── screens
│   │   │   ├── benchmark_screen.dart
│   │   │   ├── comparison_screen.dart
│   │   │   ├── regression_trends_screen.dart
│   │   │   ├── report_screen.dart
│   │   │   ├── robustness_screen.dart
│   │   │   └── workbench_shell.dart
│   │   ├── services
│   │   │   └── api_client.dart
│   │   ├── shell_adapter.dart
│   │   └── widgets
│   │       ├── active_jobs_bar.dart
│   │       ├── baseline_selector.dart
│   │       ├── benchmark_catalog.dart
│   │       ├── benchmark_header_card.dart
│   │       ├── benchmark_results_table.dart
│   │       ├── benchmark_run_form.dart
│   │       ├── benchmark_workbench_tabs.dart
│   │       ├── comparison_workspace.dart
│   │       ├── metric_diff_table.dart
│   │       ├── neurobench_mobile_wizard.dart
│   │       ├── perturbation_curve_chart.dart
│   │       ├── report_builder.dart
│   │       ├── results_summary_card.dart
│   │       ├── robustness_curve_chart.dart
│   │       ├── run_history_timeline.dart
│   │       ├── target_comparison_grid.dart
│   │       └── trend_chart.dart
│   ├── pubspec.lock
│   ├── pubspec.yaml
│   ├── test
│   │   ├── api_exception_test.dart
│   │   ├── api_integration_test.dart
│   │   ├── execution_flow_test.dart
│   │   ├── governance
│   │   │   └── material_icons_audit_test.dart
│   │   ├── models
│   │   │   └── result_test.dart
│   │   ├── navigation_test.dart
│   │   ├── test_helpers.dart
│   │   ├── widget_test.dart
│   │   └── widgets
│   │       ├── active_jobs_bar_test.dart
│   │       ├── benchmark_run_form_test.dart
│   │       ├── perturbation_curve_chart_test.dart
│   │       ├── report_builder_test.dart
│   │       ├── robustness_curve_chart_test.dart
│   │       ├── run_history_timeline_no_nested_cards_test.dart
│   │       ├── run_history_timeline_test.dart
│   │       ├── target_comparison_grid_test.dart
│   │       └── trend_chart_test.dart
│   └── web
│       ├── favicon.png
│       ├── icons
│       │   ├── Icon-192.png
│       │   ├── Icon-512.png
│       │   ├── Icon-maskable-192.png
│       │   └── Icon-maskable-512.png
│       ├── index.html
│       └── manifest.json
├── issues-archive
│   ├── 001-beta-implement-benchmark-create-endpoint-remove-501.md
│   ├── 001-hardware-benchmark-integration.md
│   ├── 001-spinncloud-spinnaker2-benchmarking.md
│   ├── 002-beta-fix-benchmark-fixtures-and-baseline-selector-typing.md
│   ├── 002-synsense-dynapcnn-benchmarking.md
│   ├── 002a-cloud-runner-schema.md
│   ├── 002b-cloud-orchestration-agent.md
│   ├── 003-beta-add-real-benchmark-execution-integration-smoke.md
│   ├── 003-pynq-z2-energy-power-benchmarking.md
│   ├── 003-wire-neurobench-verification-toggle.md
│   ├── 004-replace-pynq-placeholder-result-and-power-trace-endpoints.md
│   ├── 005-define-deterministic-karpathy-triplets.md
│   ├── 006-beta-rate-limiting.md
│   ├── 007-beta-authentication-layer.md
│   ├── 008-beta-structured-logging.md
│   ├── 009-beta-real-benchmark-execution.md
│   ├── 01-f811-redefined-names.md
│   ├── 010-beta-diff-engine-enhancements.md
│   ├── 011-beta-security-md-and-changelog-md.md
│   ├── 012-prod-end-to-end-integration-tests.md
│   ├── 013-prod-report-generation-system.md
│   ├── 014-prod-container-hardening.md
│   ├── 015-prod-regression-testing-framework.md
│   ├── 016-prod-user-documentation.md
│   ├── 02-plw0602-global-state.md
│   ├── 03-arg001-unused-router-args.md
│   ├── 04-g004-try401-logging.md
│   ├── 05-pt011-pytest-raises-match.md
│   ├── 06-pth-pathlib-modernization.md
│   ├── 07-sim117-nested-with.md
│   ├── 08-plc0206-era001-dict-and-deadcode.md
│   ├── 09-npy002-numpy-random.md
│   ├── 10-ann-type-hints.md
│   ├── 10-neurobench-shared-shell-theme-and-results-summary.md
│   ├── 11-d417-docstring-args.md
│   ├── 11-neurobench-shell-adapter-and-comparison-workspace.md
│   ├── 12-neurobench-job-setup-and-execution-controls.md
│   ├── 12-plc0415-inline-imports.md
│   ├── 13-plr2004-magic-numbers.md
│   ├── 14-plr0915-oversized-functions.md
│   ├── NBENCH-001-outdated-actions.md
│   ├── NBENCH-002-benchmark-runner-hardware-stubs.md
│   ├── NBENCH-003-fault-sweeper-real-implementation.md
│   ├── NBENCH-004-perturbation-sweeper-real-implementation.md
│   ├── NBENCH-005-encoding-comparator-real-implementation.md
│   ├── NBENCH-006-target-comparator-real-implementation.md
│   ├── NBENCH-007-spike-fidelity-edge-cases.md
│   ├── NBENCH-008-diff-engine-tolerance-edge-cases.md
│   ├── NBENCH-009-pydantic-contract-enforcement.md
│   ├── NBENCH-010-json-export-serialization.md
│   ├── sent-pynq_benchmarking_integration.md
│   └── sent-spinnaker2_benchmarking_integration.md
├── neurobench
│   ├── GUARDRAILS.md
│   ├── LICENSE
│   ├── app
│   │   ├── __init__.py
│   │   ├── auth.py
│   │   ├── config.py
│   │   ├── exceptions.py
│   │   ├── limiter.py
│   │   ├── logging_config.py
│   │   ├── main.py
│   │   ├── routers
│   │   │   ├── __init__.py
│   │   │   ├── baselines.py
│   │   │   ├── benchmarks.py
│   │   │   ├── comparison.py
│   │   │   ├── faults.py
│   │   │   ├── perturbation.py
│   │   │   ├── pynq.py
│   │   │   ├── regression.py
│   │   │   ├── reports.py
│   │   │   ├── results.py
│   │   │   ├── runner.py
│   │   │   ├── spinnaker2.py
│   │   │   └── synsense.py
│   │   ├── runners
│   │   │   ├── pynq_runner.py
│   │   │   ├── spinnaker2_runner.py
│   │   │   └── synsense_runner.py
│   │   ├── schemas
│   │   │   ├── __init__.py
│   │   │   ├── benchmarks.py
│   │   │   ├── common.py
│   │   │   ├── comparison.py
│   │   │   ├── reports.py
│   │   │   ├── results.py
│   │   │   └── robustness.py
│   │   ├── services
│   │   │   ├── __init__.py
│   │   │   ├── benchmark_loader.py
│   │   │   ├── benchmark_markdown_report.py
│   │   │   ├── benchmark_runner.py
│   │   │   ├── cross_platform_validation.py
│   │   │   ├── diff_engine.py
│   │   │   ├── encoding_comparator.py
│   │   │   ├── fault_sweeper.py
│   │   │   ├── job_manager.py
│   │   │   ├── metric_normalizer.py
│   │   │   ├── neurobench_executor.py
│   │   │   ├── neurosense_artifact.py
│   │   │   ├── perturbation_sweeper.py
│   │   │   ├── regression_service.py
│   │   │   ├── report_generator.py
│   │   │   ├── result_store.py
│   │   │   ├── seed_published_results.py
│   │   │   └── target_comparator.py
│   │   └── templates
│   │       └── report.html
│   ├── benchmarks
│   │   └── builtin
│   │       ├── auto_radar.json
│   │       ├── dvs_gesture.json
│   │       ├── ecg_classification.json
│   │       ├── grip_stability.json
│   │       ├── keyword_spotting.json
│   │       ├── mackey_glass.json
│   │       ├── nehar.json
│   │       ├── neurosense_replay_contract.json
│   │       ├── primate_reaching.json
│   │       └── ptb_lm.json
│   ├── cli
│   │   └── __main__.py
│   ├── contracts
│   │   ├── __init__.py
│   │   ├── benchmark_contracts.py
│   │   ├── comparison_contracts.py
│   │   ├── regression_contracts.py
│   │   ├── report_contracts.py
│   │   └── robustness_contracts.py
│   ├── data
│   │   └── reports
│   │       ├── rep_013a4919.html
│   │       ├── rep_58c4e53a.html
│   │       ├── rep_7536d3f7.json
│   │       ├── rep_85687c15.json
│   │       ├── rep_e7012839.html
│   │       └── rep_ead6c506.json
│   ├── neurobench.sqlite
│   ├── poetry.toml
│   ├── pyproject.toml
│   ├── reports
│   │   ├── rep_01a162a4.json
│   │   ├── rep_0283e563.html
│   │   ├── rep_27ceb33f.json
│   │   ├── rep_30d01f8d.html
│   │   ├── rep_4ae5da94.html
│   │   ├── rep_5c0cde54.json
│   │   ├── rep_6125611e.json
│   │   ├── rep_62bd53c7.html
│   │   ├── rep_69afc042.html
│   │   ├── rep_7386850a.json
│   │   ├── rep_8b97da06.html
│   │   ├── rep_972eef11.json
│   │   ├── rep_c755c648.json
│   │   └── rep_d7e760cf.json
│   ├── tests
│   │   ├── FIXTURES.md
│   │   ├── __init__.py
│   │   ├── conftest.py
│   │   ├── properties
│   │   │   ├── __init__.py
│   │   │   ├── strategies.py
│   │   │   ├── test_benchmark_properties.py
│   │   │   ├── test_regression_properties.py
│   │   │   └── test_robustness_properties.py
│   │   ├── services
│   │   │   └── test_target_comparator.py
│   │   ├── test_auth.py
│   │   ├── test_benchmark_markdown_report.py
│   │   ├── test_benchmark_runner_hardware.py
│   │   ├── test_contracts.py
│   │   ├── test_cross_platform_validation.py
│   │   ├── test_data.npy
│   │   ├── test_diff_engine.py
│   │   ├── test_dummy.py
│   │   ├── test_encoding_comparator.py
│   │   ├── test_fault_sweeper.py
│   │   ├── test_metric_normalizer.py
│   │   ├── test_network.cnl
│   │   ├── test_neurosense_artifact_service.py
│   │   ├── test_perturbation_sweeper.py
│   │   ├── test_rate_limiting.py
│   │   ├── test_real_benchmarks.py
│   │   ├── test_regression_service.py
│   │   ├── test_report_generator.py
│   │   ├── test_result_store.py
│   │   ├── test_router_core.py
│   │   ├── test_router_results_comp.py
│   │   ├── test_router_robustness_reports.py
│   │   ├── test_schemas.py
│   │   ├── test_service_data.py
│   │   ├── test_service_logic.py
│   │   ├── test_service_stubs.py
│   │   └── test_smoke.py
│   └── uv.lock
├── neurobench.sqlite
├── neurobench_functional_testing_guide.md
├── neurobench_spec.md
├── reports
│   ├── rep_1b0d34d5.html
│   └── rep_7c3ea763.json
└── scripts
    └── generate_all_datasets.sh
</directory_structure>

## Remote Testing Configuration

For dev, `REMOTE_HOST=dev@<dev-host>` can be used. For example, when the agent wants to test run the app, you can use `<dev-host>` as the server address.
