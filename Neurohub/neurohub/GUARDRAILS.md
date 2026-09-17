# Neurohub Guardrails

This document outlines known failure patterns and mitigations when working with the Neurohub registry and metadata module, as well as strict safety constraints regarding access control and data integrity. Use this to design resilient features and avoid common pitfalls.

## 🛑 Security & Access Control Boundaries

**Safety Constraint:** Neurohub manages sensitive metadata across the entire suite. Unauthorized access can lead to data leaks or suite-wide disruption.
- **Auth Boundaries:** All mutating endpoints (POST, PUT, DELETE) must be protected. You must interface with `auth.py` and strictly enforce role-based access control (RBAC). Do not bypass dependency injection (e.g., `Depends(get_current_user)`).
- **Data Access Controls:** Verify ownership and permissions before returning or modifying project resources. Ensure data requested via `projects.py`, `assets.py`, `dashboard.py`, `notes.py`, and `milestones.py` respects the user's role and project assignments.
- **Member Permission Enforcement:** Adding, removing, or modifying team members must only be done through `members.py` by authorized admins. Do not allow regular users to elevate their own permissions or add new members directly via other API endpoints.

## 🛑 Data Integrity & Migration Safety

**Safety Constraint:** Neurohub's database acts as the central source of truth for the suite. Corrupted metadata or broken links can render projects unusable.
- **Asset Integrity:** When managing assets via `assets.py`, always ensure cross-references to external suite apps remain valid. Implement soft-deletes or validation checks rather than allowing hard deletes of assets that might be actively referenced in pipelines managed by `workflows.py` or aggregated in `activity.py`.
- **Database Migration Safety:** When altering schemas, you must use Alembic. Do not manually modify the SQLite database or bypass the standard migration flow. All new migrations must be tested and proven to be reversible. Ensure `alembic upgrade head` succeeds in a clean environment before merging.
- **Contract Enforcement:** Changes to `config.py` and `health.py` must maintain backward compatibility. The 3 defined contracts are: `project_contracts.py`, `workflow_contracts.py`, and `bundle_contracts.py` (defined in `neurohub/contracts/__init__.py`). All contract tests live under `neurohub/tests/test_contracts.py`.

## 🛑 Service Unavailability

**Failure Pattern:** One or more suite apps (NeuroSim, NeuroChip, etc.) are down, causing timeouts or 5xx errors in Neurohub when fetching activity or sending bundles.
- **Mitigation 1:** Always wrap `call_app_api` or `fetch_activity` in a `try-except` block to catch `httpx.HTTPError`.
- **Mitigation 2:** Return a partial success state or a placeholder for missing data on the dashboard instead of failing the entire request.
- **Note:** Neurohub's `/health` endpoint is self-only (database connectivity + version). Suite-wide health monitoring belongs to `nmtk`. Do not implement cross-module health polling in Neurohub.

## 🛑 Data Model Mismatches

**Failure Pattern:** A suite app's API changes its response format, breaking Neurohub's parsing logic (e.g., the activity feed format).
- **Mitigation 1:** Use strict Pydantic models with `extra="ignore"` to avoid crashing on unexpected fields.
- **Mitigation 2:** Implement version-checking in the `suite_client` to detect incompatible API versions.
- **Mitigation 3:** Maintain comprehensive mock data in tests that reflect the latest known API contracts.

## 🛑 Long-Running Workflow Deadlocks

**Failure Pattern:** A multi-app workflow (e.g., design → deploy) hangs because one step takes longer than the timeout or never returns.
- **Mitigation 1:** Use the `WorkflowRun` status to track execution. Implement a cancellation mechanism (`cancel_workflow_run`).
- **Mitigation 2:** Ensure timeouts are configurable per step (defaulting to 300s) and never leave a step running indefinitely.
- **Mitigation 3:** Idempotency: Allow workflows to be re-run from the last failed/skipped step instead of always starting from scratch.

## 🛑 Database Out-of-Sync (Polling)

**Failure Pattern:** The activity feed collector polls too frequently (overwhelming suite apps) or too infrequently (causing lag on the dashboard).
- **Mitigation 1:** Use the `since` parameter in polling to only fetch new entries since the last successful collection.
- **Mitigation 2:** Implement an exponential backoff strategy if a suite app is consistently failing to respond to polling requests.
- **Mitigation 3:** Ensure the collector uses a background task or a separate worker process so it doesn't block API requests.

## 🛑 Asset Reference Orphans

**Failure Pattern:** A project link in Neurohub points to a resource in NeuroSim that has been deleted.
- **Mitigation 1:** Implement "soft validation" of links when a project is loaded; if a resource is missing, mark the link as "broken" rather than crashing.
- **Mitigation 2:** When deleting an asset via the Neurohub shared library, check if it is being used by any active projects across the suite.
