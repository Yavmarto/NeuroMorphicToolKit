# ADR 0016: Monitoring and Observability Stack

## Status
Accepted

## Context
With 6+ backend services running concurrently, diagnosing performance issues, tracking error rates, and monitoring resource usage requires centralized observability. Individual service logs are insufficient for understanding cross-service behavior.

## Decision
Deploy a monitoring stack via the `monitoring` Docker Compose profile: Prometheus scrapes HTTP metrics (`http_requests_total`, `http_request_duration_seconds`) from all services, Loki aggregates logs shipped by Promtail, and Grafana provides dashboards and visualization. AlertManager handles alert routing. Services expose metrics at their health endpoints. All monitoring services run on a dedicated `monitoring-net` network.

## Consequences
- **Positive:** Centralized metrics and log aggregation enables cross-service performance analysis and alerting; Grafana dashboards provide at-a-glance health visibility.
- **Negative:** The monitoring stack adds significant resource overhead (Prometheus, Loki, Grafana, Promtail, AlertManager); no distributed tracing (OpenTelemetry/Jaeger) means cross-service request flows cannot be visualized.
