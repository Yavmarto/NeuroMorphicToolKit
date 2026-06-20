# Neurohub & Neurobench Integration Completion

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the four specific gaps that make Neurohub and Neurobench appear broken/placeholder inside cnlstudio (neurocnl), and verify the standalone module builds are clean.

**Architecture:** The launcher routing chain (`GoRouter → ToolViewScreen → NativeSurfaceRegistry → ShellAdapter`) is architecturally correct — both Neurohub and Neurobench are already registered with their native shell adapters. The bugs are (1) the embedded NeurobenchPanel cross-module widget in neurocnl is implemented but never rendered, (2) that panel points to the wrong port (8003 runner-worker instead of suite_api 9000), (3) Neurobench is missing from the global command palette, and (4) the Neurohub command description is wrong.

**Tech Stack:** Flutter/Dart, Riverpod, GoRouter, nmtk_ui_core, suite_api (port 9000)

## Global Constraints

- All Dart-define env vars follow the `String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:9000')` pattern used throughout the codebase
- Icons come from `ZetaIcons` (not Material), matching all other commands in command_provider.dart
- No new packages — use existing imports only
- Hot-restart (not hot-reload) is sufficient for Dart changes; backend restart not required for frontend-only changes
- `make dev` launches the full stack: `./scripts/run_dev.sh --flutter-device macos`

---

## What Is NOT Broken (Do Not Change)

| Component | Status | Why |
|-----------|--------|-----|
| GoRouter `/module/neurohub` and `/module/neurobench` using `ToolViewScreen` | ✅ Correct | `ToolViewScreen` checks `NativeSurfaceRegistry` first; both modules are registered there with their shell adapters |
| `NativeSurfaceRegistry` — both adapters registered | ✅ Correct | `NeurohubShellAdapter` and `NeurobenchShellAdapter` are registered |
| suite_api domain routers for neurohub/neurobench | ✅ Real implementations | These are full proxies/in-process routers, not stubs |
| Python backends | ✅ Full implementations | Neurohub has 20+ test files; Neurobench has 40+ test files |
| Neurohub load-from-hub / publish-to-hub in neurocnl | ✅ Already wired | setup_step.dart and deploy_workspace_panel.dart both use hub_asset_provider |

---

## File Map

| File | Change |
|------|--------|
| `neurocnl/frontend/lib/providers/neurobench_panel_provider.dart` | Fix hardcoded port → API_BASE_URL |
| `neurocnl/frontend/lib/screens/studio/steps/results_step.dart` | Wire NeurobenchPanel into results UI |
| `nmtk/neuro_toolkit/lib/src/features/app/presentation/command_provider.dart` | Add Neurobench command; fix Neurohub description |

---

### Task 1: Fix NeurobenchPanel URL — use suite_api instead of hardcoded runner-worker port

The panel currently talks directly to the neurobench-runner-worker on port 8003. In the unified dev stack, the suite_api at port 9000 proxies `/api/neurobench/run/*` to the runner-worker automatically. The panel should point at suite_api.

**Files:**
- Modify: `neurocnl/frontend/lib/providers/neurobench_panel_provider.dart` (lines 10–11)

- [ ] **Step 1: Open the file and locate the constant**

  ```
  neurocnl/frontend/lib/providers/neurobench_panel_provider.dart
  lines 10-11:
    const _neurobenchBaseUrl = 'http://localhost:8003';
    const _apiPrefix = '/api/neurobench';
  ```

- [ ] **Step 2: Replace the hardcoded URL**

  ```dart
  // BEFORE
  const _neurobenchBaseUrl = 'http://localhost:8003';

  // AFTER
  const _neurobenchBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:9000',
  );
  ```

  The `_apiPrefix` constant stays unchanged.

- [ ] **Step 3: Verify no build errors**

  Run: `flutter analyze neurocnl/frontend/lib/providers/neurobench_panel_provider.dart`
  Expected: No errors.

- [ ] **Step 4: Commit**

  ```bash
  git add neurocnl/frontend/lib/providers/neurobench_panel_provider.dart
  git commit -m "fix(neurocnl): point NeurobenchPanel at suite_api port 9000 via API_BASE_URL"
  ```

---

### Task 2: Wire NeurobenchPanel into the results step UI

The `NeurobenchPanel` widget is fully implemented (constructor: `const NeurobenchPanel({super.key})`) but is never imported or rendered anywhere. The natural home is `results_step.dart`, alongside the existing "Deploy to Hardware" expandable section — add a sibling "Benchmark" toggle button and panel using the same expand/collapse pattern.

**Files:**
- Modify: `neurocnl/frontend/lib/screens/studio/steps/results_step.dart`

**Existing pattern to follow:**
```dart
// State variable
bool _deployExpanded = false;

// Toggle button
OutlinedButton.icon(
  onPressed: () => setState(() => _deployExpanded = !_deployExpanded),
  icon: Icon(_deployExpanded ? ZetaIcons.expand_less : ZetaIcons.expand_more),
  label: Text(_deployExpanded ? 'Hide Deploy' : 'Deploy to Hardware'),
),

// Expandable content
if (_deployExpanded) ...[
  const Divider(height: 1),
  SizedBox(height: 360, child: widget.buildDeployPanel()),
],
```

- [ ] **Step 1: Add the import at the top of results_step.dart**

  In the imports block:
  ```dart
  import '../../../widgets/neurobench_panel.dart';
  ```

- [ ] **Step 2: Add `_benchmarkExpanded` state variable**

  In `_ResultsStepState` alongside `_deployExpanded`:
  ```dart
  bool _deployExpanded = false;
  bool _benchmarkExpanded = false;   // ADD THIS LINE
  ```

