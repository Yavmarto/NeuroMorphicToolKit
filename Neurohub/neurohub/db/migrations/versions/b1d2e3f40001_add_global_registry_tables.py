"""add global registry tables.

Revision ID: b1d2e3f40001
Revises: 1c146618b802
Create Date: 2026-05-29 00:00:00.000000

Creates the five Neurohub Global Registry tables (artefacts, ratings, comments,
follows, activity) for the /api/v1 surface. Fully reversible (Property 29).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "b1d2e3f40001"
down_revision: str | Sequence[str] | None = "1c146618b802"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the global registry tables."""
    op.create_table(
        "registry_artefacts",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("type", sa.String(), nullable=False),
        sa.Column("owner", sa.String(), nullable=False),
        sa.Column("slug", sa.String(), nullable=False),
        sa.Column("version", sa.String(), nullable=False),
        sa.Column("description", sa.String(), nullable=True),
        sa.Column("tags", sa.JSON(), nullable=False),
        sa.Column("readme", sa.Text(), nullable=True),
        sa.Column("sha256", sa.String(), nullable=False),
        sa.Column("storage_key", sa.String(), nullable=False),
        sa.Column("file_size_bytes", sa.Integer(), nullable=False),
        sa.Column("download_count", sa.Integer(), nullable=False),
        sa.Column("average_rating", sa.Float(), nullable=False),
        sa.Column("rating_count", sa.Integer(), nullable=False),
        sa.Column("model_card", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.String(), nullable=False),
        sa.Column("updated_at", sa.String(), nullable=False),
        sa.Column("deleted_at", sa.String(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("owner", "slug", "version", name="uq_artefact_owner_slug_version"),
    )
    op.create_index("ix_registry_artefacts_id", "registry_artefacts", ["id"])
    op.create_index("ix_registry_artefacts_type", "registry_artefacts", ["type"])
    op.create_index("ix_registry_artefacts_owner", "registry_artefacts", ["owner"])
    op.create_index("ix_registry_artefacts_slug", "registry_artefacts", ["slug"])
    op.create_index("ix_registry_artefacts_deleted_at", "registry_artefacts", ["deleted_at"])

    op.create_table(
        "registry_ratings",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("artefact_id", sa.String(), nullable=False),
        sa.Column("user_id", sa.String(), nullable=False),
        sa.Column("value", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.String(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("artefact_id", "user_id", name="uq_rating_artefact_user"),
    )
    op.create_index("ix_registry_ratings_id", "registry_ratings", ["id"])
    op.create_index("ix_registry_ratings_artefact_id", "registry_ratings", ["artefact_id"])
    op.create_index("ix_registry_ratings_user_id", "registry_ratings", ["user_id"])

    op.create_table(
        "registry_comments",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("artefact_id", sa.String(), nullable=False),
        sa.Column("author_id", sa.String(), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("created_at", sa.String(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_registry_comments_id", "registry_comments", ["id"])
    op.create_index("ix_registry_comments_artefact_id", "registry_comments", ["artefact_id"])
    op.create_index("ix_registry_comments_author_id", "registry_comments", ["author_id"])
    op.create_index("ix_registry_comments_created_at", "registry_comments", ["created_at"])

    op.create_table(
        "registry_follows",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("follower_id", sa.String(), nullable=False),
        sa.Column("followed_user_id", sa.String(), nullable=False),
        sa.Column("created_at", sa.String(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("follower_id", "followed_user_id", name="uq_follow_pair"),
        sa.CheckConstraint("follower_id != followed_user_id", name="ck_follow_not_self"),
    )
    op.create_index("ix_registry_follows_id", "registry_follows", ["id"])
    op.create_index("ix_registry_follows_follower_id", "registry_follows", ["follower_id"])
    op.create_index(
        "ix_registry_follows_followed_user_id", "registry_follows", ["followed_user_id"]
    )

    op.create_table(
        "registry_activity",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("follower_id", sa.String(), nullable=False),
        sa.Column("followed_user_id", sa.String(), nullable=False),
        sa.Column("artefact_id", sa.String(), nullable=False),
        sa.Column("event_type", sa.String(), nullable=False),
        sa.Column("created_at", sa.String(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_registry_activity_id", "registry_activity", ["id"])
    op.create_index("ix_registry_activity_follower_id", "registry_activity", ["follower_id"])
    op.create_index(
        "ix_registry_activity_followed_user_id", "registry_activity", ["followed_user_id"]
    )
    op.create_index("ix_registry_activity_artefact_id", "registry_activity", ["artefact_id"])
    op.create_index("ix_registry_activity_created_at", "registry_activity", ["created_at"])


def downgrade() -> None:
    """Drop the global registry tables (drops their indexes with them)."""
    op.drop_table("registry_activity")
    op.drop_table("registry_follows")
    op.drop_table("registry_comments")
    op.drop_table("registry_ratings")
    op.drop_table("registry_artefacts")
