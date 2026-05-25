# Implementation Plan

## Overview

Fixes two independent root causes of the lava_sim template display bug using the exploratory bugfix methodology:

- **Fix A (Backend)**: `lava_simulator.py` — replace the single `Monitor` with per-population monitors so `SimulatorRunResult.spikes` contains one key per LIF/CubaLIF population (not just the actuator).
- **Fix B (Frontend)**: `simulation_provider.dart` + `simulator_panel.dart` — add `injectLavaPlayback` to `SimulationNotifier` and wire a `ref.listen` in `_SimulatorPanelState` so a successful Deploy-pane run populates `simulationProvider.playback`, enabling `CanvasSimulationSurface` to render.

Wave ordering: Wave 1 (tasks 1–2, parallel) → Wave 2 (tasks 3–4, parallel) → Wave 3 (tasks 5–6) → Wave 4 (task 7).

## Task Dependency Graph

```json
{
  "waves": [
    {
      "wave": 1,
      "tasks": ["1", "2"],
      "description": "Write exploration and preservation tests in parallel (before any fix)"
    },
    {
      "wave": 2,
      "tasks": ["3", "4"],
      "description": "Apply Fix A (backend) and Fix B (frontend) in parallel — independent files"
    },
    {
      "wave": 3,
      "tasks": ["5", "6"],
      "description": "Verify exploration tests now pass and preservation tests still pass"
    },
    {
      "wave": 4,
      "tasks": ["7"],
      "description": "Final checkpoint — lint, type check, full test suite"
    }
  ]
}
```

## Tasks

- [ ] 1. Write bug condition exploration tests (BEFORE implementing any fix)
  - **Property 1: Bug Condition** - All LIF Populations Recorded by lava_sim (Backend) + Deploy-Pane Canvas Populated (Frontend)
  - **CRITICAL**: These tests MUST FAIL on unfixed code — failure confirms both bugs exist
  - **DO NOT attempt to fix the test or the code when tests fail**
  - **NOTE**: These tests encode the expected behavior; they will validate the fixes when they pass after implementation
  - **GOAL**: Surface counterexamples that demonstrate each root cause
  - **Scoped PBT Approach**: For Root Cause A, scope the property to graphs with exactly 2 LIF nodes (minimum reproducing case) to ensure deterministic reproduction; generalise to N ∈ [2, 8] for the full property run
  - **Backend (Root Cause A) — file: `neurocnl/neurocnl/runtime/lava_simulator.py`**:
    - Build a minimal 2-LIF NIR graph using `nir.NIRGraph` with nodes `{"input_pop": nir.LIF(...), "output_pop": nir.LIF(...)}` and an edge between them
    - Call `LavaSimulatorAdapter()._run_in_process(graph, timesteps=10, seed=42)` on unfixed code
    - Assert `len(result.spikes) == 2` — this FAILS because only 1 key (`output_pop`) is present, confirming the single-monitor defect (`isBugConditionBackend`: `lif_count=2` AND `len(spikes.keys)=1 < 2`)
    - Repeat with a 3-LIF graph; assert `len(result.spikes) == 3` — FAILS with 1 key
    - Build a 2-LIF graph where the first LIF fires zero spikes (silent); assert both population keys present — FAILS, silent pop absent
    - For the remote path: mock `LavaIO.compile_and_run_remote()` to return a flat `{"0": [1, 3, 5]}` dict; call `_run_remote` on unfixed code; assert `len(result.spikes) == 2` — FAILS with 1 key from `_normalize_flat_spikes`
    - Document all counterexamples (e.g. `"_run_in_process(2-LIF graph) → spikes has 1 key, expected 2"`)
  - **Frontend (Root Cause B) — file: `neurocnl/frontend/lib/widgets/simulator_panel.dart` + `simulation_provider.dart`**:
    - Write a Flutter widget test that pumps `ProviderScope(overrides: [...], child: SimulatorPanel(initialBackend: 'lava_sim'))` with a mocked `simulatorRunProvider` pre-seeded with `SimulatorRunSuccess` carrying a 2-population `SimulatorRunResult`
    - After pump, assert `container.read(simulationProvider).playback != null` — this FAILS on unfixed code because `_SimulatorPanelState` never calls `simulationProvider.notifier.injectLavaPlayback(...)` (`isBugConditionFrontend`: `runState IS SimulatorRunSuccess AND isDeployPane AND backendName=='lava_sim' AND playback==null`)
    - Also assert that the empty-state widget (`_SimulationEmptyState` / `_EmptyResultsPlaceholder`) is NOT shown in `CanvasSimulationSurface` — FAILS
    - Document counterexamples (e.g. `"Deploy-pane run → simulationProvider.playback is null"`)
  - Run all exploration tests on UNFIXED code
  - **EXPECTED OUTCOME**: All tests FAIL (this is correct — proves both bugs exist)
  - Mark task complete when tests are written, run, and all failures are documented
  - _Requirements: 1.1, 1.1a, 1.2, 1.3, 1.4, 1.5_

