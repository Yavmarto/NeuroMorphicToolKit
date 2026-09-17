# ADR 0007: Job Store Persistence

## Status
Accepted

## Context
Simulation jobs (preview runs and parameter sweeps) generate results that users need to access after completion. The job store must track job status, parameters, and results across the job lifecycle (queued, running, completed, failed).

## Decision
Implement an in-memory `JobStore` class that tracks simulation jobs using Python dictionaries. Jobs are keyed by UUID and store status, start time, parameters, and results. The preview runner and sweep runner both register jobs in the store and update them as execution progresses.

## Consequences
- **Positive:** In-memory storage is fast with zero infrastructure dependencies; simple dictionary-based design is easy to understand and debug.
- **Negative:** All job state is lost on server restart with no persistence or recovery mechanism; in-memory storage cannot be shared across multiple server instances, preventing horizontal scaling.
