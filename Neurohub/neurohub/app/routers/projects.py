"""Router for project-related endpoints."""

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy.orm import Session

from neurohub.app.auth import get_current_user, require_admin
from neurohub.app.limiter import limiter
from neurohub.app.schemas.bundles import ProjectBundle
from neurohub.app.schemas.projects import Project
from neurohub.app.services import bundle_service, project_service
from neurohub.db.database import get_db
from neurohub.db.models import ProjectDB

router = APIRouter(tags=["Projects"])


def _get_project_user_identity(current_user: Any) -> tuple[str, bool]:
    """Normalize authenticated user identity for project access checks."""
    user_id = getattr(current_user, "user_id", None) or getattr(current_user, "id", None)
    if not isinstance(user_id, str) or not user_id:
        raise HTTPException(status_code=500, detail="Invalid authenticated user")

    is_admin = getattr(current_user, "is_admin", None)
    if not isinstance(is_admin, bool):
        is_admin = getattr(current_user, "role", None) == "admin"

    return user_id, is_admin


@router.get(
    "/projects",
    response_model=list[Project],
    dependencies=[Depends(get_current_user)],
)
@limiter.limit("120/minute")
def list_projects(
    request: Request,
    response: Response,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_user: Any = Depends(get_current_user),
) -> list[ProjectDB]:
    """Retrieve a list of all projects visible to the current user.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        skip: Number of projects to skip (offset).
        limit: Maximum number of projects to return.
        db: SQLAlchemy database session.
        current_user: The currently authenticated user.

    Returns:
        A list of project database model instances.
    """
    # If user is admin, show all projects. Otherwise filter by user_id.
    user_id, is_admin = _get_project_user_identity(current_user)
    user_filter = None if is_admin else user_id
    db_projects = project_service.get_projects(db, user_id=user_filter, skip=skip, limit=limit)
    return db_projects


@router.post(
    "/projects",
    response_model=Project,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_admin)],
)
@limiter.limit("30/minute")
def create_project(
    request: Request,
    response: Response,
    project: Project,
    db: Session = Depends(get_db),
    current_user: Any = Depends(get_current_user),
) -> ProjectDB:
    """Create a new project.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        project: Project schema containing the new project's data.
        db: SQLAlchemy database session.
        current_user: The authenticated admin user creating the project.

    Returns:
        The newly created project database model instance.

    Raises:
        HTTPException: If a project with the same ID already exists.
    """
    db_project = project_service.get_project(db, project_id=project.id)
    if db_project:
        raise HTTPException(status_code=400, detail="Project already exists")
    return project_service.create_project(db, project)


def check_project_access(
    project: ProjectDB, user_id: str, admin: bool, min_role: str | None = None
) -> None:
    """Check if a user has access to a project."""
    if admin or project.owner == user_id:
        return

    member = next((m for m in (project.members or []) if m.get("user_id") == user_id), None)
    if not member:
        raise HTTPException(status_code=403, detail="Not a project member")

    if min_role == "admin" and member.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Project admin role required")


@router.get("/projects/{id}", response_model=Project)
@limiter.limit("120/minute")
def get_project(
    request: Request,
    response: Response,
    id: str,
    db: Session = Depends(get_db),
    current_user: Any = Depends(get_current_user),
) -> ProjectDB:
    """Retrieve a single project by its ID.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        id: The unique identifier of the project.
        db: SQLAlchemy database session.
        current_user: The currently authenticated user.

    Returns:
        The project database model instance.

    Raises:
        HTTPException: If the project is not found.
    """
    db_project = project_service.get_project(db, project_id=id)
    if db_project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    user_id, is_admin = _get_project_user_identity(current_user)
    check_project_access(db_project, user_id, is_admin)
    return db_project


@router.put(
    "/projects/{id}",
    response_model=Project,
)
@limiter.limit("30/minute")
def update_project(
    request: Request,
    response: Response,
    id: str,
    project_update: dict[str, Any],
    db: Session = Depends(get_db),
    current_user: Any = Depends(get_current_user),
) -> ProjectDB:
    """Update an existing project.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        id: The unique identifier of the project to update.
        project_update: A dictionary of project attributes to update.
        db: SQLAlchemy database session.
        current_user: The currently authenticated user.

    Returns:
        The updated project database model instance.

    Raises:
        HTTPException: If the project is not found.
    """
    db_project = project_service.get_project(db, project_id=id)
    if db_project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    user_id, is_admin = _get_project_user_identity(current_user)
    check_project_access(db_project, user_id, is_admin, min_role="admin")

    updated_project = project_service.update_project(db, id, project_update, user_id=user_id)
    if updated_project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return updated_project


@router.delete(
    "/projects/{id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
@limiter.limit("30/minute")
def delete_project(
    request: Request,
    response: Response,
    id: str,
    db: Session = Depends(get_db),
    current_user: Any = Depends(get_current_user),
) -> None:
    """Delete a project.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        id: The unique identifier of the project to delete.
        db: SQLAlchemy database session.
        current_user: The currently authenticated user.

    Raises:
        HTTPException: If the project is not found.
    """
    db_project = project_service.get_project(db, project_id=id)
    if not db_project:
        raise HTTPException(status_code=404, detail="Project not found")

    user_id, is_admin = _get_project_user_identity(current_user)
    check_project_access(db_project, user_id, is_admin, min_role="admin")

    success = project_service.delete_project(db, project_id=id, user_id=user_id)
    if not success:
        raise HTTPException(status_code=404, detail="Project not found")


@router.post("/projects/{id}/export", response_model=ProjectBundle)
@limiter.limit("30/minute")
def export_project(
    request: Request, response: Response, id: str, db: Session = Depends(get_db)
) -> ProjectBundle:
    """Export a project and its associated data into a bundle.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        id: The unique identifier of the project to export.
        db: SQLAlchemy database session.

    Returns:
        A ProjectBundle containing the project data.

    Raises:
        HTTPException: If the project is not found.
    """
    try:
        return bundle_service.export_project_bundle(db, project_id=id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e)) from e


@router.post("/projects/import", response_model=Project)
@limiter.limit("30/minute")
def import_project(
    request: Request, response: Response, bundle: ProjectBundle, db: Session = Depends(get_db)
) -> ProjectDB:
    """Import a project bundle.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        bundle: The project bundle data to import.
        db: SQLAlchemy database session.

    Returns:
        The newly created project database model instance.

    Raises:
        HTTPException: If the project already exists or the version is unsupported.
    """
    try:
        return bundle_service.import_project_bundle(db, bundle)
    except ValueError as e:
        status_code = 400
        if "already exists" in str(e):
            status_code = 409
        raise HTTPException(status_code=status_code, detail=str(e)) from e
