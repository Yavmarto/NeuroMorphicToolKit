"""Service for managing projects in NeuroHub."""

import uuid
from datetime import datetime, UTC
from typing import Any

from sqlalchemy.orm import Session

from neurohub.app.schemas.projects import Project
from neurohub.db.models import ProjectDB


def get_project(db: Session, project_id: str) -> ProjectDB | None:
    """Retrieve a single project by its ID."""
    return db.query(ProjectDB).filter(ProjectDB.id == project_id).first()


def get_projects(
    db: Session, user_id: str | None = None, skip: int = 0, limit: int = 100
) -> list[ProjectDB]:
    """Retrieve projects with pagination, optionally filtered by user."""
    query = db.query(ProjectDB)
    if user_id:
        from sqlalchemy import or_

        try:
            bind: Any = db.get_bind()
            bind_url = getattr(bind, "url", getattr(getattr(bind, "engine", None), "url", ""))
            is_sqlite = "sqlite" in str(bind_url)
        except Exception:
            is_sqlite = False

        if is_sqlite:
            projects = db.query(ProjectDB).all()
            filtered = [
                p
                for p in projects
                if p.owner == user_id or any(m.get("user_id") == user_id for m in (p.members or []))
            ]
            return filtered[skip : skip + limit]

        query = query.filter(
            or_(
                ProjectDB.owner == user_id,
                ProjectDB.members.contains([{"user_id": user_id}]),
            )
        )
    return query.offset(skip).limit(limit).all()


def create_project(db: Session, project: Project) -> ProjectDB:
    """Create a new project in the database."""
    now = datetime.now(UTC).isoformat()
    db_project = ProjectDB(
        id=project.id or str(uuid.uuid4()),
        name=project.name,
        description=project.description,
        created_at=project.created_at or now,
        updated_at=now,
        owner=project.owner,
        members=[m.model_dump() for m in project.members],
        links=project.links.model_dump() if project.links else {},
        status=project.status,
        tags=project.tags,
    )
    db.add(db_project)
    db.commit()
    db.refresh(db_project)
    return db_project


def update_project(
    db: Session, project_id: str, project_update: dict[str, Any], user_id: str = "unknown"
) -> ProjectDB | None:
    """Update an existing project's attributes."""
    del user_id  # reserved for future audit hooks
    db_project = get_project(db, project_id)
    if db_project:
        for key, value in project_update.items():
            setattr(db_project, key, value)
        db_project.updated_at = datetime.now(UTC).isoformat()
        db.commit()
        db.refresh(db_project)
    return db_project


def delete_project(db: Session, project_id: str, user_id: str = "unknown") -> bool:
    """Delete a project from the database."""
    del user_id
    db_project = get_project(db, project_id)
    if db_project:
        db.delete(db_project)
        db.commit()
        return True
    return False
