# Akida Launcher Runtime Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let CNL Studio use Akida runtime map and run actions through launcher-managed Akida host records instead of talking directly to remote Neurochip runtimes.

**Architecture:** Add thin launcher proxy endpoints for Akida host `map` and `run`, reusing existing host resolution, terminal logging, and remote JSON request helpers. Update Studio’s target-registry and deploy-service layers so selected-host Akida flows use launcher endpoints while local/no-host flows keep the current direct-runtime behavior.

**Tech Stack:** Python launcher control service, Dart Studio services/providers, pytest/unittest launcher tests, Flutter unit tests

---

### Task 1: Launcher Akida proxy tests

**Files:**
- Modify: `tests/test_launcher_control_service.py`
- Modify: `nmtk/launcher_control/server.py`

- [ ] Add a failing launcher test for `map` host proxy routing and payload forwarding.
- [ ] Run the targeted launcher test and confirm it fails because the route or state method is missing.
- [ ] Add the minimal launcher route and proxy method to pass the test.
- [ ] Re-run the targeted launcher test and confirm it passes.

### Task 2: Launcher Akida run proxy tests

**Files:**
- Modify: `tests/test_launcher_control_service.py`
- Modify: `nmtk/launcher_control/server.py`

- [ ] Add a failing launcher test for `run` host proxy routing, request payload forwarding, and runtime-target response passthrough.
- [ ] Run the targeted launcher test and confirm it fails for the expected missing behavior.
- [ ] Implement the minimal `run` proxy and terminal logging behavior to satisfy the test.
- [ ] Re-run the targeted launcher tests and confirm both `map` and `run` pass.

### Task 3: Studio selected-host routing tests

**Files:**
- Modify: `neurocnl/frontend/test/services/studio_target_registry_service_test.dart`
- Modify: `neurocnl/frontend/test/providers/studio_akida_deploy_provider_test.dart`
- Modify: `neurocnl/frontend/lib/services/studio_target_registry_service.dart`
- Modify: `neurocnl/frontend/lib/services/studio_akida_deploy_service.dart`

- [ ] Add failing service tests for launcher-backed Akida host `map` and `run`.
- [ ] Add or adjust provider tests so selected-host actions call the host-aware service path.
- [ ] Run the focused Flutter tests and confirm they fail because the host-aware methods do not exist yet.
- [ ] Implement the minimal Studio service changes to pass the new tests.
- [ ] Re-run the focused Flutter tests and confirm they pass.

### Task 4: End-to-end verification

**Files:**
- Modify: `nmtk/launcher_control/server.py`
- Modify: `tests/test_launcher_control_service.py`
- Modify: `neurocnl/frontend/lib/services/studio_target_registry_service.dart`
- Modify: `neurocnl/frontend/lib/services/studio_akida_deploy_service.dart`
- Modify: `neurocnl/frontend/test/services/studio_target_registry_service_test.dart`
- Modify: `neurocnl/frontend/test/providers/studio_akida_deploy_provider_test.dart`

- [ ] Run the focused Python launcher tests.
- [ ] Run the focused Flutter test files.
- [ ] Run `bash scripts/run_launcher_guardrails.sh` because launcher behavior is changing.
- [ ] If guardrails fail, fix the smallest blocker and re-run the affected checks.
