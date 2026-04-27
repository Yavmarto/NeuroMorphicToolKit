# ADR 0018: Suite API — Unified Backend

## Status
Accepted

## Context
ADRs 0009 and 0014 established fixed per-module ports (8000–8005) and
Docker Compose orchestration of six independent FastAPI services.
The architecture-consolidation-analysis.md (2026-04-27) concluded that
the suite behaves as one product with seven domains, not seven independent
services, and that the per-service split imposes duplicate middleware,
health checks, startup scripts, and cross-service HTTP hops without
providing true product independence.

## Decision
Consolidate all six FastAPI backends into a single `suite_api` application
served on port 9000. Each module's business logic is mounted as an internal
APIRouter under `/api/{module}/`. Optional workers (neurosense-hw, neurobench-
runner, neurochip-hw, neurocnl-physics) remain as isolated processes only
where justified by hardware requirements, long-running jobs, or heavy optional
dependencies (MuJoCo, BrainFlow, Akida, PYNQ).

## Consequences
- **Positive:** One API surface, one middleware stack, one startup command.
- **Positive:** Cross-module calls become in-process; no localhost HTTP hops for
  standard workflows.
- **Positive:** Neurohub's suite_client no longer needs to poll sibling services
  for routine orchestration.
- **Negative:** A bad change to suite_api has a larger blast radius than a
  change to one isolated service.
- **Negative:** Optional hardware dependencies still need careful isolation to
  prevent ImportError on machines without the hardware stack installed.
- **Supersedes:** ADR 0009 (Makefile Port Allocation) and ADR 0014
  (Docker Compose Orchestration) — those ADRs describe the old architecture;
  their port/service decisions are superseded by this ADR after Phase 5.
