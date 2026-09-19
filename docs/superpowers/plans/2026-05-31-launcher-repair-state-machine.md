# Launcher Repair State Machine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit `repair` action to the NMTK launcher so users can recover a module stuck in `error` state — and ensure failed installs clean up their partial environments instead of leaving unrecoverable venv debris.

**Architecture:** Three layers change together: (1) Python backend gets `repair_module()` + `_repair_sync()` methods and a `POST /repair` HTTP route; (2) Dart `ControlApiService` gets `repairModule()` following the identical pattern as `installModule`; (3) Flutter UI gets a "Repair" button in the `error` state case of `_ModuleCard`. Install rollback is added to `_install_sync()` by wrapping the pip/poetry commands in a try/except that calls `_cleanup_module_environment()` before re-raising — making every failed install safe to retry immediately.

**Tech Stack:** Python (stdlib threading, server.py HTTP handler), Dart/Flutter (ChangeNotifier, http package, widget tests), pytest/unittest

---

## Scope: Both P0 #4 and P0 #9 are in this plan

These items are tightly coupled — they touch the same files:

| P0 item | What | Tasks |
|---------|------|-------|
| P0 #9 | Explicit repair endpoint + UI action | Tasks 1, 2, 4, 5 |
| P0 #4 | Install rollback (clean partial venv on failure) | Task 3 |

---

## File Map

| File | Action | Why |
|------|--------|-----|
| `nmtk/launcher_control/server.py` | Modify | Add `repair_module()`, `_repair_sync()`, HTTP route, rollback in `_install_sync()` |
| `tests/test_launcher_control_service.py` | Modify | Python unit tests for repair + rollback |
| `nmtk/neuro_toolkit/lib/services/control_api_service.dart` | Modify | Add `repairModule()` |
| `nmtk/neuro_toolkit/lib/providers/module_provider.dart` | Modify | Add `repairModule()` |
| `nmtk/neuro_toolkit/lib/widgets/module_picker_panel.dart` | Modify | Add `onRepair` param + Repair button in error state |
| `nmtk/neuro_toolkit/test/module_picker_panel_test.dart` | Modify | Add `repairCalls` to mock + Repair button widget test |

**Read before editing (per AGENTS.md):**
```bash
cat CODING_STYLE_GUIDE.md
cat nmtk/AGENTS.md
```

**Guardrails (run after every Python change to server.py):**
```bash
python3 scripts/launcher_control_service.py --doctor --json
python3 -m unittest tests.test_launcher_control_service
```

**Flutter guardrails (run after Dart changes):**
```bash
cd nmtk/neuro_toolkit && flutter test
```

---

## Task 1: Add `repair_module()` + `_repair_sync()` + HTTP route to server.py

**Files:**
- Modify: `nmtk/launcher_control/server.py`

- [ ] **Step 1: Read CODING_STYLE_GUIDE.md and nmtk/AGENTS.md**

```bash
cat $HOME/NeuroMorphicToolKit/CODING_STYLE_GUIDE.md
cat $HOME/NeuroMorphicToolKit/nmtk/AGENTS.md
```

- [ ] **Step 2: Find the line numbers of `update_module()` and `_repair_sync` area**

```bash
grep -n "def update_module\|def _update_sync\|def uninstall_module" \
  $HOME/NeuroMorphicToolKit/nmtk/launcher_control/server.py
```

This locates where to insert the new methods (place them after `update_module` / before `uninstall_module`).

- [ ] **Step 3: Add `repair_module()` method directly after `update_module()`**

Find the closing line of `update_module()` and insert after it:

