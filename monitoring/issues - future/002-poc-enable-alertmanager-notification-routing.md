# [POC-02] Enable Real Alertmanager Notification Routing

**Module**: monitoring
**Phase**: POC
**Priority**: P1
**Effort**: Small (1 day)
**Labels**: `monitoring`, `phase:poc`, `priority:high`, `alerting`, `operations`
**Source**: 02-Apr-2026 folder review

## Problem

The monitoring stack already defines alert rules for service down, high error rate, and high latency, but Alertmanager is configured with a `null-receiver`. This means alerts are computed but never delivered to a real operator channel.

## Acceptance Criteria

- [x] Replace the placeholder `null-receiver` with at least one real notification target
- [x] Support environment-driven configuration for secrets or webhook URLs
- [x] Route critical alerts differently from warning-level alerts if needed
- [x] Verify a synthetic alert can be triggered and delivered end-to-end
- [x] Document how operators should configure notification channels locally and in production

Implemented in CEL-312. Routing goes to Slack #nmtk-alerts; the webhook URL comes
from the `SLACK_WEBHOOK_URL` environment variable. See
[`../alertmanager/README.md`](../alertmanager/README.md) and
`scripts/verify_alertmanager_routing.sh`.