- [ ] 2. Write preservation property tests (BEFORE implementing any fix)
  - **Property 2: Preservation** - Non-Buggy Inputs Unchanged (snntorch_sim, single-LIF lava_sim, silent-network, missing-dependency, standalone panel)
  - **IMPORTANT**: Follow observation-first methodology — run UNFIXED code with non-buggy inputs, observe outputs, then write tests capturing those outputs
  - **GOAL**: Establish a baseline of correct behavior that must survive both fixes
  - **Backend preservation tests — file: `neurocnl/neurocnl/runtime/lava_simulator.py`**:
    - Observe: `LavaSimulatorAdapter()._run_in_process(single_lif_graph, ...)` on unfixed code returns `len(spikes) == 1` with the single population key present
    - Write property-based test: for all single-LIF NIR graphs (`lif_count == 1`, `isBugConditionBackend` returns `false`), assert `len(result.spikes) == 1` and the single LIF name is the key — PASSES on unfixed code
    - Observe: silent 2-LIF graph raises no exception; if no spikes fire, `spikes = {}` and `warnings` contains the silent-network message
    - Write test: when every population is silent, assert `result.warnings` contains a string matching `"no spikes"` (case-insensitive) and no `LavaDispatchError` is raised — PASSES on unfixed code
    - Observe: when `_is_lava_available()` returns `False` and no `worker_url`, `LavaDispatchError` is raised with message containing `"lava_sim_dependency_missing"` or install hint
    - Write test: mock `_is_lava_available` to return `False`, assert `LavaDispatchError` is raised — PASSES on unfixed code
    - Observe: `nir_summary.node_count` and `nir_summary.edge_count` are computed in the API layer, not in `lava_simulator.py` — assert `result.spikes` dict shape changes do not alter NIR summary fields
  - **Frontend preservation tests — files: `simulator_panel.dart` + `simulation_provider.dart`**:
    - Observe: `SimulatorPanel` with `initialBackend == null` (standalone mode) never writes to `simulationProvider`; `simulationProvider.playback` stays `null` after a successful run
    - Write property-based test: for any `SimulatorRunSuccess` result with any backend, when `initialBackend == null`, assert `simulationProvider.playback` is `null` both before and after the run — PASSES on unfixed code
    - Observe: `snntorch_sim` runs in standalone panel produce correct spike + voltage results in all 5 tabs; `SimulatorRunResult.voltages` is populated
    - Write test: pump standalone `SimulatorPanel` with `snntorch_sim` mocked result containing voltages, assert all 5 tab labels visible and `_DynamicsTab` renders without error — PASSES on unfixed code
    - Observe: `StudioLavaDeployNotifier.runResult` is set after a Deploy-pane run and is not disturbed by `simulationProvider` state changes
    - Write test: assert `studioLavaDeployProvider.state.runResult` is unchanged after any `simulationProvider.notifier.injectLavaPlayback(...)` call — PASSES on unfixed code
    - Write property-based test for `durationMs` computation: for any `timesteps ∈ [1, 10000]` and `dt_ms ∈ [0.1, 100.0]`, assert that a future `_buildPreviewPlayback` produces `durationMs == timesteps * dt_ms` (write as a pending/skipped test now; it will pass once `_buildPreviewPlayback` is implemented)
  - Run all preservation tests on UNFIXED code
  - **EXPECTED OUTCOME**: All preservation tests PASS (confirms baseline behavior to protect)
  - Mark task complete when tests are written, run on unfixed code, and all pass
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [ ] 3. Apply Fix A — Backend: attach a Monitor per LIF population
  - **File**: `neurocnl/neurocnl/runtime/lava_simulator.py`

  - [ ] 3.1 Replace single `Monitor` with per-population monitors in `_run_in_process`
    - Remove the single `monitor = Monitor()` / `monitor.probe(target_process.s_out, timesteps)` block
    - After the connections loop, add a per-population monitor loop:
      ```python
      monitors: dict[str, Monitor] = {}
      for pop_name, proc in population_processes.items():
          m = Monitor()
          m.probe(proc.s_out, timesteps)
          monitors[pop_name] = m
      ```
    - Keep `target_process.run(condition=RunSteps(num_steps=timesteps), run_cfg=Loihi2SimCfg())` unchanged as the runtime entry point (Lava graph-wide execution)
    - After `run()` returns, replace the single `monitor.get_data()` call with an iteration over all monitors:
      ```python
      spikes: dict[str, dict[str, list[int]]] = {}
      for pop_name, m in monitors.items():
          raw = m.get_data()
          pop_spikes = _extract_spikes_from_monitor(raw, population_processes[pop_name], pop_name)
          spikes[pop_name] = pop_spikes.get(pop_name, {})  # include silent pops as {}
      ```
    - Update the silent-network check: replace `if not spikes:` with `if not any(spikes.values()):` so the warning fires when all populations are silent (all empty dicts) rather than only when the `spikes` dict itself is empty
    - Keep `target_process.stop()` in the `finally` block unchanged (stops the entire Lava runtime)
    - _Bug_Condition: `isBugConditionBackend(graph, spikes_result)` where `lif_count > 1 AND len(spikes_result.keys) < lif_count`_
    - _Expected_Behavior: `len(result.spikes) == lif_count AND set(result.spikes.keys) == all_lif_names(graph)`, silent populations present as `{}`_
    - _Preservation: single-LIF graphs unchanged; silent-network warning still fires; `LavaDispatchError` still raised when Lava unavailable; `nir_summary` fields untouched_
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.4, 3.5, 3.7_

  - [ ] 3.2 Fix `_run_remote` to return all LIF population keys
    - Extract all LIF/CubaLIF names from the graph before dispatching:
      ```python
      lif_names = [
          name for name, node in graph.nodes.items()
          if isinstance(node, (nir.LIF, nir.CubaLIF))
      ]
      ```
    - Replace the `_normalize_flat_spikes(raw_spikes, output_pop)` call with a per-population wrap; if the remote worker returns a population-keyed dict use it directly, otherwise assign the flat response to the inferred output pop and add empty entries for the rest:
      ```python
      # If worker returns {pop_name: {neuron_idx: [...]}} (population-keyed)
      if lif_names and all(k in lif_names for k in raw_spikes if raw_spikes):
          spikes = {name: {k: v for k, v in raw_spikes.get(name, {}).items() if v}
                    for name in lif_names}
      else:
          # Flat response: assign to inferred output pop, add empty entries for others
          output_pop = _infer_output_population(graph)
          spikes = {name: ({k: v for k, v in raw_spikes.items() if v}
                           if name == output_pop else {})
                    for name in lif_names}
      ```
    - Update the silent-network warning to reference all populations, not just `output_pop`
    - _Bug_Condition: `isBugConditionBackend` applies equally to the remote path_
    - _Expected_Behavior: `result.spikes` has one key per LIF/CubaLIF node, consistent with the in-process path_
    - _Preservation: remote path error handling and `execution_time_ms` reporting unchanged_
    - _Requirements: 2.1a, 3.7_

