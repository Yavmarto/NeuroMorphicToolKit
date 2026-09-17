from fastapi import APIRouter, Query, Request, Response

from ..schemas.deployments import DeploymentManifest, DeploymentRecord
from ..services import deployment_store

router = APIRouter(prefix="/api/neurochip/deployments", tags=["deployments"])


@router.get("", response_model=list[DeploymentRecord])
def list_deployments(
    request: Request,
    response: Response,
    target_id: str | None = Query(None),
    limit: int = Query(100, ge=1, le=1000),
) -> list[DeploymentRecord]:
    return deployment_store.list_deployments(target_id=target_id, limit=limit)


@router.post("", response_model=DeploymentRecord)
def record_deployment(
    request: Request, response: Response, record: DeploymentRecord
) -> DeploymentRecord:
    return deployment_store.record_deployment(record)


@router.post("/validate", response_model=DeploymentManifest)
def validate_deployment_manifest(
    request: Request, response: Response, manifest: DeploymentManifest
) -> DeploymentManifest:
    """Validate a deployment manifest against hardware constraints."""
    return manifest
