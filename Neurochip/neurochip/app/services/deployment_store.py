"""Deployment log persistence, backed by a typed SQLAlchemy repository."""

from sqlalchemy import select

from ..schemas.deployments import DeploymentRecord
from .deployment_db import DB_PATH, DeploymentDB, session_scope

__all__ = ["DB_PATH", "get_deployment", "list_deployments", "record_deployment"]


def _to_record(row: DeploymentDB) -> DeploymentRecord:
    return DeploymentRecord(
        id=row.id,
        timestamp=row.timestamp,
        network_spec_hash=row.network_spec_hash,
        target_id=row.target_id,
        quantization_bits=row.quantization_bits,
        firmware_version=row.firmware_version,
        serial_port=row.serial_port,
        device_id=row.device_id,
        notes=row.notes,
    )


def record_deployment(record: DeploymentRecord) -> DeploymentRecord:
    with session_scope() as session:
        session.merge(
            DeploymentDB(
                id=record.id,
                timestamp=record.timestamp,
                network_spec_hash=record.network_spec_hash,
                target_id=record.target_id,
                quantization_bits=record.quantization_bits,
                firmware_version=record.firmware_version,
                serial_port=record.serial_port,
                device_id=record.device_id,
                notes=record.notes,
            )
        )
        session.commit()
    return record


def list_deployments(target_id: str | None = None, limit: int = 100) -> list[DeploymentRecord]:
    with session_scope() as session:
        stmt = select(DeploymentDB).order_by(DeploymentDB.timestamp.desc()).limit(limit)
        if target_id:
            stmt = stmt.where(DeploymentDB.target_id == target_id)
        rows = session.execute(stmt).scalars().all()
        return [_to_record(row) for row in rows]


def get_deployment(deployment_id: str) -> DeploymentRecord | None:
    with session_scope() as session:
        row = session.get(DeploymentDB, deployment_id)
        return _to_record(row) if row is not None else None
