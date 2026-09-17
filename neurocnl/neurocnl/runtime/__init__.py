"""neurocnl.runtime — shared runtime helpers for the CNL → NIR → Simulator pipeline.

Modules
-------
nir_support
    Classify a compiled ``nir.NIRGraph`` for a given simulator backend:
    exact, approximate, or unsupported.
stimulus
    Parse or generate deterministic spike-train stimuli for a compiled graph.
"""