```python
def repair_module(self, module_id: str) -> dict[str, Any]:
    """Repair a module by running preflight with allow_repair=True.

    Sets the module to 'installing' state immediately and spawns a background
    thread.  On completion the module lands in 'installed' (ok), 'degraded',
    or 'error' state — but is never started.
    """
    with self._lock:
        module = self._get_module(module_id)
        if self._task_running(module_id):
            return self._serialize_module(module)
        module["status"] = STATUS_INDEX["installing"]
        module["installProgress"] = 0.0
        module["healthStatus"] = None
        module["preflightStatus"] = PREFLIGHT_OK
        module["preflightMessage"] = None
        module["capabilityWarnings"] = []
        self._persist_states()
        self._spawn_task(module_id, lambda: self._repair_sync(module_id))
        return self._serialize_module(module)

def _repair_sync(self, module_id: str) -> None:
    """Background worker for repair_module().

    Runs _preflight_module with allow_repair=True.  Unlike _start_sync,
    does not attempt to start the service after a successful repair.
    """
    with self._lock:
        module = dict(self._get_module(module_id))

    preflight = self._preflight_module(module, allow_repair=True)
    self._update_module_fields(module_id, **preflight.state_fields())

    if preflight.status == PREFLIGHT_FAILED:
        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["error"],
            healthStatus=preflight.message,
        )
        raise RuntimeError(preflight.message or "Module repair failed")

    next_status = (
        STATUS_INDEX["degraded"]
        if preflight.status == PREFLIGHT_DEGRADED
        else STATUS_INDEX["installed"]
    )
    self._update_module_fields(
        module_id,
        status=next_status,
        healthStatus=None,
    )
```

- [ ] **Step 4: Add the HTTP route for `/repair`**

Find the module route handler section (around line 6510 — the block of `if len(segments) == 5 and segments[4] == "update"` checks). Add a new clause immediately after the `"update"` route:

```python
    if len(segments) == 5 and segments[4] == "repair" and method == "POST":
        self._send_json(
            HTTPStatus.ACCEPTED,
            self.server.state.repair_module(module_id),
        )
        return
```

- [ ] **Step 5: Run the doctor to verify no regressions**

```bash
cd $HOME/NeuroMorphicToolKit && \
  python3 scripts/launcher_control_service.py --doctor --json 2>&1 | python3 -m json.tool | head -20
```

Expected: `"fatalCount": 0`

- [ ] **Step 6: Commit**

```bash
git add nmtk/launcher_control/server.py
git commit -m "feat(launcher): add repair_module() + _repair_sync() + POST /repair route (P0 #9)

Adds an explicit repair action that runs _preflight_module(allow_repair=True)
without starting the service. Module transitions to installed/degraded/error
based on preflight result. Follows identical threading and state patterns as
install_module() and update_module()."
```

---

## Task 2: Python unit tests for `repair_module()`

**Files:**
- Modify: `tests/test_launcher_control_service.py`

- [ ] **Step 1: Verify existing test structure**

```bash
grep -n "def test_\|class Launcher" \
  $HOME/NeuroMorphicToolKit/tests/test_launcher_control_service.py | tail -20
```

This shows where to append new tests.

- [ ] **Step 2: Write three failing tests**

Add these test methods to `LauncherControlServiceTest`. Insert them after the last existing `test_*` method:

```python
def test_repair_module_returns_installing_state_immediately(self) -> None:
    """repair_module() returns the module in 'installing' state immediately."""
    # Prevent the background thread from running so we see the initial state.
    with mock.patch.object(self.state, "_repair_sync", return_value=None):
        result = self.state.repair_module("dummy")

    self.assertEqual(result["status"], launcher_server.STATUS_INDEX["installing"])
    self.assertIsNone(result["healthStatus"])
    self.assertEqual(result["preflightStatus"], launcher_server.PREFLIGHT_OK)

def test_repair_module_sets_installed_when_preflight_ok(self) -> None:
    """After a successful repair (preflight OK), module ends in 'installed' state."""
    # Put the module in error first.
    self.state._modules[0]["status"] = launcher_server.STATUS_INDEX["error"]
    self.state._modules[0]["healthStatus"] = "import probe failed"

    ok_result = launcher_server.PreflightResult(
        status=launcher_server.PREFLIGHT_OK,
        message=None,
        capability_warnings=[],
        environment_fingerprint="abc123",
    )
    with mock.patch.object(self.state, "_preflight_module", return_value=ok_result):
        self.state.repair_module("dummy")
        task = self.state._tasks.get("dummy")
        if task:
            task.join(timeout=5.0)

    module = self.state._get_module("dummy")
    self.assertEqual(module["status"], launcher_server.STATUS_INDEX["installed"])
    self.assertIsNone(module["healthStatus"])

def test_repair_module_sets_error_when_preflight_fails(self) -> None:
    """After a failed repair (preflight FAILED), module ends in 'error' state."""
    self.state._modules[0]["status"] = launcher_server.STATUS_INDEX["error"]

    failed_result = launcher_server.PreflightResult(
        status=launcher_server.PREFLIGHT_FAILED,
        message="Cannot find required dependency: torch",
        capability_warnings=[],
        environment_fingerprint=None,
    )
    with mock.patch.object(self.state, "_preflight_module", return_value=failed_result):
        self.state.repair_module("dummy")
        task = self.state._tasks.get("dummy")
        if task:
            task.join(timeout=5.0)

    module = self.state._get_module("dummy")
    self.assertEqual(module["status"], launcher_server.STATUS_INDEX["error"])
    self.assertEqual(module["healthStatus"], "Cannot find required dependency: torch")
```

