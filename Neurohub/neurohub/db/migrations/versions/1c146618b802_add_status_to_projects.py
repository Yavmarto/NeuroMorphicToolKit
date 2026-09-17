"""add status to projects.

Revision ID: 1c146618b802
Revises: 3426e94d3033
Create Date: 2026-04-02 17:49:35.709675

"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "1c146618b802"
down_revision: str | Sequence[str] | None = "3426e94d3033"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table("projects") as batch_op:
        batch_op.add_column(
            sa.Column("status", sa.String(), nullable=False, server_default="not_started")
        )


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table("projects") as batch_op:
        batch_op.drop_column("status")
