"""GitHub-backed Neurohub workspace API."""

from __future__ import annotations

from collections.abc import Generator
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from neurohub.app.services.github_client import GitHubClient, GitHubError
from neurohub.app.services.github_workspace_store import (
    GitHubWorkspaceStore,
    WorkspaceSaveConflict,
)
from neurohub.contracts.workspace_contracts import (
    CollaboratorUpdate,
    WorkspaceConflict,
    WorkspaceCreate,
    WorkspaceResponse,
    WorkspaceSummary,
    WorkspaceUpdate,
    WorkspaceVisibilityUpdate,
)

router = APIRouter(prefix="/workspaces", tags=["Neurohub Workspaces"])
_bearer = HTTPBearer(auto_error=False)


def get_workspace_store(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> Generator[GitHubWorkspaceStore, None, None]:
    """Build a request-scoped workspace store using the user's OAuth token."""
    if credentials is None or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sign in to Neurohub to access shared workspaces.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        client = GitHubClient(credentials.credentials)
    except GitHubError as exc:
        raise _http_error(exc) from exc
    try:
        yield GitHubWorkspaceStore(client)
    finally:
        client.close()


def _http_error(exc: GitHubError) -> HTTPException:
    headers = {"Retry-After": exc.retry_after} if exc.retry_after else None
    return HTTPException(status_code=exc.status_code, detail=str(exc), headers=headers)


@router.get("", response_model=list[WorkspaceSummary])
def list_workspaces(
    store: GitHubWorkspaceStore = Depends(get_workspace_store),
) -> list[WorkspaceSummary]:
    """List all GitHub-backed workspaces visible to the caller."""
    try:
        return store.list_workspaces()
    except GitHubError as exc:
        raise _http_error(exc) from exc


@router.post("", response_model=WorkspaceResponse, status_code=status.HTTP_201_CREATED)
def create_workspace(
    request: WorkspaceCreate,
    store: GitHubWorkspaceStore = Depends(get_workspace_store),
) -> WorkspaceResponse:
    """Create a private-by-default workspace repository."""
    try:
        return store.create_workspace(request)
    except GitHubError as exc:
        raise _http_error(exc) from exc


@router.get("/{owner}/{slug}", response_model=WorkspaceResponse)
def get_workspace(
    owner: str,
    slug: str,
    store: GitHubWorkspaceStore = Depends(get_workspace_store),
) -> WorkspaceResponse:
    """Open the current verified workspace revision."""
    try:
        return store.get_workspace(owner, slug)
    except GitHubError as exc:
        raise _http_error(exc) from exc


@router.put(
    "/{owner}/{slug}",
    response_model=WorkspaceResponse,
    responses={409: {"model": WorkspaceConflict}},
)
def update_workspace(
    owner: str,
    slug: str,
    request: WorkspaceUpdate,
    store: GitHubWorkspaceStore = Depends(get_workspace_store),
) -> WorkspaceResponse:
    """Save one atomic workspace revision or return a stable conflict."""
    try:
        return store.update_workspace(owner, slug, request)
    except WorkspaceSaveConflict as exc:
        conflict = WorkspaceConflict(base_commit=exc.base_commit, remote_commit=exc.remote_commit)
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=conflict.model_dump(),
        ) from exc
    except GitHubError as exc:
        raise _http_error(exc) from exc


@router.put("/{owner}/{slug}/collaborators/{username}", status_code=status.HTTP_204_NO_CONTENT)
def add_collaborator(
    owner: str,
    slug: str,
    username: str,
    request: CollaboratorUpdate,
    store: GitHubWorkspaceStore = Depends(get_workspace_store),
) -> Response:
    """Grant a user repository-backed workspace access."""
    try:
        store.add_collaborator(owner, slug, username, request.permission)
    except GitHubError as exc:
        raise _http_error(exc) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/{owner}/{slug}/collaborators/{username}", status_code=status.HTTP_204_NO_CONTENT)
def remove_collaborator(
    owner: str,
    slug: str,
    username: str,
    store: GitHubWorkspaceStore = Depends(get_workspace_store),
) -> Response:
    """Revoke a user's repository-backed workspace access."""
    try:
        store.remove_collaborator(owner, slug, username)
    except GitHubError as exc:
        raise _http_error(exc) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{owner}/{slug}/visibility", response_model=WorkspaceResponse)
def set_visibility(
    owner: str,
    slug: str,
    request: WorkspaceVisibilityUpdate,
    store: GitHubWorkspaceStore = Depends(get_workspace_store),
) -> WorkspaceResponse:
    """Make a workspace public or private after explicit confirmation."""
    try:
        return store.set_public(owner, slug, public=request.public)
    except GitHubError as exc:
        raise _http_error(exc) from exc


@router.delete("/{owner}/{slug}", status_code=status.HTTP_204_NO_CONTENT)
def archive_workspace(
    owner: str,
    slug: str,
    store: GitHubWorkspaceStore = Depends(get_workspace_store),
) -> Response:
    """Archive a workspace instead of permanently deleting it."""
    try:
        store.archive(owner, slug)
    except GitHubError as exc:
        raise _http_error(exc) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)