- [ ] **Step 3: Run the new tests — expect FAIL**

```bash
cd $HOME/NeuroMorphicToolKit && \
  python3 -m unittest \
    tests.test_launcher_control_service.LauncherControlServiceTest.test_repair_module_returns_installing_state_immediately \
    tests.test_launcher_control_service.LauncherControlServiceTest.test_repair_module_sets_installed_when_preflight_ok \
    tests.test_launcher_control_service.LauncherControlServiceTest.test_repair_module_sets_error_when_preflight_fails \
    -v 2>&1 | tail -20
```

Expected: FAIL (`AttributeError: 'LauncherControlState' object has no attribute 'repair_module'`) — these tests were written before Task 1, which should already be done; if Task 1 is complete the tests should now PASS. Re-run to confirm.

- [ ] **Step 4: Run all launcher unit tests — no regressions**

```bash
cd $HOME/NeuroMorphicToolKit && \
  python3 -m unittest tests.test_launcher_control_service -v 2>&1 | tail -20
```

Expected: all tests pass including the 3 new ones.

- [ ] **Step 5: Run doctor**

```bash
python3 scripts/launcher_control_service.py --doctor --json 2>&1 | python3 -m json.tool | grep -E "fatalCount|degradedCount|okCount"
```

Expected: `"fatalCount": 0`

- [ ] **Step 6: Commit**

```bash
git add tests/test_launcher_control_service.py
git commit -m "test(launcher): add unit tests for repair_module() — ok, failed, and immediate state"
```

---

## Task 3: Install rollback — clean partial venv when `_install_sync` fails

Without this, a failed pip install leaves a partial `.venv`/`venv` directory. The next `repair` or `install` call sees the broken venv and may report misleading errors instead of reinstalling cleanly. The fix wraps the install commands in a try/except that calls `_cleanup_module_environment()` before re-raising.

**Files:**
- Modify: `nmtk/launcher_control/server.py` (in `_install_sync`, lines ~5175–5269)
- Modify: `tests/test_launcher_control_service.py`

- [ ] **Step 1: Write a failing test that asserts venv is removed after install failure**

Add to `LauncherControlServiceTest`:

```python
def test_install_sync_cleans_venv_on_pip_failure(self) -> None:
    """When pip install fails, _install_sync removes the partial venv directory."""
    # Create a fake (partial) venv directory simulating a mid-install state.
    venv_path = self.repo_root / "dummy_module" / "venv"
    venv_path.mkdir(parents=True, exist_ok=True)
    (venv_path / "pyvenv.cfg").write_text("home = /usr/bin\n", encoding="utf-8")

    # Make _run_command raise to simulate a pip failure.
    call_count = {"n": 0}
    original_run_cmd = self.state._run_command

    def fail_on_pip(command: list, cwd, module_id: str) -> None:  # type: ignore[override]
        call_count["n"] += 1
        if "pip" in command or "install" in command:
            raise RuntimeError("pip install failed: network error")
        return original_run_cmd(command, cwd, module_id)

    with mock.patch.object(self.state, "_run_command", side_effect=fail_on_pip):
        with self.assertRaises(RuntimeError):
            self.state._install_sync("dummy")

    self.assertFalse(
        venv_path.exists(),
        "Partial venv directory must be removed after a failed pip install",
    )
```

- [ ] **Step 2: Run the test — expect FAIL**

