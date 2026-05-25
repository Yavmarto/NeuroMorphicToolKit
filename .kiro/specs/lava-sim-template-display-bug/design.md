# Lava Sim Template Display Bug — Bugfix Design

## Overview

Running a basic CNL template through the Lava simulator (`lava_sim`) produces two visible defects: only the actuator (last connection target) population appears in the Dynamics tab dropdown and Spike Raster, and the canvas Deploy-pane shows the empty-state placeholder instead of any simulation data.

The bug has two independent root causes that require two surgical, non-overlapping fixes:

1. **Backend (`lava_simulator.py`)** — `_run_in_process` creates a single `Monitor` and probes only the last connection target population. `_run_remote` calls `_infer_output_population` (returns only the last LIF) and passes a single-key spikes dict through `_normalize_flat_spikes`. Both paths must be updated to monitor and return every LIF population.

2. **Frontend (`simulator_panel.dart` + `simulation_provider.dart`)** — `CanvasSimulationSurface` reads `simulationProvider.playback`, which is populated exclusively from the canvas WebSocket/polling `PreviewPlayback` API. When `SimulatorPanel` completes a `lava_sim` run in the Deploy-pane context, it never writes to `simulationProvider`, so `playback` stays `null` and the empty-state widget is shown. The fix converts the `SimulatorRunResult.spikes` map into a `PreviewPlayback` value and writes it to `simulationProvider` after a successful Deploy-pane run.

---

## Glossary

- **Bug_Condition (C)**: The condition that triggers either defect — either (a) a `lava_sim` run where the NIR graph contains ≥ 2 LIF populations, or (b) a `lava_sim` run completing in the Deploy-pane context where `simulationProvider.playback` is not populated.
- **Property (P)**: The desired correct behavior — (a) `SimulatorRunResult.spikes` contains one key per LIF/CubaLIF population in the NIR graph, or (b) `simulationProvider.playback` is non-null after a Deploy-pane `lava_sim` run completes.
- **Preservation**: The existing `snntorch_sim` multi-population recording, voltage trace rendering, silent-network warning, and missing-dependency error handling that must remain unchanged by this fix.
- **`LavaSimulatorAdapter._run_in_process`**: The function in `neurocnl/neurocnl/runtime/lava_simulator.py` that builds Lava processes and runs the simulation in-process. Currently creates a single `Monitor` for only the last connection target.
- **`LavaSimulatorAdapter._run_remote`**: The function in the same file that dispatches to a Neurochip Lava worker over HTTP. Currently wraps the response under a single population key via `_infer_output_population`.
- **`SimulatorRunResult`**: The Dart model in `neurocnl/frontend/lib/models/simulator.dart` that carries `spikes: Map<String, Map<String, List<int>>>` — one outer key per population.
- **`SimulatorPanel`**: The Flutter widget in `neurocnl/frontend/lib/widgets/simulator_panel.dart` that runs the simulator and renders result tabs. In Deploy-pane context (`initialBackend != null`), it currently does not write to `simulationProvider`.
- **`simulationProvider`**: The Riverpod `StateNotifierProvider<SimulationNotifier, SimulationState>` in `neurocnl/frontend/lib/providers/canvas/simulation_provider.dart`. Its `playback` field is what `CanvasSimulationSurface` reads.
- **`PreviewPlayback`**: The canvas playback model in `neurocnl/frontend/lib/models/canvas/preview.dart`. Carries `durationMs`, `nodes: List<PreviewNodePlayback>`, spike events, and a summary.
- **`CanvasSimulationSurface`**: The canvas-side widget that reads `simulationProvider.playback` and shows either the empty-state or `_SimulationDetailsPanel`.
- **`StudioLavaDeployNotifier`**: The existing Deploy-pane state notifier in `studio_lava_deploy_provider.dart`. Its `runResult` state must NOT be altered by the frontend fix.
- **actuator population**: The LIF population that is the final connection target in the NIR graph (`connections[-1]["post"]`).
- **silent population**: A LIF population for which no neuron fires during the simulation (empty spike train). Must still appear as a key in `spikes` after the fix.

