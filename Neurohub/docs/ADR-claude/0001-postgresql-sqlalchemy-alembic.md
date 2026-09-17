# ADR 0001: PostgreSQL + SQLAlchemy + Alembic

## Status
Accepted

## Context
As the community registry for neuromorphic computing artifacts, Neurohub requires robust relational storage with schema evolution capability, unlike the simpler SQLite-only approach used in other NMTK modules. The data model includes users, projects, assets, workflows, and activity logs with complex relationships.

## Decision
Use SQLAlchemy 2.x with `DeclarativeBase` and `mapped_column` for 9+ database models (UserDB, ProjectDB, MilestoneDB, SharedAssetDB, WorkflowTemplateDB, ActivityEntryDB, NoteDB, WorkflowRunDB, SuiteConfigDB). Alembic handles schema migrations, auto-applied on startup via the FastAPI lifespan hook. Both PostgreSQL (production) and SQLite (development) are supported via `NEUROHUB_DB_URL`.

## Consequences
- **Positive:** SQLAlchemy 2.x provides type-safe ORM with modern Python typing; Alembic auto-migration on startup ensures the database is always current without manual intervention.
- **Negative:** Dual database support (PostgreSQL + SQLite) requires avoiding PostgreSQL-specific features; auto-migration on startup can be dangerous in production without a `NEUROHUB_SKIP_MIGRATIONS` escape hatch.

## Status Update (2026-07-16 audit)
The 9 models this ADR describes (`UserDB`, `ProjectDB`, `MilestoneDB`, `SharedAssetDB`,
`WorkflowTemplateDB`, `ActivityEntryDB`, `NoteDB`, `WorkflowRunDB`, `SuiteConfigDB`) are no
longer what's in the codebase. `neurohub/db/models.py`'s `__all__` today lists a different set
of 9 models: `UserDB`, `ProjectDB`, `SharedAssetDB`, `SuiteConfigDB`, `ArtefactDB`, `RatingDB`,
`CommentDB`, `FollowDB`, `RegistryActivityEntryDB`. Migration
`neurohub/db/migrations/versions/c2d4e5f60002_drop_pm_workflow_tables.py` (revises
`b1d2e3f40001`) drops the `workflow_runs`, `workflow_templates`, `activity_entries`, `notes`,
and `milestones` tables and removes the `projects.milestones` JSON column — confirmed present
in the migrations directory. The current schema is a "global registry" model
(artefacts/ratings/comments/follows/activity feed), not the PM/workflow schema this ADR
documents; SQLAlchemy 2.x + Alembic remain accurate as the underlying tech choice, but the
model list and much of the Context section are stale.
