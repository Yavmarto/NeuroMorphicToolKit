---
title: "Mitigate Topological Drift Risk for Akida Sequential Invariants"
labels: ["maintenance", "validation", "hardware", "akida"]
---

## Audit Status

Status as of 2026-04-13: `partially implemented`

What is already landed:
- A shared `NetworkTopologyAnalyzer` now exists in `neurocnl/neurocnl/ir/topology.py`.
- Akida capability planning in `neurocnl/neurocnl/backends/akida_capabilities.py` instantiates that analyzer.

What is still open:
- `neurocnl/neurocnl/layers/akida_validator.py` still relies on separate `_build_graph` / `_is_sequential_path` helpers instead of the shared analyzer.
- Tests still permit some attributed connections that the shared analyzer would currently reject fail-closed, so validation and capability planning are not fully aligned.
- Finish this by routing Akida sequential validation through `NetworkTopologyAnalyzer` and adding tests that reject unknown or unsupported topological structures consistently.

# Problem Statement
The Akida hardware backend integration currently handles hardware invariants by differentiating between Akida 1 (which strictly requires linear, feed-forward sequential topologies) and Akida 2 (which supports branching topologies). The validation logic in `neurocnl/layers/akida_validator.py` and `neurocnl/backends/akida_capabilities.py` correctly analyzes the graph structure to enforce these constraints.

However, a maintainability risk has been identified: maintaining parallel structural invariant checks for Akida alongside the core `NetworkIR` graph representation could lead to topological drift. If new connectivity features, spatial connection types, or node definitions are added to `NetworkIR` in the future, the Akida-specific validation logic might not inherently recognize or correctly restrict these new graph topologies, potentially allowing invalid networks to be passed to the Akida generator.

# Proposed Solution
1. **Centralize Topology Abstraction:** Refactor the graph traversal and topology analysis logic currently localized in the Akida validators into a more generalized `NetworkTopologyAnalyzer` utility within the `NetworkIR` or `layers` module.
2. **Unified Constraint Registration:** Ensure that the Akida capability profile dynamically subscribes to or queries this generalized topology analyzer to determine if a graph is strictly sequential, rather than performing isolated graph traversal.
3. **Future-Proofing Features:** Add unit tests that inject unknown or unsupported node/edge types into the `NetworkIR` graph to guarantee that the Akida sequential validator defaults to a safe rejection (fail-closed) rather than ignoring unhandled graph properties.

# Acceptance Criteria
- [ ] Graph traversal logic is extracted from `akida_validator.py`/`akida_capabilities.py` into a shared utility.
- [ ] The Akida 1 validator uses this shared utility to enforce its strict linear feed-forward constraint.
- [ ] Tests are added to demonstrate that newly mocked or unsupported `NetworkIR` connectivity structures are safely rejected by the Akida 1 validator.
- [ ] No regressions in the current capabilities detection for Akida 1 and Akida 2.
