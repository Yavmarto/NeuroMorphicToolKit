# NeuroHub API Reference

This page documents the human-facing NeuroHub HTTP API. The live OpenAPI schema
at `/openapi.json` is authoritative for exact request and response models.

Default base URL: `http://127.0.0.1:8005`

Live docs:

- Swagger UI: `http://127.0.0.1:8005/docs`
- OpenAPI JSON: `http://127.0.0.1:8005/openapi.json`
- Health: `http://127.0.0.1:8005/health`

All NeuroHub application routes use the `/api/neurohub` prefix unless otherwise
noted.

## Authentication

Authentication is optional. When `NEUROHUB_AUTH_ENABLED=true`, requests can use:

- `X-API-Key: <NEUROHUB_ADMIN_API_KEY>` for admin role.
- `X-API-Key: <NEUROHUB_VIEWER_API_KEY>` for viewer role.
- `Authorization: Bearer <jwt>` after login.

When auth is disabled, the backend returns a default admin test user for
development.

## Operational Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Simple service health check with no DB dependency. |
| `GET` | `/docs` | FastAPI Swagger UI. |
| `GET` | `/openapi.json` | Canonical generated OpenAPI schema. |
| `GET` | `/api/neurohub/health` | Aggregated health of configured suite services. |

## Auth

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurohub/auth/register` | Register a user. |
| `POST` | `/api/neurohub/auth/login` | Login and receive a JWT token. |
| `POST` | `/api/neurohub/auth/refresh` | Refresh a JWT token. |

## Dashboard, Config, and Activity

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurohub/dashboard` | Return project summary, recent activity, and suite health. |
| `GET` | `/api/neurohub/config` | Fetch suite configuration. |
| `PUT` | `/api/neurohub/config` | Update suite configuration. |
| `GET` | `/api/neurohub/activity` | List activity entries with optional filters. |
| `POST` | `/api/neurohub/activity/collect` | Collect activity from configured suite apps. |

NeuroHub orchestrates and references other modules; it should not reimplement
their heavy compute or hardware execution paths.

## Projects

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurohub/projects` | List projects visible to the current user. |
| `POST` | `/api/neurohub/projects` | Create a project. |
| `GET` | `/api/neurohub/projects/{id}` | Fetch one project. |
| `PUT` | `/api/neurohub/projects/{id}` | Update a project. |
| `DELETE` | `/api/neurohub/projects/{id}` | Delete a project. |
| `POST` | `/api/neurohub/projects/{id}/export` | Export a project bundle. |
| `POST` | `/api/neurohub/projects/import` | Import a project bundle. |

## Milestones, Members, and Notes

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurohub/projects/{id}/milestones` | List project milestones. |
| `PUT` | `/api/neurohub/projects/{id}/milestones` | Replace project milestones. |
| `GET` | `/api/neurohub/projects/{id}/members` | List project members. |
| `PUT` | `/api/neurohub/projects/{id}/members` | Replace project members. |
| `GET` | `/api/neurohub/projects/{id}/notes` | List project notes. |
| `POST` | `/api/neurohub/projects/{id}/notes` | Create a project note. |

Admin role is required for mutating member, milestone, note, and many project
operations when auth is enabled.

## Assets

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurohub/assets` | List shared assets, optionally filtered by type or tags. |
| `POST` | `/api/neurohub/assets` | Add a shared asset. |
| `GET` | `/api/neurohub/assets/{id}` | Fetch asset metadata. |
| `PUT` | `/api/neurohub/assets/{id}` | Update asset metadata or create a new version. |
| `DELETE` | `/api/neurohub/assets/{id}` | Remove an asset. |

Large artifacts and module-specific execution logic should remain in the owning
module. NeuroHub stores references, metadata, and orchestration state.

## Workflows

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurohub/workflows` | List workflow templates. |
| `POST` | `/api/neurohub/workflows` | Create a workflow template. |
| `PUT` | `/api/neurohub/workflows/{id}` | Update a workflow template. |
| `POST` | `/api/neurohub/workflows/{id}/run` | Run a workflow for a project. |
| `GET` | `/api/neurohub/workflows/runs/{run_id}` | Fetch workflow run status/details. |
| `POST` | `/api/neurohub/workflows/runs/{run_id}/cancel` | Cancel a running workflow. |

Workflow runs may call other suite services. Callers should expect partial
service failure, timeout, or degraded module state.

## Related Docs

- [`../../neurohub_spec.md`](../../neurohub_spec.md) describes broader product intent.
- [`user_guide.md`](user_guide.md) covers user workflows.
- [`developer_guide.md`](developer_guide.md) covers implementation details.
- [`../neurohub_functional_testing_guide.md`](../neurohub_functional_testing_guide.md) covers validation.
