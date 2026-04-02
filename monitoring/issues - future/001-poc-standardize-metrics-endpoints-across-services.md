# [POC-01] Standardize Metrics Endpoints Across NMTK Services

**Module**: monitoring
**Phase**: POC
**Priority**: P0
**Effort**: Medium (2-3 days)
**Labels**: `monitoring`, `phase:poc`, `priority:critical`, `observability`, `metrics`
**Source**: 02-Apr-2026 folder review

## Problem

The root monitoring stack already scrapes all major services through Prometheus, but the scrape target list is ahead of the service implementations. Some modules expose health endpoints only, some expose real metrics, and at least `neurocnl` has explicit Prometheus middleware. The suite needs a consistent metrics contract before dashboarding and alerting can be trusted.

## Acceptance Criteria

- [ ] Define a standard metrics endpoint path and exposure pattern for all HTTP services
- [ ] Verify each service exports Prometheus-compatible metrics rather than just a health endpoint
- [ ] Add missing metrics middleware or instrumentation where absent
- [ ] Ensure request count, latency, and error-rate metrics exist for each backend
- [ ] Update Prometheus scrape config only if it matches the real service behavior
- [ ] Document which metrics are required for all modules versus optional module-specific metrics
