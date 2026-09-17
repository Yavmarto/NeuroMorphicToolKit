# ADR 0001: Canvas-Based Graph Model

## Status
Accepted

## Context
Users need to visually compose SNN topologies before simulation, requiring a data model that is both UI-renderable and simulation-executable. Existing standards like GraphML or NeuroML are too verbose or lack simulation semantics.

## Decision
Represent SNN designs as `CanvasGraph` (nodes + edges with typed parameters), serialized as JSON within SQLite. Nodes map to neuron populations and components, edges represent synaptic connections. The `CanvasNode` and `CanvasEdge` Pydantic schemas define the graph contract.

## Consequences
- **Positive:** Direct mapping between visual canvas and simulation model eliminates translation errors; JSON serialization keeps the storage layer simple.
- **Negative:** Custom graph format lacks interoperability with standard neuroinformatics tools; graph validation logic must be maintained alongside UI rendering.
