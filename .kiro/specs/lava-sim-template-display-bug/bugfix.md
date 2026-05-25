# Bugfix Requirements Document

## Introduction

When running a basic CNL template in CNL Studio, the Lava simulator (`lava_sim`) shows only the actuator (output) neuron population in the neuron list and renders nothing during playback. Running the same template with the snnTorch simulator (`snntorch_sim`) correctly shows all neuron populations — including the actuator — and playback works fine.

The bug has two root causes:

1. **Backend — single-population recording**: `LavaSimulatorAdapter._run_in_process` only attaches a Lava `Monitor` to the single *target* population (the last connection target, i.e. the actuator). All intermediate and input populations are wired but never monitored, so `lava_result.spikes` contains only one population key. The `SimulatorRunResult` returned by `POST /api/simulators/run` therefore has only one entry in its `spikes` dict for `lava_sim`, while `snntorch_sim` records every LIF population.

2. **Frontend — playback empty for `lava_sim`**: `CanvasSimulationSurface` reads from `simulationProvider` (the canvas `PreviewPlayback` model built from the canvas-preview WebSocket/polling API, not from `SimulatorRunResult`). `SimulatorPanel`'s Dynamics tab, by contrast, reads `SimulatorRunResult.spikes` directly via `AnimatedSnnPlayback`. Neither surface cross-feeds the other: when `SimulatorPanel` is used in the Deploy-pane context for `lava_sim`, the canvas `simulationProvider.playback` is `null`, so `CanvasSimulationSurface` shows the empty-state widget instead of any simulation data. The Dynamics tab in `SimulatorPanel` does receive the sparse single-population `spikes` dict but `_DynamicsTabState._populations` is derived exclusively from `result.spikes.keys` — so only that one actuator population key is surfaced in the dropdown.

## Glossary

- **LIF population**: any node in the NIR graph whose type is `nir.LIF` or `nir.CubaLIF`
- **basic CNL template**: any CNL Studio built-in template that compiles to a NIR graph with ≥ 2 LIF populations (e.g. the default feedforward template)
- **actuator population**: the LIF population that is the final connection target in the NIR graph (i.e. `connections[-1].post`)
- **silent population**: a LIF population for which no neuron fires during the simulation (zero spike events recorded)
- **Deploy-pane context**: the canvas tab where both `CanvasSimulationSurface` and `SimulatorPanel` are visible side-by-side

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN a basic CNL template is run with `lava_sim` via the in-process path THEN the system records spikes only for the actuator population (last connection target), omitting all other LIF populations present in the NIR graph; `SimulatorRunResult.spikes` therefore contains exactly one key regardless of how many LIF populations exist in the graph

1.1a WHEN a basic CNL template is run with `lava_sim` via the remote worker path THEN `_infer_output_population` selects a single output population and `_normalize_flat_spikes` wraps only that population's data, producing the same single-key defect as the in-process path

1.1b WHEN a LIF population is wired in the NIR graph but not monitored (because it is not the target population) THEN it produces no entry in `lava_result.spikes`, even if neurons in that population fire during the simulation

1.2 WHEN `lava_sim` results are displayed in the Dynamics tab population dropdown THEN the system shows only the single recorded actuator population because `_DynamicsTabState._populations` is constructed solely from `result.spikes.keys` and `result.voltages.keys`; all other LIF populations are absent

1.3 WHEN the Dynamics tab playback is triggered for a `lava_sim` run THEN the system renders no animation for non-actuator populations because their spike data was never recorded or returned

1.4 WHEN the Spike Raster tab is displayed after a `lava_sim` run THEN the system shows spike activity only for the single recorded actuator population, rather than all populations in the network

1.5 WHEN a `lava_sim` result is used in the canvas Deploy-pane context (where `CanvasSimulationSurface` is shown alongside `SimulatorPanel`) THEN the system shows the empty-state placeholder ("Run a preview to inspect...") because `simulationProvider.playback` is never populated from `SimulatorRunResult` data

