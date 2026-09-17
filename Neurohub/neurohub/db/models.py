"""SQLAlchemy database models for NeuroHub."""

from typing import Any

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    Float,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from neurohub.db.database import Base

__all__ = [
    "Base",
    "UserDB",
    "ProjectDB",
    "SharedAssetDB",
    "SuiteConfigDB",
    "ArtefactDB",
    "RatingDB",
    "CommentDB",
    "FollowDB",
    "RegistryActivityEntryDB",
]


class UserDB(Base):
    """Database model for a user."""

    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String, primary_key=True, index=True)
    username: Mapped[str] = mapped_column(String, unique=True, index=True)
    email: Mapped[str] = mapped_column(String, unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String)
    hashed_password: Mapped[str] = mapped_column(String)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    # Firebase UID — populated when NEUROHUB_AUTH_PROVIDER=firebase and the user
    # calls POST /api/v1/auth/sync.  Null for internal-auth users.
    firebase_uid: Mapped[str | None] = mapped_column(String, unique=True, index=True, nullable=True)
    # Supabase auth.users UID — populated when NEUROHUB_AUTH_PROVIDER=supabase
    # and the user calls POST /api/v1/auth/sync.  Null otherwise.
    supabase_uid: Mapped[str | None] = mapped_column(String, unique=True, index=True, nullable=True)


class ProjectDB(Base):
    """Database model for a project (registry grouping metadata)."""

    __tablename__ = "projects"

    id: Mapped[str] = mapped_column(String, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String, index=True)
    description: Mapped[str] = mapped_column(String)
    created_at: Mapped[str] = mapped_column(String)
    updated_at: Mapped[str] = mapped_column(String)
    owner: Mapped[str] = mapped_column(String)
    members: Mapped[list[dict[str, Any]]] = mapped_column(JSON)
    links: Mapped[dict[str, Any]] = mapped_column(JSON)
    status: Mapped[str] = mapped_column(String, default="not_started")
    tags: Mapped[list[str]] = mapped_column(JSON)


class SharedAssetDB(Base):
    """Database model for a shared asset."""

    __tablename__ = "shared_assets"

    id: Mapped[str] = mapped_column(String, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String, index=True)
    description: Mapped[str] = mapped_column(String)
    type: Mapped[str] = mapped_column(String, index=True)
    version: Mapped[int] = mapped_column(Integer)
    author: Mapped[str] = mapped_column(String)
    tags: Mapped[list[str]] = mapped_column(JSON)
    created_at: Mapped[str] = mapped_column(String)
    file_path: Mapped[str] = mapped_column(String)
    file_size_bytes: Mapped[int] = mapped_column(Integer)
    sha256: Mapped[str] = mapped_column(String)
    metadata_: Mapped[dict[str, Any]] = mapped_column(JSON)  # 'metadata' is reserved in Base


class SuiteConfigDB(Base):
    """Database model for suite configuration."""

    __tablename__ = "suite_config"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    neurosim_url: Mapped[str] = mapped_column(String)
    neurochip_url: Mapped[str] = mapped_column(String)
    neurobench_url: Mapped[str] = mapped_column(String)
    neurosense_url: Mapped[str] = mapped_column(String)
    neurocnl_url: Mapped[str] = mapped_column(String)
    shared_storage_path: Mapped[str] = mapped_column(String)
    default_project_settings: Mapped[dict[str, Any]] = mapped_column(JSON)


# ---------------------------------------------------------------------------
# Global Registry models (/api/v1 surface)
# ---------------------------------------------------------------------------


class ArtefactDB(Base):
    """Database model for a published registry artefact (a single version)."""

    __tablename__ = "registry_artefacts"
    __table_args__ = (
        UniqueConstraint("owner", "slug", "version", name="uq_artefact_owner_slug_version"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, index=True)
    type: Mapped[str] = mapped_column(String, index=True)
    owner: Mapped[str] = mapped_column(String, index=True)
    slug: Mapped[str] = mapped_column(String, index=True)
    version: Mapped[str] = mapped_column(String)
    description: Mapped[str | None] = mapped_column(String, nullable=True)
    tags: Mapped[list[str]] = mapped_column(JSON, default=list)
    readme: Mapped[str | None] = mapped_column(Text, nullable=True)
    sha256: Mapped[str] = mapped_column(String)
    storage_key: Mapped[str] = mapped_column(String)
    file_size_bytes: Mapped[int] = mapped_column(Integer)
    download_count: Mapped[int] = mapped_column(Integer, default=0)
    average_rating: Mapped[float] = mapped_column(Float, default=0.0)
    rating_count: Mapped[int] = mapped_column(Integer, default=0)
    model_card: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[str] = mapped_column(String)
    updated_at: Mapped[str] = mapped_column(String)
    deleted_at: Mapped[str | None] = mapped_column(String, nullable=True, index=True)


class RatingDB(Base):
    """Database model for a 1-5 star rating on an artefact (one per user)."""

    __tablename__ = "registry_ratings"
    __table_args__ = (UniqueConstraint("artefact_id", "user_id", name="uq_rating_artefact_user"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, index=True)
    artefact_id: Mapped[str] = mapped_column(String, index=True)
    user_id: Mapped[str] = mapped_column(String, index=True)
    value: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[str] = mapped_column(String)


class CommentDB(Base):
    """Database model for a comment on an artefact."""

    __tablename__ = "registry_comments"

    id: Mapped[str] = mapped_column(String, primary_key=True, index=True)
    artefact_id: Mapped[str] = mapped_column(String, index=True)
    author_id: Mapped[str] = mapped_column(String, index=True)
    content: Mapped[str] = mapped_column(Text)
    created_at: Mapped[str] = mapped_column(String, index=True)


class FollowDB(Base):
    """Database model for a publisher follow relationship."""

    __tablename__ = "registry_follows"
    __table_args__ = (
        UniqueConstraint("follower_id", "followed_user_id", name="uq_follow_pair"),
        CheckConstraint("follower_id != followed_user_id", name="ck_follow_not_self"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, index=True)
    follower_id: Mapped[str] = mapped_column(String, index=True)
    followed_user_id: Mapped[str] = mapped_column(String, index=True)
    created_at: Mapped[str] = mapped_column(String)


class RegistryActivityEntryDB(Base):
    """Database model for a follow/new-artefact activity feed entry."""

    __tablename__ = "registry_activity"

    id: Mapped[str] = mapped_column(String, primary_key=True, index=True)
    follower_id: Mapped[str] = mapped_column(String, index=True)
    followed_user_id: Mapped[str] = mapped_column(String, index=True)
    artefact_id: Mapped[str] = mapped_column(String, index=True)
    event_type: Mapped[str] = mapped_column(String)
    created_at: Mapped[str] = mapped_column(String, index=True)
