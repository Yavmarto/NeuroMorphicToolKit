---
title: "Mitigate Topological Drift Risk for Akida Sequential Invariants"
labels: ["maintenance", "validation", "hardware", "akida"]
---

## Audit Status

Status as of 2026-04-13: `complete`

What is already landed:
- A shared `NetworkTopologyAnalyzer` now exists in `neurocnl/neurocnl/ir/topology.py`.
- Akida capability planning in `neurocnl/neurocnl/backends/akida_capabilities.py` instantiates that analyzer.
- `neurocnl/neurocnl/layers/akida_validator.py` now routes sequential and recurrent checks through the shared analyzer.
- Validator tests now cover fail-closed rejection for unsupported connection attributes.
- Targeted Akida validator / contract / mapper verification passes in the current repo state.

What is still open:
- No direct implementation gap remains in this issue's original scope.
- Residual Akida work now belongs in the broader deployment plan, not in this topology-drift ticket.

## Continuation Order

Queue position: `completed dependency`

## Next Action To Continue

- Continue in `akida-studio-deployment-plan.md`.
- Reopen this only if a new topology feature bypasses `NetworkTopologyAnalyzer`.

# Problem Statement
The Akida hardware backend integration currently handles hardware invariants by differentiating between Akida 1 (which strictly requires linear, feed-forward sequential topologies) and Akida 2 (which supports branching topologies). The validation logic in `neurocnl/layers/akida_validator.py` and `neurocnl/backends/akida_capabilities.py` correctly analyzes the graph structure to enforce these constraints.

However, a maintainability risk has been identified: maintaining parallel structural invariant checks for Akida alongside the core `NetworkIR` graph representation could lead to topological drift. If new connectivity features, spatial connection types, or node definitions are added to `NetworkIR` in the future, the Akida-specific validation logic might not inherently recognize or correctly restrict these new graph topologies, potentially allowing invalid networks to be passed to the Akida generator.

# Proposed Solution
1. **Centralize Topology Abstraction:** Refactor the graph traversal and topology analysis logic currently localized in the Akida validators into a more generalized `NetworkTopologyAnalyzer` utility within the `NetworkIR` or `layers` module.
2. **Unified Constraint Registration:** Ensure that the Akida capability profile dynamically subscribes to or queries this generalized topology analyzer to determine if a graph is strictly sequential, rather than performing isolated graph traversal.
3. **Future-Proofing Features:** Add unit tests that inject unknown or unsupported node/edge types into the `NetworkIR` graph to guarantee that the Akida sequential validator defaults to a safe rejection (fail-closed) rather than ignoring unhandled graph properties.

# Acceptance Criteria
- [x] Graph traversal logic is extracted from `akida_validator.py`/`akida_capabilities.py` into a shared utility.
- [x] The Akida 1 validator uses this shared utility to enforce its strict linear feed-forward constraint.
- [x] Tests are added to demonstrate that newly mocked or unsupported `NetworkIR` connectivity structures are safely rejected by the Akida 1 validator.
- [x] No regressions were observed in the targeted Akida validator / mapping verification run.
