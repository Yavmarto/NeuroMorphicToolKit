# Neurosense

Read first:
- `CODING_STYLE_GUIDE.md`
- `pyproject.toml`
- `frontend/pubspec.yaml`
- `frontend/analysis_options.yaml`
- `.pre-commit-config.yaml`
- `neurosense_spec.md`
- `docs/ADR-Gemini/`, `docs/ADR-Codex/`, `docs/ADR-claude/`

Constraints:
- `neurosense/contracts/*.py` own device, signal, encoding, recording, performance, and preset payloads; update contracts and contract tests before changing routers or services.
- Preserve domain invariants such as channel count, sampling rate, gain, latency, and spike-train shape when editing acquisition or encoding paths.
- Hardware-facing logic must remain testable without physical devices; use the existing simulated or bridge-verification paths instead of assuming live hardware.
- Any change to encoded outputs, preset formats, or stream payloads requires reading the downstream consumer first: `neurocnl`, `Neurobench`, or `Neurohub`.
- Verify touched surfaces with `PYTHONPATH=neurosense pytest neurosense/tests/`, `python neurosense/tests/verify_hardware_bridge.py`, and `cd frontend && flutter test`.

Do NOT:
- Hardcode a specific board, sampling rate, or recording path as the default behavior.
- Change encoded payload fields in only one layer.
- Bypass the contract layer or hardware-bridge verification because the UI still renders.

## Shell mode

Primary screen uses `NmtkShellMode.instrument`. Pass `mode: NmtkShellMode.instrument` to `NmtkDesktopScaffold` (or `NmtkTopAppBar` in embedded mode). Do not use `.command` or `.studio`.

Live status badges (device name, connection state, sample rate, recording timer, drop-frame counter) belong in `NmtkDesktopScaffold`'s `headerActions:` slot, not as part of the main screen body. The waveform viewer (`LiveSignalViewer`) must use `Expanded` to fill available height — never a hardcoded pixel height.

The module theme seed must be `0xFF0891B2` (cyan) to match instrument-mode accent and avoid collision with `NmtkShellTokens.liveColor` (`0xFFE11D48`). Do not revert to the rose seed.


---

## Pipeline Agent Directives

This document provides instructions and context for AI agents working on the NeuroSense codebase.

## Project Overview
NeuroSense is a Biosignal Acquisition & Spike Encoding Toolkit. It acquires biological signals (EMG, EEG, EOG, ECG), processes them, and encodes them into spikes for neuromorphic systems.

## Tech Stack
- **Backend:** Python (FastAPI, Pydantic, BrainFlow, neurocnl, scipy, h5py)
- **Frontend:** Flutter (Riverpod, web_socket_channel, neuro-flutter-ui)

## Core Directives for Agents
1. **Maintain Domain Invariants:**
   - Channel count: 1-1024
   - Sampling rate: 1000-40000 Hz
   - Gain: 0.1-1000
   - Display latency: < 50ms
   - Pipeline latency: < 100ms
2. **Contract-Driven Development (CDD):**
   - Formal data contracts are in `neurosense/contracts/`.
   - Update contracts BEFORE changing implementation.
3. **Property-Based Testing (PBT):**
   - Use Hypothesis for testing domain invariants (`neurosense/tests/properties/`).
4. **Typing:**
   - Python: Strict type hints, pass `mypy --strict`.
   - Dart: No `dynamic`, use strong models.
5. **Hardware Simulation:**
   - Use BrainFlow Board ID -1 (Synthetic Board) for testing without physical hardware.

## Critical Files
- `neurosense_spec.md`: Detailed product specification.
- `CODING_STYLE_GUIDE.md`: Workspace-wide coding standards.
- `neurosense/contracts/`: Domain validation rules.
- `neurosense/app/services/device_manager.py`: Device lifecycle management.

## Testing Instructions
- Backend: `PYTHONPATH=neurosense pytest neurosense/tests/`
- Frontend: `flutter test` (inside `frontend/`)
- Hardware Bridge: `python neurosense/tests/verify_hardware_bridge.py`

