"""REST API for viewing, validating, and saving user custom nodes."""

from __future__ import annotations

import os
import pathlib
import re
import tempfile
import uuid
from typing import Any, Literal

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ...contracts.design_contracts import ComponentBlock, ParameterDef, PortDef
from ..services.components import _invalidate_cache, load_components
from ..services.custom_node_source import (
    SourceDiagnostic,
    analyze_custom_node_source,
    generate_custom_node_source,
    inject_stable_node_id,
    source_revision,
)

router = APIRouter(prefix="/api/neurosim/custom-nodes", tags=["custom-nodes"])

CUSTOM_NODES_DIR = pathlib.Path.home() / ".nmtk" / "custom_nodes"


class InstallRequest(BaseModel):
    """A remote Python custom node to install."""

    download_url: str
    filename: str


class SaveRequest(BaseModel):
    """Source to create or update.

    ``filename`` remains optional only for the new Save-As flow; legacy callers
    may continue sending exactly ``filename`` and ``source``.
    """

    source: str
    filename: str | None = None
    target_component_id: str | None = None
    save_as: bool = False
    expected_revision: str | None = None


class SourceRequest(BaseModel):
    """Selected node metadata used to retrieve or generate source."""

    component_id: str
    nir_type: str | None = None
    pipeline_type: str | None = None
    canvas_context: Literal["model", "training", "eval", "inference"] | None = None
    display_name: str = ""
    category: str = "custom"
    parameters: dict[str, Any] = Field(default_factory=dict)
    parameter_definitions: list[ParameterDef] = Field(default_factory=list)
    ports: list[PortDef] = Field(default_factory=list)


class CustomNodeValidateRequest(BaseModel):
    """Python source to validate without saving."""

    source: str
    target_component_id: str | None = None


class DiagnosticResponse(BaseModel):
    """Editor-friendly source diagnostic."""

    message: str
    severity: Literal["error", "warning"]
    line: int
    column: int
    end_line: int | None = None
    end_column: int | None = None
    code: str


class SourceResponse(BaseModel):
    """Python source and save-mode metadata for the editor."""

    source: str
    component_id: str
    is_custom: bool
    save_mode: Literal["create", "update"]
    filename: str | None = None
    revision: str | None = None


class CustomNodeValidateResponse(BaseModel):
    """Static validation result."""

    valid: bool
    diagnostics: list[DiagnosticResponse]
    component: ComponentBlock | None = None


class InstallResponse(BaseModel):
    """Save/install result compatible with the original launcher contract."""

    installed_path: str
    filename: str
    component_id: str | None = None
    revision: str | None = None
    source: str | None = None
    component: ComponentBlock | None = None


def _validate_filename(filename: str) -> None:
    """Reject path traversal and non-.py filenames."""
    safe = pathlib.Path(filename).name
    if safe != filename or not filename.endswith(".py"):
        raise HTTPException(
            status_code=400,
            detail="Choose a plain Python filename ending in .py.",
        )


def _diagnostic_response(item: SourceDiagnostic) -> DiagnosticResponse:
    return DiagnosticResponse(
        message=item.message,
        severity=item.severity,
        line=item.line,
        column=item.column,
        end_line=item.end_line,
        end_column=item.end_column,
        code=item.code,
    )


def _analyze(source: str) -> Any:
    components = load_components()
    return analyze_custom_node_source(
        source,
        known_component_ids=set(components),
    )


def _validation_response(source: str) -> CustomNodeValidateResponse:
    analysis = _analyze(source)
    component = analysis.to_component() if analysis.valid else None
    return CustomNodeValidateResponse(
        valid=analysis.valid,
        diagnostics=[_diagnostic_response(item) for item in analysis.diagnostics],
        component=component,
    )


def _slug(value: str) -> str:
    result = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    return result or "node"


def _new_identity(display_name: str) -> tuple[str, str]:
    suffix = uuid.uuid4().hex[:8]
    slug = _slug(display_name)
    return f"custom_{slug}_{suffix}", f"{slug}_{suffix}.py"


