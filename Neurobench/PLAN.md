# Implementation Plan for NeuroBench

## Goal
Implement the NeuroBench testing and benchmarking workbench according to `neurobench_spec.md`.

## Progress Summary
- Milestones 1-5 are complete (scaffolding, schemas, frontend shell, Data Layer, Business Logic).
- Most CLI, Docker, and tests are empty stubs.
- Next up: Milestone 6 (CLI Implementation).

---

## Milestones

### 1. Repository Structure (Completed)
Scaffold the basic directory layout for Python backend and Flutter frontend.

### 2. Backend API Foundations (Completed)
- [x] Pydantic models in `neurobench/app/schemas/` — `BenchmarkDefinition`, `BenchmarkResult`, `DiffResult`, `TargetComparisonResult`, `RobustnessCurve` all defined.
- [x] FastAPI app shell in `neurobench/app/main.py` with health check and all routers wired.
- [x] Stub routers for all 14 API endpoints (return 501 / empty lists).
- [x] `pyproject.toml` with FastAPI, Uvicorn, Pydantic dependencies.
- [ ] `schemas/reports.py` — empty, needs `ReportRequest`/`ReportResponse` models.

### 3. Frontend Application Shell (Completed)
- [x] `pubspec.yaml` with Riverpod, HTTP packages.
- [x] `app.dart` with Material theme.
- [x] `benchmark_screen.dart` with sidebar + main panel layout.
- [x] `benchmark_catalog.dart` — working ListView with selection.
- [x] `results_summary_card.dart` and `metric_diff_table.dart` — visual shells with hardcoded data.
- [x] Mock providers: `benchmarks_provider.dart`, `results_provider.dart`.

### 4. Data Layer & Storage (Completed)
- [x] Implement `result_store.py` — SQLite tables for results and baselines.
- [x] Implement benchmark JSON loader — read `neurobench/benchmarks/builtin/*.json`, register in catalog.
- [x] Fill remaining builtin benchmark JSONs (`spike_classification.json`, `wake_word_detection.json`, `pattern_recognition.json`).
- [x] Wire routers to use `result_store` for CRUD operations on results and baselines.

### 5. Business Logic & Services (Completed)
- [x] `benchmark_runner.py` — orchestrate: load network via `neurocnl`, simulate, score against assertions.
- [x] `diff_engine.py` — baseline comparison: compute deltas, classify improved/regressed/unchanged.
- [x] `fault_sweeper.py` — wrap `neurodreamhand` fault injection, sweep across rates, aggregate with CI.
- [x] `perturbation_sweeper.py` — input noise injection sweep.
- [x] `target_comparator.py` — call NeuroChip API for per-target quantization and metrics.
- [x] `encoding_comparator.py` — call NeuroSense API for encoding variant comparison.
- [x] `report_generator.py` — PDF/HTML report via reportlab/weasyprint.
- [x] Wire all routers to call real services instead of returning 501.

### 6. CLI Implementation ← NEXT
- [ ] `cli/__main__.py` — `neurobench run`, `neurobench compare`, `neurobench faults`, `neurobench report` commands.
- [ ] Wire CLI to call backend services directly (or HTTP).

### 7. Frontend Integration
- [ ] `api_client.dart` — HTTP client calling all backend endpoints.
- [ ] Replace mock providers with real API-backed providers.
- [ ] Implement remaining screens: `comparison_screen.dart`, `robustness_screen.dart`, `report_screen.dart`.
- [ ] Implement remaining widgets: `baseline_selector.dart`, `run_history_timeline.dart`, `target_comparison_grid.dart`, `robustness_curve_chart.dart`, `perturbation_curve_chart.dart`, `report_builder.dart`.

### 8. Infrastructure & Testing
- [ ] `Dockerfile` and `docker-compose.yml` for backend + frontend.
- [ ] Backend tests with `pytest` (schemas, routers, services).
- [ ] Frontend widget tests.
- [ ] CI/CD integration: `neurobench run` in pipeline.

### Note:
`issue_mocked_endpoints_implementation_plan.md` was deprecated as part of the POC readiness consolidation. All remaining logic is now tracked directly in this PLAN.md document.
