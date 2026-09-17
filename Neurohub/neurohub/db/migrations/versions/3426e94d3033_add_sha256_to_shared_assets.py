"""add sha256 to shared_assets.

Revision ID: 3426e94d3033
Revises: a838fc1f0016
Create Date: 2026-04-01 20:13:06.889144

"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "3426e94d3033"
down_revision: str | Sequence[str] | None = "a838fc1f0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    # Column might already exist from failed previous run due to SQLite lack of DDL transactions
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = [c["name"] for c in inspector.get_columns("shared_assets")]

    if "sha256" not in columns:
        with op.batch_alter_table("shared_assets", schema=None) as batch_op:
            batch_op.add_column(sa.Column("sha256", sa.String(), nullable=True))

    # Populate existing rows
    op.execute(
        "UPDATE shared_assets "
        "SET sha256 = "
        "'0000000000000000000000000000000000000000000000000000000000000000' "
        "WHERE sha256 IS NULL OR sha256 = ''"
    )

    with op.batch_alter_table("shared_assets", schema=None) as batch_op:
        batch_op.alter_column("sha256", nullable=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("shared_assets", "sha256")