def _atomic_write(destination: pathlib.Path, source: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.stem}-",
        suffix=".tmp",
        dir=destination.parent,
        text=True,
    )
    temporary_path = pathlib.Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(source)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, destination)
    finally:
        temporary_path.unlink(missing_ok=True)


def _component_source_path(component: ComponentBlock) -> pathlib.Path:
    if not component.is_custom or not component.source_path:
        raise HTTPException(
            status_code=400,
            detail="This built-in node must be saved as a new custom node.",
        )
    path = pathlib.Path(component.source_path)
    try:
        path.resolve().relative_to(CUSTOM_NODES_DIR.resolve())
    except ValueError as exc:
        raise HTTPException(
            status_code=400,
            detail="The custom node source is outside the managed node library.",
        ) from exc
    return path


@router.get("", response_model=list[str])
def list_custom_nodes() -> list[str]:
    """List filenames of installed custom nodes."""
    if not CUSTOM_NODES_DIR.exists():
        return []
    return sorted(path.name for path in CUSTOM_NODES_DIR.glob("*.py"))


@router.post("/source", response_model=SourceResponse)
def get_custom_node_source(request: SourceRequest) -> SourceResponse:
    """Return exact custom source or generate a built-in node class."""
    component = load_components().get(request.component_id)
    if component is not None and component.is_custom:
        source_path = _component_source_path(component)
        try:
            disk_source = source_path.read_text(encoding="utf-8")
        except OSError as exc:
            raise HTTPException(
                status_code=500,
                detail="The custom node source could not be read. Try reloading it.",
            ) from exc
        editor_source = inject_stable_node_id(disk_source, component.id)
        return SourceResponse(
            source=editor_source,
            component_id=component.id,
            is_custom=True,
            save_mode="update",
            filename=source_path.name,
            revision=source_revision(disk_source),
        )

    generated = generate_custom_node_source(
        component=component,
        component_id=request.component_id,
        nir_type=request.nir_type,
        display_name=request.display_name,
        category=request.category,
        parameters=request.parameters,
        parameter_definitions=request.parameter_definitions,
        ports=request.ports,
        pipeline_type=request.pipeline_type,
        canvas_context=request.canvas_context,
    )
    return SourceResponse(
        source=generated,
        component_id=request.component_id,
        is_custom=False,
        save_mode="create",
    )


@router.post("/validate", response_model=CustomNodeValidateResponse)
def validate_custom_node(
    request: CustomNodeValidateRequest,
) -> CustomNodeValidateResponse:
    """Validate Python and SDK metadata without executing user code."""
    return _validation_response(request.source)


@router.post("/install", response_model=InstallResponse)
async def install_custom_node(request: InstallRequest) -> InstallResponse:
    """Download, validate, and atomically install a custom node."""
    _validate_filename(request.filename)
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            response = await client.get(request.download_url)
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=502,
                detail="The custom node could not be downloaded from its source.",
            ) from exc
    try:
        source = response.content.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise HTTPException(
            status_code=400,
            detail="The downloaded custom node is not valid UTF-8 Python source.",
        ) from exc
    analysis = _analyze(source)
    if not analysis.valid:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "The downloaded custom node did not pass validation.",
                "diagnostics": [
                    _diagnostic_response(item).model_dump()
                    for item in analysis.diagnostics
                ],
            },
        )
    if analysis.node_id is None:
        node_id, _ = _new_identity(analysis.name or pathlib.Path(request.filename).stem)
        source = inject_stable_node_id(source, node_id)
    else:
        node_id = analysis.node_id
    destination = CUSTOM_NODES_DIR / request.filename
    _atomic_write(destination, source)
    _invalidate_cache()
    component = load_components().get(node_id)
    return InstallResponse(
        installed_path=str(destination),
        filename=destination.name,
        component_id=node_id,
        revision=source_revision(source),
        source=source,
        component=component,
    )