---

## Bug Details

### Bug Condition

**Root Cause A — Backend single-monitor recording:**
The bug manifests when `_run_in_process` is called with a NIR graph that contains more than one LIF/CubaLIF population. The function selects `target_pop_name` as the last connection target and creates exactly one `Monitor` probing only that process. All other LIF populations are wired but never monitored. After `target_process.run(...)` returns, `monitor.get_data()` contains data for only `target_pop_name`, so `LavaSimulatorResult.spikes` has exactly one key regardless of graph size.

The same defect affects `_run_remote`: `_infer_output_population` returns a single population name, and `_normalize_flat_spikes` wraps the flat spike dict under that single key.

**Formal Specification:**

```
FUNCTION isBugConditionBackend(graph, spikes_result)
  INPUT: graph of type nir.NIRGraph, spikes_result of type dict
  OUTPUT: boolean

  lif_count := COUNT(node IN graph.nodes WHERE isinstance(node, (nir.LIF, nir.CubaLIF)))
  RETURN lif_count > 1
         AND len(spikes_result.keys) < lif_count
END FUNCTION
```

**Root Cause B — Frontend missing simulationProvider write:**
The bug manifests when `SimulatorPanel` is rendered with `initialBackend != null` (Deploy-pane context) and a `lava_sim` run completes with `SimulatorRunSuccess`. The `build` method detects `runState is SimulatorRunSuccess` and renders the result tabs — but never writes to `simulationProvider`. `CanvasSimulationSurface`, which is rendered alongside `SimulatorPanel` in the Deploy-pane, reads `simulationProvider.playback`, which remains `null`, so it shows the empty-state placeholder.

```
FUNCTION isBugConditionFrontend(runState, simulationProviderState, context)
  INPUT: runState of type SimulatorRunState,
         simulationProviderState of type SimulationState,
         context.isDeployPane of type bool
  OUTPUT: boolean

  RETURN runState IS SimulatorRunSuccess
         AND context.isDeployPane == true
         AND runState.result.backendName == 'lava_sim'
         AND simulationProviderState.playback == null
END FUNCTION
```

### Examples

**Backend (Root Cause A):**
- **2-population feedforward template**: NIR graph has `input_pop → lif_1 → lif_2`. `_run_in_process` monitors only `lif_2`. `SimulatorRunResult.spikes` = `{"lif_2": {...}}`. `lif_1` is absent. Dynamics tab dropdown shows only `lif_2`.
- **3-population template**: NIR graph has `input → hidden → output`. Only `output` appears in `spikes`. Two populations are invisible in all result tabs.
- **Silent intermediate population**: `hidden` fires zero spikes but is a valid LIF node. After the fix it must appear in `spikes` with an empty neuron dict (`{}`).
- **Single-population template**: Only one LIF node. `isBugConditionBackend` returns `false`; behavior is unchanged.

**Frontend (Root Cause B):**
- **Deploy-pane lava_sim run**: User clicks "Run" in the Deploy pane. `SimulatorPanel` shows the Dynamics tab with spike data, but `CanvasSimulationSurface` shows "Run a preview to inspect...". `simulationProvider.playback` is `null`.
- **Standalone Simulate tab lava_sim run**: `initialBackend == null`. `CanvasSimulationSurface` is not shown alongside the panel, so no empty-state defect manifests. This is a non-bug input.

