# ADR 0003: Rate Limiting with SlowAPI

## Status
Accepted

## Context
All NMTK backend services are exposed on localhost and potentially on shared lab networks. Without rate limiting, a misbehaving client or runaway script could overwhelm a service, especially during long-running operations like simulation or benchmarking.

## Decision
All FastAPI services use SlowAPI (a Starlette rate-limiting middleware built on `limits`) with `get_remote_address` as the key function. The default limit is 60 requests per minute per client IP, applied globally. Rate limit headers (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`) are included in responses. No distributed rate limiting is implemented.

## Consequences
- **Positive:** Consistent 60/minute default across all services prevents resource exhaustion from runaway clients; in-process rate limiting requires no external infrastructure (Redis, memcached).
- **Negative:** In-process rate limiting does not share state across service instances, making it ineffective for horizontally scaled deployments; 60/minute may be too restrictive for batch operations like parameter sweeps.