@router.post("/save", response_model=InstallResponse)
def save_custom_node(request: SaveRequest) -> InstallResponse:
    """Validate and atomically create or update custom-node source."""
    components = load_components()
    source = request.source
    filename = request.filename
    target_component: ComponentBlock | None = None
    if filename is not None:
        _validate_filename(filename)

    if request.target_component_id is not None:
        target_component = components.get(request.target_component_id)
        if target_component is None:
            raise HTTPException(
                status_code=404,
                detail="This custom node no longer exists. Save it as a new node instead.",
            )
        destination = _component_source_path(target_component)
        filename = destination.name
        try:
            current_source = destination.read_text(encoding="utf-8")
        except OSError as exc:
            raise HTTPException(
                status_code=500,
                detail="The existing custom node could not be read before saving.",
            ) from exc
        if (
            request.expected_revision is not None
            and request.expected_revision != source_revision(current_source)
        ):
            raise HTTPException(
                status_code=409,
                detail=(
                    "This custom node changed after the editor opened. "
                    "Reload it before saving so no work is overwritten."
                ),
            )
        if not request.save_as:
            source = inject_stable_node_id(source, target_component.id)
    elif filename is not None and (CUSTOM_NODES_DIR / filename).exists():
        target_component = next(
            (
                component
                for component in components.values()
                if component.is_custom and component.source_filename == filename
            ),
            None,
        )
        if target_component is not None:
            source = inject_stable_node_id(source, target_component.id)

    initial_analysis = _analyze(source)
    if not initial_analysis.valid:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "Fix the Python diagnostics before saving.",
                "diagnostics": [
                    _diagnostic_response(item).model_dump()
                    for item in initial_analysis.diagnostics
                ],
            },
        )

    is_create = request.save_as or target_component is None
    if is_create:
        node_id, generated_filename = _new_identity(
            initial_analysis.name or initial_analysis.class_name or "node"
        )
        source = inject_stable_node_id(source, node_id)
        filename = (
            generated_filename if request.save_as or filename is None else filename
        )
    elif target_component is not None:
        node_id = target_component.id
    else:
        raise HTTPException(
            status_code=400,
            detail="No target component found to update.",
        )

    if filename is None:
        raise HTTPException(
            status_code=400,
            detail="A filename is required when using the legacy save operation.",
        )
    _validate_filename(filename)

    final_analysis = _analyze(source)
    if not final_analysis.valid:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "Fix the Python diagnostics before saving.",
                "diagnostics": [
                    _diagnostic_response(item).model_dump()
                    for item in final_analysis.diagnostics
                ],
            },
        )
    if final_analysis.node_id != node_id:
        raise HTTPException(
            status_code=400,
            detail="The custom node identity could not be stabilized.",
        )

    destination = CUSTOM_NODES_DIR / filename
    if is_create and destination.exists() and request.filename is None:
        raise HTTPException(
            status_code=409,
            detail="A custom node with this filename already exists.",
        )
    previous_source: str | None = None
    if destination.exists():
        try:
            previous_source = destination.read_text(encoding="utf-8")
        except OSError as exc:
            raise HTTPException(
                status_code=500,
                detail="The existing custom node could not be backed up before saving.",
            ) from exc
    _atomic_write(destination, source)
    _invalidate_cache()
    component = load_components().get(node_id)
    if component is None:
        if previous_source is None:
            destination.unlink(missing_ok=True)
        else:
            _atomic_write(destination, previous_source)
        _invalidate_cache()
        raise HTTPException(
            status_code=422,
            detail=(
                "The source did not load as a reusable node, so the previous "
                "version was restored. Review its framework imports and implementation."
            ),
        )
    return InstallResponse(
        installed_path=str(destination),
        filename=filename,
        component_id=node_id,
        revision=source_revision(source),
        source=source,
        component=component,
    )


@router.delete("/{filename}", response_model=dict)
def delete_custom_node(filename: str) -> dict[str, Any]:
    """Delete an installed custom node."""
    _validate_filename(filename)
    target = CUSTOM_NODES_DIR / filename
    if not target.exists():
        raise HTTPException(status_code=404, detail=f"{filename} was not found.")
    target.unlink()
    _invalidate_cache()
    return {"deleted": filename}
