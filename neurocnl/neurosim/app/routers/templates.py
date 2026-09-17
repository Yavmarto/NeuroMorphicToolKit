"""Router for starter circuit template management."""

import json
import os
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request, Response

from ..limiter import rate_limit
from ..schemas.templates import StarterTemplate, TemplateSummary

router = APIRouter(prefix="/api/neurosim/templates", tags=["templates"])

TEMPLATES_DIR = Path(__file__).parent.parent.parent / "templates"


@router.get("", response_model=list[TemplateSummary])
@rate_limit("60/minute")
def list_templates(request: Request, response: Response) -> list[TemplateSummary]:
    """List all starter circuit templates (summaries only).

    Returns:
        List[TemplateSummary]: A list of template summaries.
    """
    summaries = []
    if TEMPLATES_DIR.exists():
        for root, _, files in os.walk(TEMPLATES_DIR):
            for file in files:
                if file.endswith(".json"):
                    filepath = Path(root) / file
                    try:
                        with open(filepath, encoding="utf-8") as f:
                            data = json.load(f)
                            # Pydantic allows parsing a subset of fields
                            summaries.append(TemplateSummary(**data))
                    except Exception as e:
                        print(f"Error loading {filepath}: {e}")
    return summaries


@router.get("/{id}", response_model=StarterTemplate)
@rate_limit("60/minute")
def get_template(request: Request, response: Response, id: str) -> StarterTemplate:
    """Get a specific template by ID (includes canvas layout + CNL spec).

    Args:
        request (Request): The incoming request object.
        response (Response): The FastAPI response used by SlowAPI for rate-limit headers.
        id (str): The ID of the template to retrieve.

    Returns:
        StarterTemplate: The retrieved template.

    Raises:
        HTTPException: If the template is not found or cannot be parsed.
    """
    if TEMPLATES_DIR.exists():
        filepath = TEMPLATES_DIR / f"{id}.json"
        if filepath.exists() and filepath.is_file():
            try:
                with open(filepath, encoding="utf-8") as f:
                    data = json.load(f)
                    return StarterTemplate(**data)
            except Exception as e:
                raise HTTPException(
                    status_code=500,
                    detail=f"Error parsing template: {e}",
                )
    raise HTTPException(status_code=404, detail="Template not found")
