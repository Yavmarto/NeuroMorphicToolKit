# ADR 0004: Domain-Specific Widget Library

## Status
Accepted

## Context
Standard Material widgets cannot represent neuromorphic-specific concepts such as energy efficiency reports, quantization accuracy tables, deployment pipeline progress, or spike train visualizations. Each module would need to build these from scratch.

## Decision
Build domain-specific widgets including `EnergyBarChart`, `QuantizationTable`, `SparklineChart`, `PipelineStepper`, `PynqDeployStatusCard`, `AkidaSupportStateCard`, `NmtkNavigationRail`, and shared button components. Each widget accepts a typed model input (EnergyReport, QuantizationReport, SensorFrame, deployment status models) and is self-contained with no external dependencies beyond the theme.

## Consequences
- **Positive:** Domain-specific widgets eliminate duplicated visualization code across modules; typed model inputs enforce data correctness at compile time.
- **Negative:** Widgets are tightly coupled to the NMTK domain, limiting reuse outside the toolkit; model types in the shared library must evolve in lockstep with backend contract changes.
