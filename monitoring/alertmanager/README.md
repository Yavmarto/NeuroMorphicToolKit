# alertmanager

Real notification routing for NMTK alerts. Formerly every alert went to a
`null-receiver` and was delivered nowhere.

## Routing

| Alert severity | Receiver | Slack appearance | Repeat interval |
|---|---|---|---|
| `critical` | `nmtk-critical` | red, `:rotating_light:`, title `[CRITICAL] <alertname>` | 1h |
| anything else (for example `warning`) | `nmtk-warning` | yellow, `:warning:`, title `[WARNING] <alertname>` | 4h |

All notifications go to the Slack channel **#nmtk-alerts**. A firing critical
alert inhibits the same alert name on the same instance at warning severity, so
one incident produces one notification thread. Resolved alerts are sent too
(`send_resolved: true`).

The route severity comes from the `severity` label on the Prometheus rules in
`../prometheus/alert_rules.yml`.

## Secret handling

Alertmanager cannot expand environment variables in its config. `alertmanager.yml`
therefore reads the webhook URL from the file
`/etc/alertmanager/secrets/slack_webhook_url` (Slack's `api_url_file` option).
`entrypoint.sh` writes that file from the `SLACK_WEBHOOK_URL` environment
variable at startup and then starts Alertmanager. The secret is never stored in
git.

Required environment:

- `SLACK_WEBHOOK_URL` — incoming-webhook URL for #nmtk-alerts. The container
  exits with a clear message when it is unset.

Optional environment: `ALERTMANAGER_CONFIG_FILE`, `ALERTMANAGER_STORAGE_PATH`,
`ALERTMANAGER_SECRET_DIR`.

## Channel configuration

### Local (developer machine)

The stack is not started by a root compose file yet; that is CEL-310. Until
then, run Alertmanager directly with the real config and entrypoint:

```bash
docker run --rm -p 9093:9093 \
  -e SLACK_WEBHOOK_URL="$SLACK_WEBHOOK_URL" \
  -v "$PWD/monitoring/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" \
  -v "$PWD/monitoring/alertmanager/entrypoint.sh:/entrypoint.sh:ro" \
  --entrypoint /bin/sh \
  prom/alertmanager:v0.28.1 /entrypoint.sh
```

Set `SLACK_WEBHOOK_URL` in your shell or in a git-ignored `.env` file. See
`.env.example` for the variable.

### Production

There is no production Alertmanager. The CTO decision of 2026-09-17 is that the
monitoring stack is **dev/CI-only** until a central, team-run stack exists. When
such a stack is deployed, give it the same `SLACK_WEBHOOK_URL` variable in its
environment; no config change is needed.

## Verify delivery end to end

```bash
bash scripts/verify_alertmanager_routing.sh
```

The script starts Alertmanager with the real config and entrypoint, points the
Slack webhook at a throwaway local HTTP sink, fires one critical and one warning
alert through the Alertmanager API, and asserts that both are delivered through
the correct receiver and addressed to #nmtk-alerts. It needs Docker and no Slack
secret.

This proves routing and delivery. It does not prove that Prometheus evaluates a
rule and forwards it; that path depends on `/metrics` endpoints (CEL-311).

## On-call

There is no formal rotation. The CTO decision is that the person actively
working the affected area that week owns the alert. Escalate outages to the
CTO.