- [ ] **Step 3: Add the Benchmark toggle button to the Row**

  In the Row of action buttons, after the existing "Deploy to Hardware" `OutlinedButton.icon`:
  ```dart
  const SizedBox(width: 8),
  OutlinedButton.icon(
    onPressed: () => setState(() => _benchmarkExpanded = !_benchmarkExpanded),
    icon: Icon(_benchmarkExpanded ? ZetaIcons.expand_less : ZetaIcons.expand_more),
    label: Text(_benchmarkExpanded ? 'Hide Benchmark' : 'Run Benchmark'),
  ),
  ```

- [ ] **Step 4: Add the NeurobenchPanel expansion section**

  Directly after the existing `if (_deployExpanded) ...` block:
  ```dart
  if (_benchmarkExpanded) ...[
    const Divider(height: 1),
    const NeurobenchPanel(),
  ],
  ```

- [ ] **Step 5: Analyze**

  Run: `flutter analyze neurocnl/frontend/lib/screens/studio/steps/results_step.dart`
  Expected: No errors, no unused imports.

- [ ] **Step 6: Hot-restart and smoke-test**

  Hot-restart the launcher (`R` in the flutter run terminal). Open a CNL workspace → run training → navigate to the results step. Verify the "Run Benchmark" button appears and expands the NeurobenchPanel with benchmark dropdown and target selector.

- [ ] **Step 7: Commit**

  ```bash
  git add neurocnl/frontend/lib/screens/studio/steps/results_step.dart
  git commit -m "feat(neurocnl): wire NeurobenchPanel into results step UI"
  ```

---

### Task 3: Fix command palette — add Neurobench, fix Neurohub description

**Files:**
- Modify: `nmtk/neuro_toolkit/lib/src/features/app/presentation/command_provider.dart`

**Current state:**
- Neurohub command exists but description is `'View saved sessions and experiment telemetry'` — wrong module description
- Neurobench command is entirely absent

**Command structure:**
```dart
NmtkCommand(
  id: 'nav-neurobench',
  label: 'Open Neurobench',
  description: 'Run SNN benchmarks and compare results across hardware targets',
  icon: ZetaIcons.speed_meter,
  category: 'Navigation',
  onExecute: () => router.go('/module/neurobench'),
),
```

- [ ] **Step 1: Fix Neurohub description**

  Find the `'nav-neurohub'` command entry and update its description:
  ```dart
  // BEFORE
  description: 'View saved sessions and experiment telemetry',

  // AFTER
  description: 'Share CNL networks, canvas projects, and bench results with your team',
  ```

- [ ] **Step 2: Add Neurobench command**

  After the Neurohub command entry, add:
  ```dart
  NmtkCommand(
    id: 'nav-neurobench',
    label: 'Open Neurobench',
    description: 'Run SNN benchmarks and compare results across hardware targets',
    icon: ZetaIcons.speed_meter,
    category: 'Navigation',
    onExecute: () => router.go('/module/neurobench'),
  ),
  ```

  > **Icon note:** If `ZetaIcons.speed_meter` does not exist, check available icons via `grep -r 'static const IconData' $(flutter pub cache dir)/hosted/pub.dev/zeta_flutter*/lib/` and substitute `ZetaIcons.chart_bar` or `ZetaIcons.analytics` as appropriate.

- [ ] **Step 3: Analyze**

  Run: `flutter analyze nmtk/neuro_toolkit/lib/src/features/app/presentation/command_provider.dart`
  Expected: No errors.

- [ ] **Step 4: Hot-restart and verify**

  Hot-restart. Open the command palette (⌘K). Verify:
  - Typing "bench" shows "Open Neurobench"
  - Typing "hub" shows "Open Neurohub Dashboard" with the updated description
  - Both entries navigate to their respective module screens

- [ ] **Step 5: Commit**

  ```bash
  git add nmtk/neuro_toolkit/lib/src/features/app/presentation/command_provider.dart
  git commit -m "fix(launcher): add Neurobench to command palette; fix Neurohub description"
  ```

---

### Task 4: Verify standalone module builds are clean

Before declaring integration complete, verify that the Neurobench and Neurohub Flutter packages compile cleanly. Earlier analysis flagged possible build issues in both.

- [ ] **Step 1: Verify Neurobench frontend**

  ```bash
  cd Neurobench/frontend && flutter pub get && flutter analyze lib/
  ```
  Expected: Exit 0, no errors.

  If errors appear around `ApiClient.runBenchmark()`: the provider calls `controller.runBenchmark()` but the actual ApiClient method is `submitBenchmarkRun()`. Fix by searching for any call sites that use the wrong name and aligning them to `submitBenchmarkRun`.

- [ ] **Step 2: Verify Neurohub frontend**

  ```bash
  cd Neurohub/frontend && flutter pub get && flutter analyze lib/
  ```
  Expected: Exit 0, no errors.

  If `shared_preferences` platform errors appear: run `flutter pub upgrade shared_preferences` (v2.3+ supports all desktop platforms).

- [ ] **Step 3: Commit any build fixes**

  ```bash
  git add Neurobench/frontend/lib/ Neurohub/frontend/lib/
  git commit -m "fix: resolve Neurobench/Neurohub frontend build errors"
  ```

- [ ] **Step 4: Full stack smoke-test**

  ```bash
  make dev
  ```

  Verify all five integration points work end-to-end:
  1. ⌘K → "Open Neurobench" → workbench screen with benchmark catalog and tabs
  2. ⌘K → "Open Neurohub" → hub dashboard with Browse / My Models tabs
  3. CNL project → train → results step → "Run Benchmark" button expands NeurobenchPanel
  4. NeurobenchPanel benchmark dropdown populates from `http://localhost:9000/api/neurobench/benchmarks`
  5. Submit a run → job progress polling works via suite_api proxy to runner-worker on 8003
