# Neurochip

Read first:
- `CODING_STYLE_GUIDE.md`
- `pyproject.toml`
- `neurochip_spec.md`
- `docs/ADR-Gemini/`, `docs/ADR-Codex/`, `docs/ADR-claude/`

Constraints:
- `neurochip/contracts/*.py` own deployment, runtime-artifact, hardware, and quantization payloads; update contracts and contract tests before changing router or service behavior.
- Keep PYNQ, Akida, and Lava paths optional exactly as modeled in `pyproject.toml`; default startup and default tests must not require hardware-only imports.
- Any change to deploy manifests, exported artefacts, serial-flash behavior, or target metadata requires reading the consumer first: `neurocnl`, `Neuro-Dream-Hand`, or `Neurohub`.
- Hardware-affecting changes need mock, property, or simulated verification in the same change. Do not ship a firmware or flash-path edit backed only by manual reasoning.
- Verify touched surfaces with `cd Neurochip && poetry run pytest neurochip/tests -q`, `cd Neurochip && poetry run ruff check .`, and `cd Neurochip && poetry run mypy .`.

## Frontend Ownership

The NeuroChip frontend is integrated into CNL Studio, not this repository.

Do NOT edit `frontend/` for product work. It is only an IDE stub.

- Deployment UI: `neurocnl/frontend/lib/features/deploy/`
- Shared PYNQ models: `nmtk_ui_core/lib/models/pynq_deployment_model.dart`
- Verification: run CNL Studio frontend tests when frontend deployment contracts move

Do NOT:
- Hardcode serial ports, board availability, or machine-local paths.
- Pull optional hardware imports into code paths exercised by default tests or server startup.
- Change deployment field names or checksum semantics in one layer only.

## Shell mode

Primary screen uses `NmtkShellMode.instrument`. Pass `mode: NmtkShellMode.instrument` to `NmtkDesktopScaffold` (or `NmtkTopAppBar` in embedded mode). Do not use `.command` or `.studio`.

`ThemeMode` must be `ThemeMode.dark` — not `ThemeMode.system`. The module theme seed must be `0xFF0891B2` (cyan) to avoid collision with `NmtkShellTokens.degradedColor` (amber). Do not use the amber seed `0xFFD97706`.

The active hardware target must always be visible in the shell chrome (as a `headerActions` badge), not only on the target gallery screen. The deployment log belongs in an `NmtkBottomDock` panel alongside the deploy controls, not as a standalone route.


---

## Pipeline Agent Directives

## Project Context
NeuroChip is a dedicated tool for compiling, constraining, and deploying Spiking Neural Network (SNN) models to neuromorphic chips and embedded microcontrollers. It targets neuroscience researchers and SNN algorithm developers, focusing on:
- Hardware targets: Teensy 4.1, Intel Loihi 2, BrainChip Akida, SpiNNaker, and BrainScaleS.
- Core functions: Target selection, constraint analysis, quantization explorer, fault injection, and firmware generation (Teensy/Loihi).

## Agentic Workflow Principles
To optimize for AI agents, developers must adhere to the following principles:

1.  **Strong Typing is Mandatory**: Always use explicit type annotations in both Python (FastAPI/Pydantic) and Dart (Flutter). Agents rely on type signatures to prevent hallucinations.
2.  **Small, Focused Files**: Keep files under 500 lines to fit within agent context windows. Split large files into smaller, logically grouped modules.
3.  **Descriptive, Verbose Naming**: Avoid abbreviations (e.g., use `calculate_neuron_activation` instead of `calc_nrn_act`).
4.  **"Why" over "What" Comments**: Use comments to explain business logic or workarounds that aren't immediately obvious from the code itself.
5.  **Standardized Docstrings**: Every public function, class, and method MUST have a docstring (Google Style for Python, Dartdoc `///` for Flutter).
6.  **Predictable Architecture**: Follow established patterns (e.g., FastAPI routers/services/schemas, Riverpod providers/models/widgets).

## Development Commands
- **Backend (Python)**:
    - Install: `cd neurochip && poetry install`
    - Test: `cd neurochip && PYTHONPATH=.. poetry run pytest tests/`
    - Lint/Format: `cd neurochip && poetry run ruff check . --fix && poetry run ruff format .`
    - Type Check: `cd neurochip && poetry run mypy .`
- **Frontend (Flutter)**:
    - Install: `cd frontend && flutter pub get`
    - Test: `cd frontend && flutter test`
    - Analyze: `cd frontend && dart analyze`

