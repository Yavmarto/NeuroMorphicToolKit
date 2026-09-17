# ADR 0002: Real-time vs Batch Simulation

## Status
Accepted

## Context
NeuroSim users need to edit parameters and see instant visual feedback in their spiking models (low latency, `<500ms`). Conversely, validating full models with datasets requires extended runtimes spanning minutes or hours (`sweep`). Handling both within a single request queue leads to severe UI lockups and timeout issues.

## Decision
We separated simulation execution models.
- **Real-Time Preview (`/api/neurosim/preview`):** Fast-tracked API that runs short (`<500ms`) in-memory Nengo engine processes directly without database locks or I/O logging to maximize responsiveness.
- **Batch Processing (`/api/neurosim/sweep`):** Background job execution mapping simulations to SQLite tracking (`jobs.db`). Yields asynchronous updates.

## Consequences
- **Positive:** Prevents the main Node/Flutter UI canvas from freezing. It gives users immediate tactile feedback during parameter tuning.
- **Negative:** Requires dual maintenance of simulation runners in the backend, and results cannot perfectly synchronize across systems without careful state management in Riverpod.