```bash
cd $HOME/NeuroMorphicToolKit && \
  python3 -m unittest \
    tests.test_launcher_control_service.LauncherControlServiceTest.test_install_sync_cleans_venv_on_pip_failure \
    -v 2>&1 | tail -10
```

Expected: FAIL — venv still exists after exception.

- [ ] **Step 3: Add rollback to `_install_sync()` in `server.py`**

Locate the section of `_install_sync` that begins after the venv creation and pip setup (around line 5237 — after `self._update_module_fields(module_id, installProgress=0.6)`). Wrap the entire pip/poetry install command block and the final `_update_module_fields(installed)` call in a try/except. The final portion of `_install_sync` becomes:

```python
    self._update_module_fields(module_id, installProgress=0.6)
    try:
        if poetry is not None and _module_uses_poetry(module):
            self._run_command(
                [str(poetry), "lock"],
                cwd=install_dir,
                module_id=module_id,
            )
            self._run_command(
                [str(poetry), "install", "--no-interaction", "--no-root"],
                cwd=install_dir,
                module_id=module_id,
            )
        else:
            install_extras = _module_install_extras(module)
            install_target = (
                f".[{','.join(install_extras)}]" if install_extras else "."
            )
            self._run_command(
                [str(venv_python), "-m", "pip", "install", install_target],
                cwd=install_dir,
                module_id=module_id,
            )
        environment_fingerprint = self._compute_environment_fingerprint(module)
        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["installed"],
            installProgress=1.0,
            healthStatus=None,
            preflightStatus=PREFLIGHT_OK,
            preflightMessage=None,
            capabilityWarnings=[],
            environmentFingerprint=environment_fingerprint,
        )
    except Exception:
        # Rollback: remove any partial venv so the next install starts clean.
        self._append_log(
            module_id,
            "Installation failed — removing partial environment so the next install starts fresh.",
            stderr=True,
            emit_terminal=True,
        )
        self._cleanup_module_environment(module_id)
        raise
```

**Important:** Only the pip/poetry install commands and the final success update need to be inside the try. The venv creation commands (before `installProgress=0.6`) remain outside — if venv creation itself fails, there's nothing meaningful to clean up yet.

- [ ] **Step 4: Run the failing test — expect PASS**

```bash
cd $HOME/NeuroMorphicToolKit && \
  python3 -m unittest \
    tests.test_launcher_control_service.LauncherControlServiceTest.test_install_sync_cleans_venv_on_pip_failure \
    -v 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 5: Run all launcher unit tests — no regressions**

```bash
python3 -m unittest tests.test_launcher_control_service -v 2>&1 | tail -20
```

Expected: all previously passing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add nmtk/launcher_control/server.py tests/test_launcher_control_service.py
git commit -m "fix(launcher): clean partial venv on pip install failure (P0 #4)

Wraps the pip/poetry install commands in _install_sync() with a rollback
try/except that calls _cleanup_module_environment() before re-raising.
Guarantees every failed install leaves a clean slate for the next attempt."
```

---

## Task 4: Add `repairModule()` to Dart `ControlApiService` and `ModuleProvider`

**Files:**
- Modify: `nmtk/neuro_toolkit/lib/services/control_api_service.dart`
- Modify: `nmtk/neuro_toolkit/lib/providers/module_provider.dart`

- [ ] **Step 1: Add `repairModule()` to `ControlApiService`**

Locate `installModule()` (around line 560) and add the following method immediately after `updateModule()`:

```dart
  Future<Module> repairModule(String moduleId) async {
    final response = await _client.post(
      _uri('/api/launcher/modules/$moduleId/repair'),
    );
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }
```

- [ ] **Step 2: Add `repairModule()` to `ModuleProvider`**

Locate `installModule()` in `module_provider.dart` (lines 260–297) and add the following method immediately after it:

```dart
  Future<void> repairModule(String moduleId) async {
    final index = _modules.indexWhere((Module module) => module.id == moduleId);
    if (index == -1) {
      return;
    }

    _modules[index] = _modules[index].copyWith(
      status: ModuleStatus.installing,
      installProgress: 0.0,
      healthStatus: null,
    );
    notifyListeners();

    try {
      _modules[index] = await _controlApiService.repairModule(moduleId);
      notifyListeners();
      await _reloadFromControlApi(includeLauncherUpdate: false);
    } catch (e) {
      _modules[index] = _modules[index].copyWith(
        status: ModuleStatus.error,
        healthStatus: nmtkUserFacingError(e),
      );
      notifyListeners();
      debugPrint('Repair failed for $moduleId: $e');
    }
  }
```