- [ ] 4. Apply Fix B — Frontend: write `PreviewPlayback` to `simulationProvider` after Deploy-pane lava_sim run
  - **Files**: `neurocnl/frontend/lib/providers/canvas/simulation_provider.dart` and `neurocnl/frontend/lib/widgets/simulator_panel.dart`

  - [ ] 4.1 Add `injectLavaPlayback` method to `SimulationNotifier` in `simulation_provider.dart`
    - Add the following public method to `SimulationNotifier` after the existing `restoreSnapshot` method:
      ```dart
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
    - This method reuses the existing `_stopPlaybackTimer()` and `_defaultNodeId()` private helpers; no new helpers needed
    - `StudioLavaDeployNotifier` state is NOT touched here — this method only mutates `SimulationNotifier`'s own state
    - _Bug_Condition: `isBugConditionFrontend` — `simulationProvider.playback == null` after a Deploy-pane lava_sim run_
    - _Expected_Behavior: after `injectLavaPlayback(playback)` is called, `state.playback != null`, `state.status == SimulationStatus.completed`, `state.currentTime == 0.0`, `state.selectedNodeId` set to first active node_
    - _Preservation: `restoreSnapshot`, `runPreview`, `play`, `pause`, `reset`, `stepForward` unchanged; `StudioLavaDeployNotifier.runResult` unaffected_
    - _Requirements: 2.5, 3.1, 3.2, 3.6_

  - [ ] 4.2 Add `_buildPreviewPlayback` helper to `_SimulatorPanelState` in `simulator_panel.dart`
    - Add the following private method to `_SimulatorPanelState`:
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
            for (final timeStep in times) {
              spikeEvents.add(PreviewSpikeEvent(
                nodeId: nodeId,
                neuronId: neuronId,
                neuronIndex: int.tryParse(neuronEntry.key) ?? 0,
                timeMs: timeStep * dtMs,
              ));
            }
          }
          final spikeCount =
              spikeTrains.values.fold<int>(0, (s, ts) => s + ts.length);
          nodes.add(PreviewNodePlayback(
            nodeId: nodeId,
            spikeTrains: spikeTrains,
            spikeCount: spikeCount,
          ));
        }

        spikeEvents.sort((a, b) => a.timeMs.compareTo(b.timeMs));
        return PreviewPlayback(
          durationMs: durationMs,
          nodes: nodes,
          spikeEvents: spikeEvents,
          summary: PreviewPlaybackSummary(
            totalSpikes: spikeEvents.length,
            activeNodeCount: nodes.where((n) => n.spikeCount > 0).length,
          ),
        );
      }
      ```
    - Import `PreviewPlayback`, `PreviewNodePlayback`, `PreviewSpikeEvent`, `PreviewPlaybackSummary` from `'../models/canvas/preview.dart'` at the top of `simulator_panel.dart`
    - Import `'../providers/canvas/simulation_provider.dart'` for `simulationProvider`
    - _Expected_Behavior: `durationMs == result.timesteps * dt_ms`; one `PreviewNodePlayback` per key in `result.spikes`; `spikeEvents` sorted by `timeMs` ascending_
    - _Requirements: 2.5_

  - [ ] 4.3 Wire the Deploy-pane success transition to `injectLavaPlayback` in `simulator_panel.dart`
    - In `_SimulatorPanelState`, add a `ref.listen` call in `build()` that fires only in Deploy-pane context (`widget.initialBackend != null`):
      ```dart
      // Inside build(), before the `if (locked)` layout branch:
      ref.listen<SimulatorRunState>(
        simulatorRunProvider(_selectedBackend),
        (previous, next) {
          if (!mounted) return;
          if (widget.initialBackend == null) return;
          if (next is! SimulatorRunSuccess) return;
          if (previous is SimulatorRunSuccess &&
              previous.result == next.result) return; // deduplicate
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final playback = _buildPreviewPlayback(next.result);
            ref.read(simulationProvider.notifier).injectLavaPlayback(playback);
          });
        },
      );
      ```
    - The `addPostFrameCallback` wrapper prevents mutating provider state during `build`
    - The `previous == next` guard prevents re-injecting on unrelated rebuilds
    - This logic is gated on `widget.initialBackend != null` — standalone panel (`initialBackend == null`) is completely unaffected
    - `StudioLavaDeployNotifier` is not read or modified here
    - _Bug_Condition: `isBugConditionFrontend` — Deploy-pane + `SimulatorRunSuccess` + `playback == null`_
    - _Expected_Behavior: after a Deploy-pane run, `simulationProvider.playback != null`; `CanvasSimulationSurface` renders `_SimulationDetailsPanel` instead of empty-state_
    - _Preservation: standalone panel unaffected; `studioLavaDeployProvider.state` unaffected; non-lava_sim Deploy-pane runs also get `simulationProvider` updated (correct behavior, no regression)_
    - _Requirements: 2.5, 3.5, 3.6_

