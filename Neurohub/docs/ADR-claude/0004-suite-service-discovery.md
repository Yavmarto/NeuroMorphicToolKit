# ADR 0004: Suite Service Discovery

## Status
Deprecated — dead code, no live callers (see Status Update below)

## Context
Neurohub must communicate with all 5 other NMTK backend services (neurocnl, Neurosim, Neurochip, Neurobench, Neurosense) to check health status and dispatch workflow steps. Service locations vary between development (localhost ports) and Docker deployment.

## Decision
Implement a `suite_client.py` that maintains configurable base URLs for each NMTK service, stored in the database via `SuiteConfigDB`. URL resolution follows a hierarchy: database configuration, then environment variables, then localhost port defaults (8000-8005). Health checks are async HTTP GET requests with timeout handling.

## Consequences
- **Positive:** Three-tier URL resolution (database > environment > defaults) adapts to any deployment topology without code changes; async health checks avoid blocking the main event loop.
- **Negative:** HTTP-based discovery lacks automatic failover or load balancing; stale database URLs require manual cleanup if services are relocated.

## Status Update (2026-07-16 audit)
`get_app_urls()` in `neurohub/app/services/suite_client.py` only implements two tiers: a
`SuiteConfigDB` row from the database, or the hardcoded `DEFAULT_URLS` dict — there is no
environment-variable lookup anywhere in the function (confirmed via read/grep), so the
"three-tier" resolution this ADR describes doesn't match the code. `HEALTH_PATH = "/health"`
is defined in the file but never referenced anywhere else in it (grep shows exactly one
occurrence). Separately, `neurohub/app/routers/health.py`'s own docstring states its endpoint
"checks only Neurohub's local status, not the health of other suite services. Suite-wide
health monitoring belongs to nmtk" — directly contradicting this ADR's premise that Neurohub
does suite-wide service discovery/health checking. As noted in the 0003 status update,
`suite_client.py` itself is unused dead code with no callers under `app/`.