### Expected Behavior (Correct)

2.1 WHEN a basic CNL template is run with `lava_sim` via the in-process path THEN the system SHALL attach a Lava `Monitor` to every LIF population in the NIR graph (every `nir.LIF` or `nir.CubaLIF` node), collect each population's `s_out` spike data, and return `SimulatorRunResult.spikes` with one key per LIF population; a population key SHALL be present even if the population is silent (empty spike train list)

2.1a WHEN a basic CNL template is run with `lava_sim` via the remote worker path THEN the system SHALL request spike data for all LIF populations in the NIR graph (not only the inferred output population) and return `SimulatorRunResult.spikes` with one key per LIF population, consistent with the in-process path behavior

2.2 WHEN `lava_sim` results are displayed in the Dynamics tab population dropdown THEN the system SHALL show one dropdown entry per `nir.LIF` or `nir.CubaLIF` node in the compiled NIR graph; the count SHALL match the number shown by `snntorch_sim` for the same template

2.3 WHEN the Dynamics tab playback is triggered for a `lava_sim` run THEN `AnimatedSnnPlayback` SHALL receive a non-empty `spikes` map and render the playback cursor; the default selected population SHALL be the alphabetically-first population whose spike train list contains at least one timestep (matching the sort order used by `_DynamicsTabState`)

2.4 WHEN the Spike Raster tab is displayed after a `lava_sim` run THEN the system SHALL render one neuron row per neuron across all LIF populations that have at least one spike, ordered by population (insertion order) then by neuron index ascending within each population

2.5 WHEN a `lava_sim` `SimulatorRunResult` becomes available in the Deploy-pane context THEN the system SHALL convert `SimulatorRunResult.spikes` into a `PreviewPlayback` value (using `durationMs = timesteps × dt_ms`) and write it to `simulationProvider`, enabling `CanvasSimulationSurface` to render the playback slider, raster, and node dropdown with the Lava spike data; this conversion SHALL NOT alter the `StudioLavaDeployNotifier` run-result state

### Unchanged Behavior (Regression Prevention)

3.1 WHEN a basic CNL template is run with `snntorch_sim` THEN the system SHALL CONTINUE TO return at least one entry per LIF population in `SimulatorRunResult.spikes` and each population SHALL appear in the Dynamics tab population dropdown

3.2 WHEN `snntorch_sim` produces voltage traces THEN the system SHALL CONTINUE TO render membrane potential traces in the Dynamics tab for `snntorch_sim` runs, including the animated voltage overlay in `AnimatedSnnPlayback`

3.3 WHEN any simulator run completes with `status = "completed"` and a non-empty `spikes` dict THEN the system SHALL CONTINUE TO display the Spike Raster tab with a raster plot containing at least one neuron row

3.4 WHEN a `lava_sim` run returns zero spikes for every population (silent network) THEN the system SHALL CONTINUE TO display the Warnings tab with the "No spikes recorded" warning visible; the Dynamics tab SHALL render without an unhandled exception and SHALL NOT navigate away from the simulator panel

3.5 WHEN `lava_sim` is unavailable (missing dependency or no worker URL configured) THEN the system SHALL CONTINUE TO return HTTP 503 with `detail.error = "lava_sim_dependency_missing"` and the simulator panel SHALL display a chip whose text contains the install-hint string from `detail.hint`

3.6 WHEN a `snntorch_sim` run returns results in the Standalone Simulate tab THEN the system SHALL CONTINUE TO display all five tabs — Dynamics, Spike Raster, Output Summary, Warnings, and NIR Support — each in a rendered, non-error state

3.7 WHEN multiple CNL templates with different topology sizes are run with `lava_sim` THEN the system SHALL CONTINUE TO report `nir_summary.node_count` equal to the number of population nodes in the NIR graph and `nir_summary.edge_count` equal to the number of directed connection edges in the NIR graph, regardless of how many populations are now monitored