- [ ] 5. Verify bug condition exploration tests now pass (after both fixes applied)

  - [ ] 5.1 Re-run backend bug condition test (Property 1: Expected Behavior — Backend)
    - **Property 1: Expected Behavior** - All LIF Populations Recorded by lava_sim
    - **IMPORTANT**: Re-run the SAME tests written in task 1 — do NOT write new tests
    - Re-run the 2-LIF in-process test: assert `len(result.spikes) == 2` and `set(result.spikes.keys) == {"input_pop", "output_pop"}`
    - Re-run the 3-LIF in-process test: assert `len(result.spikes) == 3`
    - Re-run the silent intermediate population test: assert both keys present, silent pop maps to `{}`
    - Re-run the remote path mock test: assert `len(result.spikes) == 2`
    - **EXPECTED OUTCOME**: All backend exploration tests PASS (confirms Fix A resolves the single-monitor defect)
    - _Requirements: 2.1, 2.1a, 2.2, 2.3, 2.4_

  - [ ] 5.2 Re-run frontend bug condition test (Property 1: Expected Behavior — Frontend)
    - **Property 1: Expected Behavior** - Deploy-Pane Canvas Populated After lava_sim Run
    - **IMPORTANT**: Re-run the SAME widget tests written in task 1 — do NOT write new tests
    - Re-run: pump `SimulatorPanel(initialBackend: 'lava_sim')` with mocked `SimulatorRunSuccess`; assert `simulationProvider.playback != null`
    - Assert `simulationProvider.playback.nodes.length == 2` (matches the 2-population mock result)
    - Assert `simulationProvider.status == SimulationStatus.completed`
    - Assert `CanvasSimulationSurface` does NOT show the empty-state widget
    - **EXPECTED OUTCOME**: All frontend exploration tests PASS (confirms Fix B resolves the missing cross-provider write)
    - _Requirements: 2.5_

