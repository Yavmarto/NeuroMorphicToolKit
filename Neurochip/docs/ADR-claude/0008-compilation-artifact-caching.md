# ADR 0008: Compilation Artifact Caching

## Status
Accepted

## Context
Compiling SNN models for neuromorphic hardware (quantization, code generation, firmware packaging) is computationally expensive. Re-compiling unchanged models wastes time, especially during iterative development and CI runs.

## Decision
Implement a `cache_manager.py` that caches compiled artifacts using SHA-256 hashes of the input model and compilation parameters as cache keys. Cached artifacts are stored on the local filesystem. Cache hits skip the full compilation pipeline and return the previously compiled artifact directly.

## Consequences
- **Positive:** Cache hits eliminate redundant compilation, significantly speeding up iterative development and CI pipelines; SHA-256 keys ensure cache correctness when inputs change.
- **Negative:** No cache eviction policy means the cache grows unboundedly over time; cache is local to each machine with no shared cache across CI runners or team members.
