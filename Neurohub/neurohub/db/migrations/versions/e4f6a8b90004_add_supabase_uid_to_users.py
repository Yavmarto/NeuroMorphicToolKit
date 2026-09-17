"""Add supabase_uid column to users table.

Revision ID: e4f6a8b90004
Revises: d3e5f7a80003
Create Date: 2026-08-01 00:00:00.000000

Adds a nullable, unique ``supabase_uid`` column to the ``users`` table.
This column is populated by ``POST /api/v1/auth/sync`` when
``NEUROHUB_AUTH_PROVIDER=supabase``.  Null for all existing internal-auth and
firebase-auth users.
Fully reversible (Property 29).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "e4f6a8b90004"
down_revision: str | Sequence[str] | None = "d3e5f7a80003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add supabase_uid column and unique index to the users table."""
    op.add_column(
        "users",
        sa.Column("supabase_uid", sa.String(), nullable=True),
    )
    op.create_index(
        "ix_users_supabase_uid",
        "users",
        ["supabase_uid"],
        unique=True,
    )


def downgrade() -> None:
    """Drop the supabase_uid index and column from the users table."""
    op.drop_index("ix_users_supabase_uid", table_name="users")
    op.drop_column("users", "supabase_uid")
