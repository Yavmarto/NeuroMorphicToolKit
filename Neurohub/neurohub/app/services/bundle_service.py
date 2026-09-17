"""Service for exporting and importing project bundles."""

import hashlib

from sqlalchemy.orm import Session

from neurohub.app.schemas.bundles import ProjectBundle
from neurohub.app.schemas.projects import Project
from neurohub.contracts.bundle_contracts import BundleFormat, ExportBundle
from neurohub.db.models import ProjectDB


def export_project_bundle(db: Session, project_id: str) -> ProjectBundle:
    """Export project metadata into a bundle."""
    db_project = db.query(ProjectDB).filter(ProjectDB.id == project_id).first()
    if not db_project:
        raise ValueError("Project not found")

    return ProjectBundle(
        version=2,
        project=Project.model_validate(db_project),
    )


def import_project_bundle(db: Session, bundle: ProjectBundle) -> ProjectDB:
    """Import a project bundle into the database."""
    if bundle.version not in (1, 2):
        raise ValueError("Unsupported bundle version")

    existing_project = db.query(ProjectDB).filter(ProjectDB.id == bundle.project.id).first()
    if existing_project:
        raise ValueError("Project already exists")

    db_project = ProjectDB(
        id=bundle.project.id,
        name=bundle.project.name,
        description=bundle.project.description,
        created_at=bundle.project.created_at,
        updated_at=bundle.project.updated_at,
        owner=bundle.project.owner,
        members=[m.model_dump() for m in bundle.project.members],
        links=bundle.project.links.model_dump(),
        tags=bundle.project.tags,
        status=bundle.project.status,
    )
    db.add(db_project)
    db.commit()
    db.refresh(db_project)
    return db_project


def prepare_handoff_bundle(
    db: Session, project_id: str, target: str, workflow_id: str
) -> ExportBundle:
    """Prepare a contract-compliant ExportBundle for module handoff."""
    bundle_data = export_project_bundle(db, project_id)

    serialized = bundle_data.model_dump_json(exclude_none=True)
    bundle_hash = hashlib.sha256(serialized.encode()).hexdigest()

    contents = [
        f"projects/{project_id}/metadata.json",
    ]

    return ExportBundle(
        format=BundleFormat.NEUROSPACE,
        contents=contents,
        bundle_hash=bundle_hash,
        target=target,
        project_id=project_id,
        workflow_id=workflow_id,
    )