---

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- `snntorch_sim` runs MUST continue to return one key per LIF population in `SimulatorRunResult.spikes` — the backend fix does not touch any `snntorch_sim` code path.
- `snntorch_sim` voltage trace rendering in the Dynamics tab MUST continue to work, including animated overlay in `AnimatedSnnPlayback`.
- The Spike Raster tab MUST continue to render for any run with a non-empty `spikes` dict, regardless of backend.
- The "No spikes recorded" warning MUST continue to appear in the Warnings tab when `lava_sim` returns a silent network (all populations empty).
- HTTP 503 with `detail.error = "lava_sim_dependency_missing"` MUST continue to be returned and surfaced in the UI when Lava is not installed.
- `StudioLavaDeployNotifier.runResult` MUST NOT be modified by the frontend fix — only `simulationProvider` is written.
- The standalone Simulate tab (when `initialBackend == null`) MUST NOT be affected by the frontend change.
- `nir_summary.node_count` and `nir_summary.edge_count` MUST be unchanged — monitoring additional populations does not change NIR graph topology reporting.

**Scope:**
All inputs that do NOT satisfy `isBugConditionBackend` (single-LIF graphs) are unaffected by the backend fix. All inputs that do NOT satisfy `isBugConditionFrontend` (standalone panel, non-lava_sim backends, non-Deploy-pane context) are unaffected by the frontend fix.

---

## Hypothesized Root Cause

Based on the bug description and code inspection:

### Root Cause A — Backend

1. **Single-monitor instantiation**: `_run_in_process` creates `monitor = Monitor()` once outside the population loop, then calls `monitor.probe(target_process.s_out, timesteps)` for only `target_process`. The Lava `Monitor` API supports probing multiple processes, but only one probe is registered.

2. **`target_pop_name` selection**: The code explicitly selects the last connection target as the single monitored population — the selection logic itself is correct for a single-output use-case, but the decision to create only one monitor is the defect.

3. **`_run_remote` single-key wrapping**: `_infer_output_population` is a deliberate heuristic that returns the last LIF name. `_normalize_flat_spikes` wraps the flat worker response under that single name. The remote worker may already return per-population data or may need an updated request parameter — the fix needs to either request all-populations data or iterate over the response.

4. **`_extract_spikes_from_monitor` architecture**: The helper is designed for a single process — it takes `population_process: Any` as a positional argument. The fix will either call it per-population or extend it to accept a `dict[str, Any]` of processes.

### Root Cause B — Frontend

1. **Separate data flows never bridged**: `SimulatorPanel` writes to `simulatorRunProvider(backendName)` (a scoped Riverpod provider for panel state). `CanvasSimulationSurface` reads `simulationProvider` (the canvas WebSocket/polling provider). These are two distinct providers that were never connected in the Deploy-pane layout.

2. **No post-run side-effect in `SimulatorPanel`**: The `_run()` method dispatches to `simulatorRunProvider(backendName).notifier.run(...)`. There is no `ref.listen` or `didChangeDependencies` logic in `_SimulatorPanelState` that observes `SimulatorRunSuccess` and forwards it to `simulationProvider`.

3. **`PreviewPlayback` conversion not yet implemented for `SimulatorRunResult`**: `PreviewPlayback` has `fromLegacyResults` and `fromJson` factory constructors, but no factory that accepts `SimulatorRunResult.spikes` (`Map<String, Map<String, List<int>>>`). The conversion logic needs to be added (either as a new factory or as a standalone function).

---

## Correctness Properties

Property 1: Bug Condition — All LIF Populations Recorded by lava_sim

_For any_ NIR graph where the bug condition holds (graph contains ≥ 2 LIF/CubaLIF
populations), the fixed `LavaSimulatorAdapter` (both `_run_in_process` and
`_run_remote`) SHALL return a `LavaSimulatorResult.spikes` dict with exactly one key
per LIF/CubaLIF population in the NIR graph. Silent populations (zero spikes) SHALL
be present as keys mapping to an empty neuron dict. The key set SHALL equal the set
of all node names whose type is `nir.LIF` or `nir.CubaLIF` in the compiled graph.

**Validates: Requirements 2.1, 2.2**

Property 2: Bug Condition — Canvas Deploy-Pane Populated After lava_sim Run

