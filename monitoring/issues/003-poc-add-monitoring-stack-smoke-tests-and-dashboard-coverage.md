# [POC-03] Add Monitoring Stack Smoke Tests and Dashboard Coverage

**Module**: monitoring
**Phase**: POC
**Priority**: P1
**Effort**: Medium (2 days)
**Labels**: `monitoring`, `phase:poc`, `priority:high`, `testing`, `grafana`
**Source**: 02-Apr-2026 folder review

## Problem

The monitoring stack is structurally present in `docker-compose.yml`, but there is not yet a strong verification path showing that Prometheus, Loki, Grafana, and Alertmanager all start correctly, ingest useful data, and present a meaningful suite-level dashboard.

## Acceptance Criteria

- [ ] Add a smoke test or validation script for the monitoring profile in root Docker Compose
- [ ] Verify Prometheus can scrape all configured targets that are expected to be up
- [ ] Verify Promtail ships logs from NMTK containers into Loki
- [ ] Verify Grafana provisions both datasources and the default dashboard without manual steps
- [ ] Expand the default dashboard if needed to cover uptime, request rate, latency, error rate, and recent logs
- [ ] Document the minimum operator workflow for checking suite health in Grafana