- [ ] 6. Verify preservation tests still pass (after both fixes applied)
  - **Property 2: Preservation** - Non-Buggy Inputs Unchanged
  - **IMPORTANT**: Re-run the SAME tests written in task 2 — do NOT write new tests
  - Re-run all backend preservation tests:
    - Single-LIF graph still returns `len(spikes) == 1` ✓
    - Silent all-populations network still emits the silent-network warning, no exception ✓
    - `LavaDispatchError` still raised when Lava unavailable ✓
  - Re-run all frontend preservation tests:
    - Standalone panel (`initialBackend == null`) → `simulationProvider.playback` stays `null` after any run ✓
    - `snntorch_sim` standalone run → all 5 tabs render, voltage overlay present ✓
    - `studioLavaDeployProvider.state.runResult` unchanged after `injectLavaPlayback` is called ✓
    - `durationMs == timesteps * dt_ms` property ✓
  - **EXPECTED OUTCOME**: All preservation tests PASS (confirms no regressions introduced)
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [ ] 7. Checkpoint — all tests pass, lint and type checks clean
  - Run backend unit tests: `python3 -m pytest neurocnl/tests/ -k "lava" -v` — all pass
  - Run Dart analyzer on changed files: `dart analyze neurocnl/frontend/lib/widgets/simulator_panel.dart neurocnl/frontend/lib/providers/canvas/simulation_provider.dart` — zero errors
  - Run Flutter widget tests: `flutter test neurocnl/frontend/test/ --run-tests` — all pass
  - Confirm no new warnings introduced in `lava_simulator.py` by running `python3 -m ruff check neurocnl/neurocnl/runtime/lava_simulator.py`
  - Ensure all tests pass; ask the user if any questions arise

## Notes

- Fix A and Fix B are fully independent — they touch different files and different language stacks (Python backend vs. Dart frontend). They can be implemented and reviewed in parallel.
- The Lava `Monitor` API supports probing multiple processes simultaneously. Calling `.run()` on any one connected process starts the entire Lava runtime graph, so keeping `target_process.run(...)` as the entry point in the `finally` block is correct and sufficient.
- The `ref.listen` hook in `_SimulatorPanelState` is gated on `widget.initialBackend != null`. This ensures standalone Simulate-tab runs (`initialBackend == null`) never write to `simulationProvider`, preserving requirement 3.6.
- `StudioLavaDeployNotifier.runResult` must NOT be modified by Fix B. The fix is purely additive: it writes to `simulationProvider` as a side-effect of `SimulatorRunSuccess`, without touching the Deploy-pane's own state notifier.
- Silent populations (zero spikes) must appear as keys in `result.spikes` mapping to `{}` after Fix A. The silent-network warning check must be updated from `if not spikes:` to `if not any(spikes.values()):` to preserve the existing warning behavior.
- Test files should follow the project's existing test conventions. Read `neurocnl/AGENTS.md` before writing any new test files.
