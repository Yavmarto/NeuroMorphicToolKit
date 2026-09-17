"""Add firebase_uid column to users table.

Revision ID: d3e5f7a80003
Revises: c2d4e5f60002
Create Date: 2026-07-20 14:00:00.000000

Adds a nullable, unique ``firebase_uid`` column to the ``users`` table.
This column is populated by ``POST /api/v1/auth/sync`` when
``NEUROHUB_AUTH_PROVIDER=firebase``.  Null for all existing internal-auth users.
Fully reversible (Property 29).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "d3e5f7a80003"
down_revision: str | Sequence[str] | None = "c2d4e5f60002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add firebase_uid column and unique index to the users table."""
    op.add_column(
        "users",
        sa.Column("firebase_uid", sa.String(), nullable=True),
    )
    op.create_index(
        "ix_users_firebase_uid",
        "users",
        ["firebase_uid"],
        unique=True,
    )


def downgrade() -> None:
    """Drop the firebase_uid index and column from the users table."""
    op.drop_index("ix_users_firebase_uid", table_name="users")
    op.drop_column("users", "firebase_uid")