_For any_ `SimulatorRunSuccess` state where `result.backendName == 'lava_sim'` and `SimulatorPanel` is in Deploy-pane context (`initialBackend != null`), the fixed `_SimulatorPanelState` SHALL write a non-null `PreviewPlayback` value to `simulationProvider` (via `simulationProvider.notifier`) with `durationMs = result.timesteps × result.metadata['dt_ms']` and one `PreviewNodePlayback` per key in `result.spikes`. This SHALL cause `CanvasSimulationSurface` to render `_SimulationDetailsPanel` instead of `_SimulationEmptyState`.

**Validates: Requirements 2.5**

Property 3: Preservation — Non-Buggy Inputs Unchanged

_For any_ input where neither bug condition holds — including `snntorch_sim` runs, single-LIF `lava_sim` graphs, standalone-panel lava_sim runs, or silent-network lava_sim runs — the fixed code SHALL produce the same observable behavior as the original code: same `spikes` dict shape, same warnings, same `StudioLavaDeployNotifier.runResult` state, same `simulationProvider` state (null `playback` for non-Deploy-pane contexts), and same Dynamics/Spike Raster/Warnings tab rendering.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**

---

## Fix Implementation

### Changes Required

#### Fix A — Backend: Attach a Monitor Per LIF Population

**File**: `neurocnl/neurocnl/runtime/lava_simulator.py`

**Function**: `LavaSimulatorAdapter._run_in_process`

**Specific Changes**:

1. **Replace single `monitor = Monitor()` with per-population monitors**: After the population processes dict is built and connections are wired, iterate over every entry in `population_processes` and create one `Monitor` per LIF process:

   ```python
   monitors: dict[str, Monitor] = {}
   for pop_name, proc in population_processes.items():
       m = Monitor()
       m.probe(proc.s_out, timesteps)
       monitors[pop_name] = m
   ```

2. **Run using any population process as the entry point**: Lava's runtime is graph-wide; calling `.run()` on any connected process starts the whole network. Keep `target_process.run(...)` for the `RunSteps` call (or use the first population process if preferred) — the runner process choice doesn't change which monitors collect data.

3. **Collect results from all monitors**: After `run()` completes, iterate `monitors.items()` and call `_extract_spikes_from_monitor` per population:

   ```python
   spikes: dict[str, dict[str, list[int]]] = {}
   for pop_name, m in monitors.items():
       raw = m.get_data()
       pop_spikes = _extract_spikes_from_monitor(raw, population_processes[pop_name], pop_name)
       # Always include the key, even if the population is silent
       spikes[pop_name] = pop_spikes.get(pop_name, {})
   ```

4. **Update the `stop()` call**: Calling `.stop()` on any one process stops the whole Lava runtime. Keep `target_process.stop()` in the `finally` block unchanged.

5. **Update the silent-network warning**: The warning should now reference all populations, not just `target_pop_name`. Check `if not any(spikes.values()):` (i.e., all populations are silent) before emitting the warning.

**Function**: `LavaSimulatorAdapter._run_remote`

**Specific Changes**:

6. **Request all-population data**: Inspect whether `LavaIO.compile_and_run_remote()` accepts a parameter for returning all populations. If so, pass it. If the remote worker always returns a flat `{neuron_idx: [...]}` dict, the fix is to loop over all LIF names in the graph and wrap each subset:

   ```python
   lif_names = [
       name for name, node in graph.nodes.items()
       if isinstance(node, (nir.LIF, nir.CubaLIF))
   ]
   # If worker returns per-population keyed response:
   spikes = {name: {k: v for k, v in raw_spikes.get(name, {}).items() if v}
             for name in lif_names}
   # Fallback: if worker returns a flat dict, assign all data to inferred output pop
   # and create empty entries for the rest (preserving existing single-key behavior
   # for the output pop while adding empty keys for others)
   ```

   The remote fix must not break the existing contract with the Neurochip worker; if the worker response shape cannot be changed, the minimum correct fix is to add empty-dict entries for all non-output LIF populations.

---

#### Fix B — Frontend: Write PreviewPlayback to simulationProvider After Deploy-Pane Run