<directory_structure>
├── AGENTS.md
├── CHANGELOG.md
├── DEMO_WALKTHROUGH.md
├── Dockerfile
├── LICENSE
├── Makefile
├── Neurosense_shell_adapter
│   ├── LICENSE
│   ├── lib
│   │   ├── neurosense_shell_adapter.dart
│   │   └── src
│   │       └── neurosense_shell_adapter.dart
│   ├── pubspec.lock
│   └── pubspec.yaml
├── README.md
├── SECURITY.md
├── UI migration.md
├── backend.log
├── docker-compose.yml
├── docs
│   ├── ADR-Codex
│   │   └── 0001-initial-architecture.md
│   ├── ADR-Gemini
│   │   ├── 0001-initial-architecture.md
│   │   ├── 0002-tiered-websocket-streaming.md
│   │   └── 0003-centralized-spike-encoding.md
│   ├── ADR-claude
│   │   ├── 0001-hardware-abstraction-sources.md
│   │   ├── 0002-multi-strategy-spike-encoding.md
│   │   ├── 0003-hdf5-session-artifacts.md
│   │   ├── 0004-signal-filter-pipeline.md
│   │   ├── 0005-quality-analysis-replay.md
│   │   └── 0006-session-benchmark-handoff.md
│   ├── api_documentation.md
│   ├── archive
│   │   ├── 02-Apr-2026-status-Jules.md
│   │   ├── neurosense-plan.md
│   │   ├── prophesee_integration_plan.md
│   │   └── pynq_integration_plan.md
│   ├── benchmarks.md
│   ├── consensus_research_questions.md
│   ├── cyton_acceptance_runbook.md
│   ├── developer_guide_adding_device.md
│   ├── flagship_workflow.md
│   ├── hardware_testing.md
│   ├── integration_guide_neurosense_to_toolkit.md
│   ├── session_artifact_contract.md
│   ├── typing.md
│   ├── unified-dev-pipeline
│   │   └── neurosense
│   │       └── GUARDRAILS.md
│   └── user_guide_connecting_device.md
├── fix_tests.patch
├── frontend
│   ├── LICENSE
│   ├── README.md
│   ├── analysis_options.yaml
│   ├── dart_test.yaml
│   ├── lib
│   │   ├── app.dart
│   │   ├── main.dart
│   │   ├── models
│   │   │   ├── device_info.dart
│   │   │   ├── preset.dart
│   │   │   ├── session.dart
│   │   │   └── signal_quality.dart
│   │   ├── providers
│   │   │   ├── device_provider.dart
│   │   │   ├── preset_provider.dart
│   │   │   ├── quality_provider.dart
│   │   │   ├── recording_provider.dart
│   │   │   ├── sessions_provider.dart
│   │   │   └── stream_provider.dart
│   │   ├── screens
│   │   │   ├── device_config_screen.dart
│   │   │   ├── filter_pipeline_screen.dart
│   │   │   ├── sessions_screen.dart
│   │   │   └── signal_monitor_screen.dart
│   │   ├── services
│   │   │   └── api_client.dart
│   │   ├── shell
│   │   │   ├── neurosense_deep_link.dart
│   │   │   ├── neurosense_restoration_snapshot.dart
│   │   │   ├── neurosense_route_state.dart
│   │   │   └── neurosense_workspace_controller.dart
│   │   ├── shell_adapter.dart
│   │   └── widgets
│   │       ├── capability_notice.dart
│   │       ├── device_selector.dart
│   │       ├── export_dialog.dart
│   │       ├── live_signal_viewer.dart
│   │       ├── pipeline_connector.dart
│   │       ├── preset_selector.dart
│   │       ├── recording_controls.dart
│   │       ├── replay_controls.dart
│   │       ├── replay_status_summary.dart
│   │       ├── signal_quality_bar.dart
│   │       ├── spike_encoding_panel.dart
│   │       └── support_level_badge.dart
│   ├── pubspec.lock
│   ├── pubspec.yaml
│   ├── test
│   │   ├── governance
│   │   │   └── material_icons_audit_test.dart
│   │   ├── providers
│   │   │   ├── device_provider_test.dart
│   │   │   ├── quality_provider_test.dart
│   │   │   ├── recording_provider_test.dart
│   │   │   ├── sessions_provider_test.dart
│   │   │   └── stream_provider_test.dart
│   │   ├── screens
│   │   │   └── neurosense_responsive_audit_test.dart
│   │   ├── shell
│   │   │   └── neurosense_shell_adapter_test.dart
│   │   ├── widget_test.dart
│   │   └── widgets
│   │       ├── device_selector_test.dart
│   │       ├── live_signal_viewer_test.dart
│   │       ├── recording_controls_test.dart
│   │       ├── replay_controls_test.dart
│   │       ├── spike_encoding_panel_test.dart
│   │       └── troubleshooting_guide_test.dart
│   └── web
│       ├── favicon.png
│       ├── icons
│       │   ├── Icon-192.png
│       │   ├── Icon-512.png
│       │   ├── Icon-maskable-192.png
│       │   └── Icon-maskable-512.png
│       ├── index.html
│       └── manifest.json
├── identify_tech_debt.sh
├── integration_test.py
├── issues-archive
│   ├── 001-beta-add-real-stream-to-export-integration-smoke.md
│   ├── 001-validate-ragged-batch-encoding-inputs.md
│   ├── 002-beta-enforce-strict-mypy-baseline-for-core-package.md
│   ├── 006-beta-rate-limiting.md
│   ├── 007-beta-authentication-layer.md
│   ├── 008-beta-structured-logging.md
│   ├── 009-beta-hardware-integration-verification-simulated.md
│   ├── 01-f811-redefined-names.md
│   ├── 010-beta-signal-processing-pipeline-hardening.md
│   ├── 011-beta-security-md-and-changelog-md.md
│   ├── 012-prod-end-to-end-integration-tests.md
│   ├── 013-prod-real-openbci-hardware-validation.md
│   ├── 014-prod-container-hardening.md
│   ├── 015-prod-real-time-streaming-performance.md
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
│   ├── 10-neurosense-shared-shell-theme-and-session-browser.md
│   ├── 11-d417-docstring-args.md
│   ├── 11-neurosense-shell-adapter-and-replay-restoration.md
│   ├── 12-neurosense-live-monitoring-and-acquisition-controls.md
│   ├── 12-plc0415-inline-imports.md
│   ├── 13-neurosense-relevance-evaluation.md
│   ├── 13-plr2004-magic-numbers.md
│   ├── 14-plr0915-oversized-functions.md
│   ├── sent-001-beta-validate-one-real-acquisition-hardware-path.md
│   ├── sent-001-prophesee-event-camera-integration.md
│   ├── sent-002-prod-create-a-canonical-session-artifact-contract.md
│   ├── sent-002-pynq-z2-edge-sensor-acquisition.md
│   ├── sent-003-beta-make-hardware-support-levels-explicit.md
│   ├── sent-prophesee_camera_integration.md
│   └── sent-pynq_edge_sensor_integration.md
├── issues-next
│   ├── 001-prod-benchmark-the-signal-to-spike-pipeline.md
│   ├── 002-prod-tighten-integration-with-neurocnl-and-neurobench.md
│   ├── 003-prod-add-one-truthful-end-to-end-demo.md
│   └── 004-prod-responsive-frontend-surface-audit.md
├── neurosense
│   ├── GUARDRAILS.md
│   ├── __init__.py
│   ├── app
│   │   ├── __init__.py
│   │   ├── auth.py
│   │   ├── limiter.py
│   │   ├── logging_utils.py
│   │   ├── main.py
│   │   ├── middleware.py
│   │   ├── routers
│   │   │   ├── __init__.py
│   │   │   ├── devices.py
│   │   │   ├── encoding.py
│   │   │   ├── export.py
│   │   │   ├── nir.py
│   │   │   ├── presets.py
│   │   │   ├── prophesee.py
│   │   │   ├── pynq.py
│   │   │   ├── quality.py
│   │   │   ├── recording.py
│   │   │   ├── sessions.py
│   │   │   └── stream.py
│   │   ├── schemas
│   │   │   ├── __init__.py
│   │   │   ├── devices.py
│   │   │   ├── encoding.py
│   │   │   ├── presets.py
│   │   │   ├── quality.py
│   │   │   ├── runtime.py
│   │   │   └── sessions.py
│   │   ├── services
│   │   │   ├── __init__.py
│   │   │   ├── benchmark_pipeline.py
│   │   │   ├── device_manager.py
│   │   │   ├── event_encoder.py
│   │   │   ├── filter_pipeline.py
│   │   │   ├── nir_service.py
│   │   │   ├── pipeline_bridge.py
│   │   │   ├── pynq_stream_client.py
│   │   │   ├── quality_analyzer.py
│   │   │   ├── recording_service.py
│   │   │   ├── replay_service.py
│   │   │   ├── session_artifact.py
│   │   │   └── spike_encoder.py
│   │   └── sources
│   │       ├── __init__.py
│   │       ├── prophesee_source.py
│   │       └── pynq_source.py
│   ├── contracts
│   │   ├── __init__.py
│   │   ├── device_contracts.py
│   │   ├── encoding_contracts.py
│   │   ├── performance_contracts.py
│   │   ├── preset_contracts.py
│   │   ├── recording_contracts.py
│   │   └── signal_contracts.py
│   ├── docs
│   │   └── cyton_acceptance_runbook.md
│   ├── electrode_diagrams
│   │   ├── forearm_emg.svg
│   │   ├── horizontal_eog.svg
│   │   └── occipital_eeg.svg
│   ├── presets
│   │   ├── eeg_alpha_bci.json
│   │   ├── emg_prosthetic.json
│   │   ├── eog_gaze.json
│   │   └── tactile_array.json
│   ├── pynq_service
│   │   ├── __init__.py
│   │   └── main.py
│   ├── scripts
│   │   ├── __init__.py
│   │   ├── benchmark_pipeline.py
│   │   └── flagship_demo.py
│   └── tests
│       ├── README.md
│       ├── __init__.py
│       ├── benchmark_latency.py
│       ├── conftest.py
│       ├── fixtures
│       │   ├── README.md
│       │   ├── canonical_emg_session.hdf5
│       │   ├── cyton_sample.csv
│       │   └── cyton_sample.hdf5
│       ├── mock_device.py
│       ├── profile_pipeline.py
│       ├── properties
│       │   ├── __init__.py
│       │   ├── test_device_properties.py
│       │   ├── test_encoding_properties.py
│       │   └── test_new_invariants.py
│       ├── test_auth.py
│       ├── test_benchmark_pipeline.py
│       ├── test_contracts.py
│       ├── test_device_manager.py
│       ├── test_e2e_pipeline.py
│       ├── test_event_encoder.py
│       ├── test_export.py
│       ├── test_filter_pipeline.py
│       ├── test_hardware_integration.py
│       ├── test_main.py
│       ├── test_middleware.py
│       ├── test_nir_integration.py
│       ├── test_pipeline_bridge.py
│       ├── test_quality_analyzer.py
│       ├── test_rate_limiting.py
│       ├── test_recording_service.py
│       ├── test_replay_service.py
│       ├── test_smoke.py
│       ├── test_spike_encoder.py
│       ├── test_stream.py
│       ├── test_validate_hardware.py
│       ├── validate_hardware.py
│       └── verify_hardware_bridge.py
├── neurosense.egg-info
│   ├── PKG-INFO
│   ├── SOURCES.txt
│   ├── dependency_links.txt
│   ├── requires.txt
│   └── top_level.txt
├── neurosense_spec.md
├── pyproject.toml
├── server_output.log
├── uvicorn.log
├── verify-contracts-local.sh
└── verify_troubleshooting.py
</directory_structure>

## Remote Testing Configuration

For dev, `REMOTE_HOST=dev@<dev-host>` can be used. For example, when the agent wants to test run the app, you can use `<dev-host>` as the server address.
