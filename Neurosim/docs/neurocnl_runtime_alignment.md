# NeuroCNL Runtime Alignment Limits

NeuroSim now reports whether a design is backed by the shared `neurocnl` runtime, only approximately supported through a local NeuroSim path, or unsupported.

## Shared Runtime Today

- `faithful` preview support currently means the canonical two-node sensory -> motor reflex graph can run through the shared NeuroCNL generator path.
- Canonical reflex-arc sweep jobs that vary node-local preview parameters such as `threshold`, `tau_ref`, or `tau_rc` still report `faithful` when NeuroSim can execute the authored graph exactly through its local Nengo preview builder, even if the shared NeuroCNL generator would collapse those population-specific runtime values.
- CNL remains the canonical source format for saving and exporting NeuroSim designs.

## Approximate Paths

- Empty graphs are still treated as a local no-op and reported as `approximate`.
- Small non-canonical designs that do not exceed the reflex-arc topology can still surface `approximate` validation metadata when NeuroSim is only describing local behavior rather than shared NeuroCNL execution.
- Python, NeuroML, NIR, and SVG exports for the canonical two-node reflex graph are still produced by NeuroSim-local serializers or visual scaffolds and are therefore reported as approximate unless explicitly unsupported.

## Unsupported Paths

- Graph topologies that exceed the canonical two-node sensory -> motor reflex arc now fail closed for preview, sweep, validation-backed runtime assessment, and local backend exports.
- NeuroSim no longer silently falls back to local execution for those multi-node topologies; users must either stay within the truthful reflex-arc runtime or wait for native multi-node synthesis support.
- Graphs that cannot be parsed, lowered, or planned truthfully through NeuroCNL are reported as `unsupported`.
- Sweep jobs inherit the worst-case preview support across all requested parameter steps and fail closed when any step is unsupported.
- The one intentional exception is a canonical reflex-arc sweep over population-specific preview parameters: those steps remain `faithful` because NeuroSim executes the authored graph directly rather than degrading the result to the shared-generator approximation label.
- C export remains blocked because NeuroSim only has a local scaffold and no truthful shared NeuroCNL-backed export path.

## Upstream Boundaries

- Broader end-to-end parse -> validate -> generate -> simulate -> export regression ownership remains in `neurocnl` issue 26.
- Expanding the shared runtime beyond the current canonical reflex topology depends on stable upstream NeuroCNL runtime primitives.