**File**: `neurocnl/frontend/lib/widgets/simulator_panel.dart`

**Class**: `_SimulatorPanelState`

**Specific Changes**:

1. **Add a `ref.listen` on `simulatorRunProvider` in `initState` / using `ConsumerStatefulWidget` lifecycle**: In the `build` method (or via `ref.listen` in `initState`), observe when `runState` transitions to `SimulatorRunSuccess` while `widget.initialBackend != null`. On that transition, call the conversion and write:

   ```dart
   // Inside _SimulatorPanelState, added to build() or via ref.listen:
   if (locked && runState is SimulatorRunSuccess) {
     WidgetsBinding.instance.addPostFrameCallback((_) {
       if (!mounted) return;
       final result = (runState as SimulatorRunSuccess).result;
       final playback = _buildPreviewPlayback(result);
       ref.read(simulationProvider.notifier).restoreSnapshotFromLavaResult(playback);
     });
   }
   ```

   Using `addPostFrameCallback` avoids mutating provider state during `build`.

2. **Add `_buildPreviewPlayback` conversion helper**: A private function that converts `SimulatorRunResult` → `PreviewPlayback`:

   ```dart
   PreviewPlayback _buildPreviewPlayback(SimulatorRunResult result) {
     final dtMs = (result.metadata['dt_ms'] as num?)?.toDouble() ?? 1.0;
     final durationMs = result.timesteps * dtMs;
     final nodes = <PreviewNodePlayback>[];
     final spikeEvents = <PreviewSpikeEvent>[];

     for (final popEntry in result.spikes.entries) {
       final nodeId = popEntry.key;
       final spikeTrains = <String, List<double>>{};
       for (final neuronEntry in popEntry.value.entries) {
         final neuronId = '$nodeId:${neuronEntry.key}';
         final times = neuronEntry.value.map((t) => t.toDouble()).toList();
         spikeTrains[neuronId] = times;
         for (final timeMs in times) {
           spikeEvents.add(PreviewSpikeEvent(
             nodeId: nodeId,
             neuronId: neuronId,
             neuronIndex: int.tryParse(neuronEntry.key) ?? 0,
             timeMs: timeMs * dtMs,
           ));
         }
       }
       final spikeCount = spikeTrains.values
           .fold<int>(0, (s, ts) => s + ts.length);
       nodes.add(PreviewNodePlayback(
         nodeId: nodeId,
         spikeTrains: spikeTrains,
         spikeCount: spikeCount,
       ));
     }

     return PreviewPlayback(
       durationMs: durationMs,
       nodes: nodes,
       spikeEvents: spikeEvents..sort((a, b) => a.timeMs.compareTo(b.timeMs)),
       summary: PreviewPlaybackSummary(
         totalSpikes: spikeEvents.length,
         activeNodeCount: nodes.where((n) => n.spikeCount > 0).length,
       ),
     );
   }
   ```

3. **Add `restoreSnapshotFromLavaResult` (or reuse `restoreSnapshot`)** in `SimulationNotifier`: The simplest approach is to call the existing `state = state.copyWith(playback: playback, status: SimulationStatus.completed, currentTime: 0.0, selectedNodeId: ...)` pattern directly through a new public method, or re-use the existing `restoreSnapshot` mechanism with a synthetic `PreviewResponse`. Adding a dedicated method keeps the intent clear:

   ```dart
   // In SimulationNotifier (simulation_provider.dart):
   void injectLavaPlayback(PreviewPlayback playback) {
     _stopPlaybackTimer();
     state = state.copyWith(
       status: SimulationStatus.completed,
       transportMode: PreviewTransportMode.none,
       playback: playback,
       currentTime: 0.0,
       clearError: true,
       selectedNodeId: _defaultNodeId(playback),
     );
   }
   ```

