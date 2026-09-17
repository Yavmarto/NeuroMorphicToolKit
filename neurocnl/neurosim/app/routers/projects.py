"""Router for project management."""

import uuid
from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response

from backend.app.services.nir_graph_serializer import (
    NirCanvasConversionError,
    deserialize_canvas_graph,
)
from neurocnl.pipeline import generate_cnl_from_nir

from ..limiter import rate_limit
from ..schemas.projects import CreateProjectRequest, Project, ProjectSummary
from ..services.project_store import ProjectStore

router = APIRouter(prefix="/api/neurosim/projects", tags=["projects"])


def get_project_store() -> ProjectStore:
    """Dependency for getting the project store.

    Returns:
        ProjectStore: The project store instance.
    """
    return ProjectStore.get_default()


@router.post("", response_model=Project)
@rate_limit("60/minute")
async def create_project(
    request: Request,
    response: Response,
    payload: CreateProjectRequest,
    store: Annotated[ProjectStore, Depends(get_project_store)],
) -> Project:
    """Save a project.

    Args:
        request (CreateProjectRequest): The request to create a new project.
        response (Response): The FastAPI response used by SlowAPI for rate-limit headers.
        payload (CreateProjectRequest): The project data to save.
        store (ProjectStore): The project store.

    Returns:
        Project: The created project.
    """
    project_id = str(uuid.uuid4())
    try:
        cnl_spec = generate_cnl_from_nir(deserialize_canvas_graph(payload.graph))
    except NirCanvasConversionError:
        cnl_spec = ""

    project = Project(
        id=project_id,
        name=payload.name,
        description=payload.description,
        updated_at=datetime.now(UTC).isoformat() + "Z",
        graph=payload.graph,
        cnl_spec=cnl_spec,
    )

    await store.save_project(project)
    return project


@router.get("", response_model=list[ProjectSummary])
@rate_limit("60/minute")
async def list_projects(
    request: Request,
    response: Response,
    store: Annotated[ProjectStore, Depends(get_project_store)],
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
) -> list[ProjectSummary]:
    """List saved projects.

    Args:
        request (Request): The incoming request object.
        response (Response): The FastAPI response used by SlowAPI for rate-limit headers.
        store (ProjectStore): The project store.
        skip (int): Number of projects to skip.
        limit (int): Maximum number of projects to return.

    Returns:
        list[ProjectSummary]: A list of project summaries.
    """
    return await store.list_projects(skip=skip, limit=limit)


@router.get("/{project_id}", response_model=Project)
@rate_limit("60/minute")
async def get_project(
    request: Request,
    response: Response,
    project_id: str,
    store: Annotated[ProjectStore, Depends(get_project_store)],
) -> Project:
    """Load a project.

    Args:
        request (Request): The incoming request object.
        response (Response): The FastAPI response used by SlowAPI for rate-limit headers.
        project_id (str): The ID of the project to retrieve.
        store (ProjectStore): The project store.

    Returns:
        Project: The retrieved project.

    Raises:
        HTTPException: If the project is not found.
    """
    project = await store.get_project(project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return project