- [ ] **Step 3: Add `repairModule()` to the `ModuleProvider` abstract interface (if it exists)**

Check if `ModuleProvider` is an abstract class/interface:
```bash
grep -n "abstract\|interface\|repairModule" \
  $HOME/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/providers/module_provider.dart | head -10
```

If there is an abstract base or interface that lists `installModule`, `launchModule`, etc., add `Future<void> repairModule(String moduleId);` to it in the same position (after `installModule`).

- [ ] **Step 4: Run Flutter tests to detect compilation errors**

```bash
cd $HOME/NeuroMorphicToolKit/nmtk/neuro_toolkit && flutter test --no-pub 2>&1 | head -30
```

Expected: compilation succeeds (any test failures at this point will be in the next task's widget test).

- [ ] **Step 5: Commit**

```bash
git add \
  nmtk/neuro_toolkit/lib/services/control_api_service.dart \
  nmtk/neuro_toolkit/lib/providers/module_provider.dart
git commit -m "feat(launcher): add repairModule() to ControlApiService and ModuleProvider

Wires the POST /repair endpoint into the Dart layer following the identical
pattern as installModule(). ModuleProvider optimistically sets the module
to installing state, calls the API, then reloads from control API on success."
```

---

## Task 5: Add "Repair" button to `module_picker_panel.dart` + widget test

**Files:**
- Modify: `nmtk/neuro_toolkit/lib/widgets/module_picker_panel.dart`
- Modify: `nmtk/neuro_toolkit/test/module_picker_panel_test.dart`

- [ ] **Step 1: Write a failing widget test**

In `module_picker_panel_test.dart`, add `repairCalls` to `_MockProvider` and the new test.

Add `final List<String> repairCalls = [];` to the `_MockProvider` field declarations (line ~18).

Add the `repairModule` override (after the `updateModule` override, around line 69):

```dart
  @override
  Future<void> repairModule(String moduleId) async =>
      repairCalls.add(moduleId);
```

Then add the widget test after the last existing `testWidgets` call:

```dart
  testWidgets('shows Repair button for error module and calls repairModule on tap',
      (tester) async {
    final mock = _MockProvider();
    mock.setModules([
      Module(
        id: 'neurocnl',
        name: 'CNL Studio',
        description: 'CNL parser',
        directory: 'neurocnl/',
        status: ModuleStatus.error,
        healthStatus: 'Import probe failed: ModuleNotFoundError',
      ),
    ]);
    await tester.pumpWidget(wrap(mock));
    await tester.pump();

    expect(find.text('Repair'), findsOneWidget);

    await tester.tap(find.text('Repair'));
    await tester.pump();

    expect(mock.repairCalls, contains('neurocnl'));
  });
```

- [ ] **Step 2: Run the new test — expect FAIL**

```bash
cd $HOME/NeuroMorphicToolKit/nmtk/neuro_toolkit && \
  flutter test test/module_picker_panel_test.dart --no-pub 2>&1 | tail -20
```

Expected: FAIL — `_MockProvider` does not yet implement `repairModule` (compile error) and/or `Repair` button not found.

- [ ] **Step 3: Add `onRepair` parameter to `_ModuleCard`**

In `module_picker_panel.dart`, update the `_ModuleCard` class definition (lines 114–131):

```dart
class _ModuleCard extends StatelessWidget {
  final Module module;
  final bool isMuJoCoUnavailable;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onOpen;
  final VoidCallback onStop;
  final VoidCallback? onUpdate;
  final VoidCallback? onRepair;   // ← add this line

  const _ModuleCard({
    required this.module,
    required this.isMuJoCoUnavailable,
    required this.onInstall,
    required this.onLaunch,
    required this.onOpen,
    required this.onStop,
    required this.onUpdate,
    this.onRepair,                // ← add this line
  });
```

- [ ] **Step 4: Update the `error` state case in `_buildActionArea()`**

Replace the `error` case (lines 282–291):

```dart
// BEFORE:
      case ModuleStatus.error:
        return Semantics(
          label: 'Retry starting ${module.name}',
          button: true,
          child: NmtkPrimaryButton(
            onPressed: onLaunch,
            icon: Icons.play_arrow,
            label: 'Start',
          ),
        );

// AFTER:
      case ModuleStatus.error:
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (onRepair != null)
              Semantics(
                label: 'Repair ${module.name}',
                button: true,
                child: NmtkPrimaryButton(
                  onPressed: onRepair,
                  icon: Icons.build_outlined,
                  label: 'Repair',
                  tone: NmtkTone.warning,
                ),
              ),
            Semantics(
              label: 'Retry starting ${module.name}',
              button: true,
              child: NmtkPrimaryButton(
                onPressed: onLaunch,
                icon: Icons.play_arrow,
                label: 'Start',
              ),
            ),
          ],
        );
```

- [ ] **Step 5: Wire `onRepair` where `_ModuleCard` is instantiated**

Search for where `_ModuleCard(` is constructed (inside `module_picker_panel.dart`):

```bash
grep -n "_ModuleCard(" \
  $HOME/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/widgets/module_picker_panel.dart
```

In that construction site, pass the repair callback:

```dart
_ModuleCard(
  module: module,
  isMuJoCoUnavailable: isMuJoCoUnavailable,
  onInstall: () => provider.installModule(module.id),
  onLaunch: () => provider.launchModule(module.id),
  onOpen: () => provider.launchModule(module.id),
  onStop: () => provider.stopModule(module.id),
  onUpdate: hasUpdate ? () => provider.updateModule(module.id) : null,
  onRepair: () => provider.repairModule(module.id),   // ← add this line
)
```

- [ ] **Step 6: Run the new test — expect PASS**

```bash
cd $HOME/NeuroMorphicToolKit/nmtk/neuro_toolkit && \
  flutter test test/module_picker_panel_test.dart --no-pub 2>&1 | tail -20
```

Expected: all tests including the new "Repair button" test PASS.

- [ ] **Step 7: Run full Flutter test suite — no regressions**

```bash
cd $HOME/NeuroMorphicToolKit/nmtk/neuro_toolkit && flutter test --no-pub 2>&1 | tail -20
```

Expected: all previously passing tests still pass.

- [ ] **Step 8: Commit**

```bash
git add \
  nmtk/neuro_toolkit/lib/widgets/module_picker_panel.dart \
  nmtk/neuro_toolkit/test/module_picker_panel_test.dart
git commit -m "feat(launcher-ui): add Repair button to error-state module card (P0 #9)

Shows a 'Repair' button (NmtkTone.warning, build icon) alongside the existing
'Start' retry button when a module is in error state. Tapping it calls
provider.repairModule() which hits the new POST /repair endpoint."
```

---

## End-to-End Verification

Run this checklist after all 5 tasks are complete:

```bash
# 1. Doctor: fatalCount must be 0
python3 scripts/launcher_control_service.py --doctor --json 2>&1 | \
  python3 -m json.tool | grep -E "fatalCount|degradedCount"

# 2. Python unit tests (all must pass)
python3 -m unittest tests.test_launcher_control_service -v 2>&1 | tail -10

# 3. Flutter tests (all must pass)
cd nmtk/neuro_toolkit && flutter test --no-pub 2>&1 | tail -10; cd ../..

# 4. repair endpoint exists in source
grep -n '"repair"' nmtk/launcher_control/server.py

# 5. rollback log message in source
grep -n "partial environment" nmtk/launcher_control/server.py

# 6. Repair button in UI source
grep -n "Repair" nmtk/neuro_toolkit/lib/widgets/module_picker_panel.dart
```

---

## After This Plan: What's Next

| Next Plan | Addresses |
|-----------|-----------|
| **Plan C: Honesty of Results** | P0 #5 (Teensy/PYNQ validated hardware path), P0 #6 (Neurobench `metric_provenance` field), P1 #11 (neurocnl validation/deploy truth), P1 #12 (pre-export capability check) |
| **Plan D: Distribution Hardening** | P1 #10 (codesigning/notarization), P1 #13 (Neurohub CI to green), P1 #14 (golden-path CI gate) |
