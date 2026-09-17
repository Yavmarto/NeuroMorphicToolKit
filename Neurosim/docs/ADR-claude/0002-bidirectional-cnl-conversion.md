# ADR 0002: Bidirectional CNL Conversion

## Status
Accepted

## Context
Users may specify SNN models either by drawing on the visual canvas or by writing NeuroCNL natural language specifications. Both representations must stay synchronized to avoid divergence.

## Decision
Implement two conversion services: `cnl_to_graph.py` (parses CNL sentences into CanvasGraph using regex pattern matching for population and connection sentences) and `graph_to_cnl.py` (serializes CanvasGraph back into CNL text). A `neurocnl_bridge.py` interfaces with the neurocnl package for deeper semantic operations.

## Consequences
- **Positive:** Users can switch between visual and textual editing freely; CNL specs serve as version-controllable text representations of visual designs.
- **Negative:** Conversion fidelity is limited by the regex parser's coverage of CNL grammar; round-trip conversions may lose layout positioning information.

## Status Update (2026-07-16 audit)
The two-service, regex-based design described above has been superseded. `neurocnl/neurosim/app/services/cnl_to_graph.py`'s module docstring now states directly: "The legacy biological-grammar repair path (`cnl_to_graph`, `parse_semantic_statements`, and the `MUST`/`sensory`/`motor` regex patterns) has been removed. All CNL → canvas conversion now goes through the NIR-native pipeline" (NIR-native CNL → `NIR_CNL_Parser` → `NIR_Compiler` → `serialize_nir_to_canvas_graph`). Neither `graph_to_cnl.py` nor `neurocnl_bridge.py` exist under `neurocnl/neurosim/app/services/` any longer (verified via directory listing). The NIR-native replacement path is documented in `neurocnl/neurosim/app/services/nir_support.py`, and live CNL sync is exposed via the `/api/neurosim/parse-cnl` endpoint. This ADR's original decision text is left unmodified above for historical record.
