# Backend endpoint smoke checks

`scripts/backend_endpoint_smoke.py` reads module IDs, ports, and health paths from
`nmtk/neuro_toolkit/assets/modules.json`. Products on port 9000 are probed through
their consolidated Suite API domain (for example `/api/neurocnl/health`); optional
workers keep their manifest-defined ports and health paths.

For the shared development host, set `NMTK_BACKEND_HOST=<dev-host>` so worker
ports resolve there and set `SUITE_API_URL=http://<dev-host>:9000` for Suite API.
Authenticated deployments also accept the app-provisioned credential through
`NMTK_ADMIN_TOKEN` or `NMTK_ADMIN_TOKEN_FILE`.

Use `health --module all` for manifest-wide readiness, `openapi --module neurocnl`
for the Suite API contract, and `smoke --module neurocnl` for health, OpenAPI,
NIR-native parse, and validation checks. `--start` is intentionally rejected for
Suite API-managed products because Backend Setup owns their lifecycle.