4. **Do NOT alter `StudioLavaDeployNotifier` state**: The conversion and `simulationProvider` write are purely additive side-effects of the `SimulatorPanel` success state. `studioLavaDeployProvider` state is owned by the Deploy-pane's own notifier and must not be modified.

---

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate each bug on the unfixed code, then verify the fix works correctly and preserves existing behavior.

---

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate both bugs BEFORE implementing the fixes. Confirm or refute the root cause analysis.

**Test Plan — Root Cause A (Backend)**:
Construct NIR graphs with multiple LIF populations and run `LavaSimulatorAdapter._run_in_process` on the unfixed code. Assert that `spikes` has as many keys as there are LIF nodes — these assertions will fail on unfixed code, confirming the single-monitor defect.

**Test Cases — Root Cause A**:
1. **Two-population in-process test**: Build a 2-LIF graph via `LavaIO`, call `_run_in_process`, assert `len(result.spikes) == 2` (will fail: only 1 key).
2. **Three-population in-process test**: 3-LIF graph, assert `len(result.spikes) == 3` (will fail: only 1 key).
3. **Silent intermediate population test**: 2-LIF graph where the first LIF fires zero spikes, assert both keys present (will fail: silent pop absent).
4. **Remote path population count test** (mocked HTTP): Provide a mocked `LavaIO.compile_and_run_remote()` response with flat spike data, assert `len(result.spikes) == 2` (will fail: only 1 key from `_normalize_flat_spikes`).

**Test Plan — Root Cause B (Frontend)**:
Build a `SimulatorPanel` widget test in Deploy-pane mode (`initialBackend = 'lava_sim'`). After a mocked successful run, assert `simulationProvider.playback != null` — this will fail on unfixed code because the panel never writes to `simulationProvider`.

**Test Cases — Root Cause B**:
1. **Deploy-pane playback population test**: Pump `SimulatorPanel(initialBackend: 'lava_sim')`, trigger a successful run with a 2-population `SimulatorRunResult`, assert `simulationProvider.playback` is non-null (will fail on unfixed code).
2. **CanvasSimulationSurface empty-state test**: Embed `CanvasSimulationSurface` alongside `SimulatorPanel` in the same widget tree, run the simulation, assert the empty-state widget is NOT shown (will fail on unfixed code).

**Expected Counterexamples**:
- `LavaSimulatorResult.spikes` has exactly 1 key for any multi-LIF graph — confirms the single-monitor defect.
- `simulationProvider.playback == null` after a Deploy-pane run — confirms the missing cross-provider write.

---

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed functions produce the expected behavior.

**Pseudocode:**
```
FOR ALL graph WHERE isBugConditionBackend(graph, spikes_result) DO
  result := LavaSimulatorAdapter_fixed.run(graph, ...)
  ASSERT len(result.spikes.keys) == count_lif_nodes(graph)
  ASSERT all_lif_names(graph) == set(result.spikes.keys)
END FOR

FOR ALL runState WHERE isBugConditionFrontend(runState, simProvState, ctx) DO
  await pumpSimulatorPanel(initialBackend='lava_sim')
  triggerRun(runState)
  ASSERT simulationProvider.playback != null
  ASSERT CanvasSimulationSurface shows _SimulationDetailsPanel
END FOR
```

---

### Preservation Checking

**Goal**: Verify that for all inputs where neither bug condition holds, the fixed code produces the same behavior as the original.

