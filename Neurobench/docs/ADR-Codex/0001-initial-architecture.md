# ADR 0001: Initial Architecture of Neurobench

## Status
Accepted

## Context
Neuromorphic teams need evidence, not just successful runs. A model that "worked once" is not enough when the real questions are whether it regressed, whether it survives perturbations, whether another encoding works better, or whether the same network behaves differently on another target.

The current Neurobench repo is already structured around that idea:
- a FastAPI backend in `neurobench/app/`
- a Flutter frontend in `frontend/`
- benchmark manifests in `benchmarks/builtin/`
- service-layer orchestration in `app/services/`
- target-specific runners in `app/runners/`
- result, report, comparison, and robustness schemas in `app/schemas/`

The service layout shows the intended decomposition clearly:
- `benchmark_loader.py` for loading benchmark definitions
- `benchmark_runner.py` and `job_manager.py` for execution orchestration
- `result_store.py` and `report_generator.py` for durable evidence and reporting
- `diff_engine.py` and `regression_service.py` for baseline and regression logic
- `target_comparator.py`, `encoding_comparator.py`, `fault_sweeper.py`, and `perturbation_sweeper.py` for specialized comparison and robustness workflows

This module sits downstream of other toolkit modules. It consumes networks, recordings, baselines, and hardware-target context, but it should not become the place where those upstream concerns are reimplemented.

## Decision
We will establish Neurobench as the benchmarking, regression, and evidence-generation layer of the toolkit.

### Core architectural model

Neurobench is built around repeatable benchmark execution, not around ad hoc metric scripts.

The module should be understood as four stacked concerns:
- benchmark definitions and inputs
- execution orchestration
- result persistence and diffing
- reporting and comparison surfaces

### Ownership boundaries

Neurobench owns:
- benchmark catalogs and manifests
- running benchmark jobs
- storing benchmark results and baselines
- diffing current results against saved expectations
- robustness and perturbation sweeps
- comparison and report generation

Neurobench does not own:
- primary model authoring semantics, which belong to `neurocnl` and `Neurosim`
- hardware deployment logic, which belongs to `Neurochip`
- biosignal acquisition and artifact recording, which belong to `Neurosense`

It may consume outputs from those modules, but it should not absorb their responsibilities.

### Structural decomposition

Safe changes should preserve the current layered shape:
- routers define HTTP surfaces and request/response boundaries
- services implement benchmark logic and orchestration
- runners isolate target-specific execution details
- schemas and contracts protect result and report shape
- frontend surfaces the benchmark, diff, and report workflows without becoming the execution engine

Benchmark definitions should remain data-driven where possible. Built-in benchmark manifests and service orchestration should be favored over hardcoded flow embedded in API handlers.

### Architectural rules for safe change

Agents working in this repository should preserve these rules:
- Do not put benchmark business logic directly into routers when it belongs in services.
- Do not hardcode target behavior into generic benchmark flows; isolate target-specific work in runners or dedicated services.
- Do not let report generation become the source of truth for results; reports should summarize stored results, not invent them.
- Do not weaken baseline, diff, or regression semantics for convenience. Reproducibility is a core purpose of this module.
- Do not make Neurobench depend on private internals of other modules; consume stable inputs, artifacts, or APIs instead.

### Why it is built this way

The architecture is designed so the same benchmark can be rerun, compared, audited, exported, and discussed later. That only works if execution, storage, diffing, and reporting are explicit architectural layers instead of hidden side effects of a single script.

## Consequences
- Benchmark runs, regression checks, and cross-target comparisons can be executed through a consistent workflow instead of bespoke evaluation code.
- Result persistence and diffing become core architecture, which makes evidence review possible but adds operational state to manage.
- The module can compare simulation, hardware, encoding, and robustness behavior without taking over the authoring or deployment systems that produced those artifacts.
- New benchmark families can be added cleanly if they fit the manifest, service, runner, and result model; they become messy if they are added as one-off API exceptions.
- Benchmark credibility now depends on maintaining fixtures, metric definitions, baselines, and report logic with the same rigor as application code.