<directory_structure>
├── AGENTS.md
├── Dockerfile
├── HARDWARE_TESTING.md
├── LICENSE
├── Makefile
├── NEUROCHIP_TESTING_GUIDE.md
├── PLAN.md
├── README.md
├── UI migration.md
├── docker-compose.yml
├── docs
│   ├── ADR-Codex
│   │   └── 0001-initial-architecture.md
│   ├── ADR-Gemini
│   │   ├── 0001-initial-architecture.md
│   │   ├── 0002-hardware-profile-manifests.md
│   │   ├── 0003-subprocess-firmware-toolchains.md
│   │   └── 0004-install-status-json-permissions.md
│   ├── ADR-claude
│   │   ├── 0001-multi-vendor-hardware-abstraction.md
│   │   ├── 0002-contract-driven-development.md
│   │   ├── 0003-optional-api-key-authentication.md
│   │   ├── 0004-file-based-storage.md
│   │   ├── 0005-sitl-verification.md
│   │   ├── 0006-docker-multi-stage-build.md
│   │   ├── 0007-network-partitioner.md
│   │   ├── 0008-compilation-artifact-caching.md
│   │   ├── 0009-code-generator-selection.md
│   │   └── 0010-pynq-word-mmio-overlay-contract.md
│   ├── AKIDA_INTEGRATION_PLAN.md
│   ├── CODE_REVIEW_CRITICAL_2026-05-14.md
│   ├── HARDWARE_COMPATIBILITY.md
│   ├── SPECK2_IMPLEMENTATION.md
│   ├── SpiNNaker2_Integration_Plan.md
│   ├── archive
│   │   └── lava_integration_plan.md
│   ├── neurochip
│   │   ├── api_reference.md
│   │   ├── developer_guide.md
│   │   ├── pynq_z2_deployment_guide.md
│   │   ├── quantization_guide.md
│   │   └── user_guide.md
│   └── unified-dev-pipeline
│       └── neurochip
│           └── GUARDRAILS.md
├── frontend
│   └── neurochip.iml
├── hardware
│   └── pynq_z2
│       ├── README.md
│       ├── hls
│       │   ├── build_hls.tcl
│       │   ├── snn_overlay_engine.cpp
│       │   └── snn_overlay_engine.hpp
│       ├── overlay_manifest.json
│       ├── rtl
│       │   └── README.md
│       ├── scripts
│       │   ├── build_overlay.sh
│       │   ├── stage_overlay.sh
│       │   ├── vitis_hls.log
│       │   ├── vivado.jou
│       │   ├── vivado.log
│       │   ├── vivado_67372.backup.jou
│       │   ├── vivado_67372.backup.log
│       │   ├── vivado_67808.backup.jou
│       │   ├── vivado_67808.backup.log
│       │   ├── vivado_78687.backup.jou
│       │   ├── vivado_78687.backup.log
│       │   ├── vivado_79122.backup.jou
│       │   ├── vivado_79122.backup.log
│       │   ├── vivado_79607.backup.jou
│       │   ├── vivado_79607.backup.log
│       │   └── xcd.log
│       └── vivado
│           └── build_overlay.tcl
├── issues-archive
│   ├── 001-beta-implement-lava-and-neuroml-export-routes.md
│   ├── 001-lava-loihi2-hardware-backend.md
│   ├── 001-teensy-real-hardware-validation.md
│   ├── 002-beta-add-contract-tests-for-real-export-artifacts.md
│   ├── 002-contract-version-pinning.md
│   ├── 002-spinncloud-spinnaker2-interfacing.md
│   ├── 003-brainchip-akida-sdk-integration.md
│   ├── 003-pynq-z2-finn-compilation.md
│   ├── 004-beta-rate-limiting.md
│   ├── 004-fix-teensy-serial-port-backend-contract.md
│   ├── 004-pynq-z2-fpga-deployment.md
│   ├── 005-beta-authentication-layer.md
│   ├── 005-post-flash-runtime-verification-fallback.md
│   ├── 006-beta-structured-logging.md
│   ├── 007-beta-simulated-hardware-verification.md
│   ├── 008-beta-quantization-explorer-enhancements.md
│   ├── 009-beta-security-md-and-changelog-md.md
│   ├── 01-akida-neurochip-server-fix.md
│   ├── 01-f811-redefined-names.md
│   ├── 010-prod-end-to-end-integration-tests.md
│   ├── 011-prod-real-hardware-testing.md
│   ├── 012-prod-container-hardening.md
│   ├── 013-prod-compilation-performance.md
│   ├── 014-prod-user-documentation.md
│   ├── 02-plw0602-global-state.md
│   ├── 03-arg001-unused-router-args.md
│   ├── 04-g004-try401-logging.md
│   ├── 05-pt011-pytest-raises-match.md
│   ├── 06-pth-pathlib-modernization.md
│   ├── 07-sim117-nested-with.md
│   ├── 08-plc0206-era001-dict-and-deadcode.md
│   ├── 09-npy002-numpy-random.md
│   ├── 10-ann-type-hints.md
│   ├── 10-neurochip-shared-shell-theme-and-deploy-status.md
│   ├── 11-d417-docstring-args.md
│   ├── 11-neurochip-shell-adapter-and-target-configuration.md
│   ├── 12-neurochip-flash-and-hardware-action-surfaces.md
│   ├── 12-plc0415-inline-imports.md
│   ├── 13-plr2004-magic-numbers.md
│   ├── 14-plr0915-oversized-functions.md
│   ├── fix-e2e-full-pipeline-success-test.md
│   ├── fix-flash-pipeline-test-pio-mock.md
│   ├── fix-property-test-bit-width-name-error.md
│   ├── fix-rate-limit-response-headers.md
│   ├── sent-akida_sdk_integration.md
│   ├── sent-lava_hardware_integration.md
│   ├── sent-spinnaker2_interfacing_integration.md
│   ├── test-core-count-boundary-schema-validation.md
│   ├── test-deployment-manifest-field-completeness.md
│   ├── test-export-router-exception-handling.md
│   ├── test-fault-runner-edge-cases.md
│   ├── test-flash-service-subprocess-paths.md
│   ├── test-loihi-generator-coverage.md
│   ├── test-oversized-network-constraint-report.md
│   ├── test-quantization-router-coverage.md
│   ├── test-targets-router-error-paths.md
│   └── test-teensy-generator-coverage.md
├── neurochip
│   ├── CHANGELOG.md
│   ├── GUARDRAILS.md
│   ├── SECURITY.md
│   ├── __init__.py
│   ├── _compat.py
│   ├── app
│   │   ├── __init__.py
│   │   ├── auth.py
│   │   ├── limiter.py
│   │   ├── main.py
│   │   ├── pynq_agent.py
│   │   ├── routers
│   │   │   ├── __init__.py
│   │   │   ├── akida.py
│   │   │   ├── analysis.py
│   │   │   ├── deployments.py
│   │   │   ├── estimation.py
│   │   │   ├── export.py
│   │   │   ├── faults.py
│   │   │   ├── lava.py
│   │   │   ├── pynq.py
│   │   │   ├── quantization.py
│   │   │   ├── serial.py
│   │   │   ├── speck.py
│   │   │   ├── spinnaker2.py
│   │   │   └── targets.py
│   │   ├── schemas
│   │   │   ├── __init__.py
│   │   │   ├── analysis.py
│   │   │   ├── deployments.py
│   │   │   ├── estimation.py
│   │   │   ├── faults.py
│   │   │   ├── health.py
│   │   │   ├── quantization.py
│   │   │   ├── runtime.py
│   │   │   └── targets.py
│   │   ├── services
│   │   │   ├── __init__.py
│   │   │   ├── akida_backend.py
│   │   │   ├── akida_errors.py
│   │   │   ├── akida_generator.py
│   │   │   ├── akida_simulator.py
│   │   │   ├── brainscales_generator.py
│   │   │   ├── cache_manager.py
│   │   │   ├── constraint_analyzer.py
│   │   │   ├── deployment_store.py
│   │   │   ├── fault_runner.py
│   │   │   ├── flash_service.py
│   │   │   ├── lava_backend.py
│   │   │   ├── lava_generator.py
│   │   │   ├── loihi_generator.py
│   │   │   ├── neuroml_generator.py
│   │   │   ├── partitioner.py
│   │   │   ├── power_estimator.py
│   │   │   ├── pynq_backend.py
│   │   │   ├── pynq_compiler.py
│   │   │   ├── pynq_errors.py
│   │   │   ├── pynq_generator.py
│   │   │   ├── pynq_install_status.py
│   │   │   ├── pynq_loop_manager.py
│   │   │   ├── pynq_overlay_assets.py
│   │   │   ├── pynq_overlay_manifest.py
│   │   │   ├── pynq_simulator.py
│   │   │   ├── pynq_sitl_verifier.py
│   │   │   ├── pynq_worker.py
│   │   │   ├── quantizer.py
│   │   │   ├── speck_backend.py
│   │   │   ├── speck_compiler.py
│   │   │   ├── speck_errors.py
│   │   │   ├── speck_samna_runtime.py
│   │   │   ├── speck_simulator.py
│   │   │   ├── spinnaker2_backend.py
│   │   │   ├── spinnaker_generator.py
│   │   │   └── teensy_generator.py
│   │   └── utils
│   │       ├── __init__.py
│   │       └── provenance.py
│   ├── contracts
│   │   ├── __init__.py
│   │   ├── akida_runtime_contract.py
│   │   ├── deployment_contracts.py
│   │   ├── estimation_contracts.py
│   │   ├── fault_contracts.py
│   │   ├── hardware_contracts.py
│   │   ├── pynq_runtime_artifact_contract.py
│   │   ├── quantization_contracts.py
│   │   ├── speck_runtime_contract.py
│   │   └── teensy_deployment_contract.py
│   ├── deployments.db
│   ├── docs
│   │   └── pynq_z2_integration_plan.md
│   ├── firmware_templates
│   │   ├── loihi
│   │   │   ├── config.json.j2
│   │   │   └── deploy.py.j2
│   │   └── teensy
│   │       ├── lif_engine.h.j2
│   │       ├── main.ino.j2
│   │       ├── network_params.h.j2
│   │       └── platformio.ini.j2
│   ├── overlays
│   │   └── README.md
│   ├── provisioning
│   │   ├── __init__.py
│   │   ├── akida_host_bundle.py
│   │   ├── pynq_agent_bundle.py
│   │   ├── pynq_agent_launch.py
│   │   └── pynq_overlay_package.py
│   ├── pytest_output.txt
│   ├── scripts
│   │   └── stress_test_flash.py
│   ├── targets
│   │   ├── akida.json
│   │   ├── brainscales.json
│   │   ├── loihi2.json
│   │   ├── pynq_z2.json
│   │   ├── speck2.json
│   │   ├── spinnaker.json
│   │   ├── spinnaker2.json
│   │   └── teensy41.json
│   └── tests
│       ├── mock_teensy.py
│       ├── properties
│       │   ├── __init__.py
│       │   ├── test_contract_properties.py
│       │   ├── test_deployment_properties.py
│       │   ├── test_pynq_runtime_properties.py
│       │   └── test_quantization_properties.py
│       ├── test_akida_backend.py
│       ├── test_akida_runtime_contract.py
│       ├── test_akida_ssrf.py
│       ├── test_akida_ws_stream.py
│       ├── test_analysis_router.py
│       ├── test_artifact_contracts.py
│       ├── test_auth.py
│       ├── test_cache_manager.py
│       ├── test_constraint_analyzer.py
│       ├── test_constraint_e2e.py
│       ├── test_contracts.py
│       ├── test_cors.py
│       ├── test_deployment_store.py
│       ├── test_e2e.py
│       ├── test_export_router.py
│       ├── test_export_ws.py
│       ├── test_fault_runner.py
│       ├── test_flash_service.py
│       ├── test_generators.py
│       ├── test_hardware_pipeline.py
│       ├── test_lava.py
│       ├── test_loihi_generator.py
│       ├── test_main.py
│       ├── test_partitioner.py
│       ├── test_power_estimator.py
│       ├── test_provenance.py
│       ├── test_pynq_agent_app.py
│       ├── test_pynq_agent_bundle.py
│       ├── test_pynq_backend.py
│       ├── test_pynq_compile.py
│       ├── test_pynq_loop.py
│       ├── test_pynq_overlay_build_scripts.py
│       ├── test_pynq_overlay_package.py
│       ├── test_pynq_sitl_verify.py
│       ├── test_pynq_ws_stream.py
│       ├── test_quantization_router.py
│       ├── test_quantizer.py
│       ├── test_rate_limiting.py
│       ├── test_routers.py
│       ├── test_speck_backend.py
│       ├── test_speck_runtime_contract.py
│       ├── test_startup_contract.py
│       ├── test_targets_router.py
│       ├── test_teensy_deployment_contract.py
│       └── test_teensy_generator.py
├── neurochip_spec.md
├── nmtk_ui_core
├── overlay_staging
│   └── pynq_z2
│       └── README.md
├── poetry.toml
├── pynq-trouble-shoot-april.md
├── pyproject.toml
└── verify-contracts-local.sh
</directory_structure>

## Remote Testing Configuration

For dev, `REMOTE_HOST=moosebun2@192.168.2.90` can be used. For example, when the agent wants to test run the app, you can use `192.168.2.90` as the server address.