**Pseudocode:**
```
FOR ALL graph WHERE NOT isBugConditionBackend(graph, spikes_result) DO
  ASSERT LavaSimulatorAdapter_original.run(graph, ...) ≅
         LavaSimulatorAdapter_fixed.run(graph, ...)
END FOR

FOR ALL context WHERE NOT isBugConditionFrontend(...) DO
  ASSERT simulationProvider_original.state ≅
         simulationProvider_fixed.state
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because it generates many graph shapes and run contexts automatically, catching edge cases that manual unit tests miss.

**Test Cases**:
1. **snntorch_sim preservation**: Run `snntorch_sim` through `SimulatorPanel` (standalone), assert `spikes`, `voltages`, and all 5 result tabs render identically before and after the fix.
2. **Single-LIF lava_sim preservation**: Run a 1-LIF graph via `lava_sim`, assert `len(spikes) == 1` (same as before fix).
3. **Silent-network warning preservation**: Run a 2-LIF graph where no neurons fire, assert the Warnings tab shows "No spikes recorded" and Dynamics tab renders without exception.
4. **lava_sim missing-dependency preservation**: Simulate `LavaDispatchError` with `"lava_sim_dependency_missing"`, assert HTTP 503 is returned and the install-hint chip is shown.
5. **Standalone-panel playback non-interference**: Run `SimulatorPanel` without `initialBackend` (standalone), assert `simulationProvider.playback` remains null (the fix must not write to the canvas provider outside Deploy-pane context).
6. **StudioLavaDeployNotifier state non-interference**: After a Deploy-pane run, assert `studioLavaDeployProvider.state.runResult` is unchanged by the frontend fix.

---

### Unit Tests

- Test `_run_in_process` with a 2-LIF mocked Lava graph: assert `len(spikes) == 2` and both population keys are present.
- Test `_run_in_process` with a silent intermediate population: assert the silent population appears as a key mapping to `{}`.
- Test `_run_remote` with mocked `LavaIO.compile_and_run_remote()`: assert all LIF names from the graph appear as keys in `result.spikes`.
- Test `_buildPreviewPlayback` conversion in Dart: given a `SimulatorRunResult` with 2 populations, assert the resulting `PreviewPlayback.nodes.length == 2` and `durationMs == timesteps * dt_ms`.
- Test `SimulationNotifier.injectLavaPlayback`: assert `state.playback` is set, `state.status == completed`, `currentTime == 0`, and `selectedNodeId` matches the first active node.
- Test the `_SimulatorPanelState` Deploy-pane path: given `SimulatorRunSuccess` with `initialBackend != null`, assert `simulationProvider.notifier.injectLavaPlayback` is called exactly once.

### Property-Based Tests

- **Backend property (Fix Checking)**: For any randomly generated NIR graph with N LIF nodes (N ∈ [1, 8]), assert `len(LavaSimulatorAdapter_fixed.run(graph).spikes) == N`.
- **Backend preservation (Preservation Checking)**: For any single-LIF graph, assert the fixed adapter's `spikes` dict is identical to the original adapter's output.
- **Frontend property (Fix Checking)**: For any `SimulatorRunResult` with K populations (K ∈ [1, 6]) in Deploy-pane context, assert `simulationProvider.playback.nodes.length == K` after the run.
- **Frontend preservation (Preservation Checking)**: For any run in standalone-panel context (all backends, any result), assert `simulationProvider.playback` is null both before and after the run.
- **durationMs computation property**: For any `timesteps ∈ [1, 10000]` and `dt_ms ∈ [0.1, 100.0]`, assert `PreviewPlayback.durationMs == timesteps * dt_ms`.

### Integration Tests

- **Full Deploy-pane lava_sim flow**: Start with a basic CNL feedforward template in the canvas Deploy pane, run `lava_sim`, assert both `SimulatorPanel` Dynamics tab and `CanvasSimulationSurface` show non-empty data.
- **All-populations Dynamics tab**: After a 3-population `lava_sim` run, assert the Dynamics tab dropdown contains exactly 3 entries matching the NIR graph LIF node names.
- **Spike Raster all populations**: After a multi-population `lava_sim` run with at least one spike per population, assert the Spike Raster tab renders one neuron row per firing neuron across all populations.
- **snntorch_sim unaffected**: Run the same feedforward template with `snntorch_sim` before and after applying the fix, assert all 5 tabs render identically.
- **Silent-network integration**: Run a 2-LIF graph with `lava_sim` with a very low firing rate that produces zero spikes in all populations, assert Warnings tab shows the silent-network warning and Dynamics tab renders without crash.
