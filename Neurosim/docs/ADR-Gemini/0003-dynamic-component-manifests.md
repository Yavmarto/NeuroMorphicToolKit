# ADR 0003: Dynamic Component Manifests

## Status
Accepted

## Context
NeuroSim requires a UI populated with highly specialized components (neurons, synapses, encoders) which actively change based on the backend SDKs we support (LIF, AdaptiveLIF, STDP, etc.). Hardcoding these UI components logically scales poorly.

## Decision
We utilize JSON component manifest schemas (e.g. `lif_population.json` in `components/neurons/`) defining parameters, types, defaults, and bounds. The Flutter frontend dynamically parses these APIs to build the component library and property panels via Riverpod (`componentLibraryProvider`).

## Consequences
- **Positive:** Adding a new neural model requires only a JSON definition; zero Flutter UI recompilation is necessary.
- **Negative:** The backend and frontend must rigidly follow the `ComponentBlock` schemas, and missing or malformed JSON bounds can invisibly crash property panels.

## Status Update (2026-07-16 audit)
The standalone-Flutter-frontend framing in this ADR is no longer accurate. There is no `Neurosim/frontend/` directory (confirmed via directory listing of `Neurosim/`), and a repo-wide grep for `componentLibraryProvider` across all `.dart` files returns zero matches — that provider name does not exist in the current codebase. Per `Neurosim/README.md`, "the Neurosim visual canvas UI is embedded directly inside CNL Studio (the `neurocnl` module frontend) at the `/canvas` route — it is not a standalone launcher card," and Neurosim backend routes are mounted by `suite_api` under `/api/neurosim`. The underlying JSON component-manifest approach (parameters, types, defaults, bounds defined per-component) may still hold conceptually, but the dynamic-parsing consumer is the `neurocnl` frontend's canvas route, not a separate Neurosim Flutter app with a `componentLibraryProvider`.
