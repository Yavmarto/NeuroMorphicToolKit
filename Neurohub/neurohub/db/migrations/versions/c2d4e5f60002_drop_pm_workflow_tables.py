"""Drop PM and workflow tables; remove embedded milestones JSON from projects.

Revision ID: c2d4e5f60002
Revises: b1d2e3f40001
Create Date: 2026-06-02 00:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "c2d4e5f60002"
down_revision: str | Sequence[str] | None = "b1d2e3f40001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_PM_TABLES = (
    "workflow_runs",
    "workflow_templates",
    "activity_entries",
    "notes",
    "milestones",
)


def upgrade() -> None:
    """Remove Jira-style PM and suite workflow orchestration tables."""
    with op.batch_alter_table("projects") as batch_op:
        batch_op.drop_column("milestones")

    for table in _PM_TABLES:
        op.drop_table(table)


def downgrade() -> None:
    """Recreate dropped tables (empty schema only — data is not restored)."""
    op.create_table(
        "milestones",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("project_id", sa.String(), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("target_date", sa.String(), nullable=True),
        sa.Column("completed_date", sa.String(), nullable=True),
        sa.Column("auto_detect", sa.JSON(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_milestones_id"), "milestones", ["id"], unique=False)
    op.create_index(op.f("ix_milestones_project_id"), "milestones", ["project_id"], unique=False)

    op.create_table(
        "notes",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("project_id", sa.String(), nullable=False),
        sa.Column("asset_id", sa.String(), nullable=True),
        sa.Column("author", sa.String(), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("created_at", sa.String(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_notes_asset_id"), "notes", ["asset_id"], unique=False)
    op.create_index(op.f("ix_notes_id"), "notes", ["id"], unique=False)
    op.create_index(op.f("ix_notes_project_id"), "notes", ["project_id"], unique=False)

    op.create_table(
        "activity_entries",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("timestamp", sa.String(), nullable=False),
        sa.Column("user", sa.String(), nullable=False),
        sa.Column("app", sa.String(), nullable=False),
        sa.Column("project_id", sa.String(), nullable=True),
        sa.Column("action", sa.String(), nullable=False),
        sa.Column("description", sa.String(), nullable=False),
        sa.Column("link", sa.String(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_activity_entries_app"), "activity_entries", ["app"], unique=False)
    op.create_index(op.f("ix_activity_entries_id"), "activity_entries", ["id"], unique=False)
    op.create_index(
        op.f("ix_activity_entries_project_id"), "activity_entries", ["project_id"], unique=False
    )
    op.create_index(
        op.f("ix_activity_entries_timestamp"), "activity_entries", ["timestamp"], unique=False
    )

    op.create_table(
        "workflow_templates",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("description", sa.String(), nullable=False),
        sa.Column("steps", sa.JSON(), nullable=False),
        sa.Column("builtin", sa.Boolean(), nullable=False),
        sa.Column("schedule", sa.String(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_workflow_templates_id"), "workflow_templates", ["id"], unique=False)
    op.create_index(
        op.f("ix_workflow_templates_name"), "workflow_templates", ["name"], unique=False
    )

    op.create_table(
        "workflow_runs",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("workflow_id", sa.String(), nullable=False),
        sa.Column("project_id", sa.String(), nullable=False),
        sa.Column("started_at", sa.String(), nullable=False),
        sa.Column("completed_at", sa.String(), nullable=True),
        sa.Column("heartbeat", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("steps", sa.JSON(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_workflow_runs_id"), "workflow_runs", ["id"], unique=False)
    op.create_index(
        op.f("ix_workflow_runs_project_id"), "workflow_runs", ["project_id"], unique=False
    )
    op.create_index(
        op.f("ix_workflow_runs_workflow_id"), "workflow_runs", ["workflow_id"], unique=False
    )

    with op.batch_alter_table("projects") as batch_op:
        batch_op.add_column(sa.Column("milestones", sa.JSON(), nullable=False, server_default="[]"))
