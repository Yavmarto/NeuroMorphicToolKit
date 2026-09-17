"""Router for component related endpoints."""

from fastapi import APIRouter, Query, Request, Response

from ..limiter import rate_limit
from ..schemas.components import ComponentBlock
from ..services.components import load_components

router = APIRouter(prefix="/api/neurosim/components", tags=["components"])


@router.get("", response_model=list[ComponentBlock])
@rate_limit("60/minute")
def list_components(
    request: Request,
    response: Response,
    category: str | None = None,
    canvas: str | None = Query(
        default=None,
        description="Filter by canvas context (model, training, eval, inference)",
    ),
    skip: int = 0,
    limit: int = 100,
) -> list[ComponentBlock]:
    """List all available component blocks with parameter schemas.

    Args:
        request (Request): The incoming request object.
        response (Response): The FastAPI response used by SlowAPI for rate-limit headers.
        category (str | None): Optional category to filter components.
        canvas (str | None): Optional canvas context to filter components.
            Components with an empty ``canvas_contexts`` list are included in all canvases.
        skip (int): Number of components to skip for pagination.
        limit (int): Maximum number of components to return for pagination.

    Returns:
        List[ComponentBlock]: A list of component blocks.
    """
    components = list(load_components().values())
    if category is not None:
        components = [block for block in components if block.category == category]
    if canvas is not None:
        components = [
            c
            for c in components
            if not getattr(c, "canvas_contexts", []) or canvas in c.canvas_contexts
        ]

    components.sort(key=lambda x: x.id)
    return components[skip : skip + limit]


@router.get("/categories", response_model=list[str])
@rate_limit("60/minute")
def list_categories(request: Request, response: Response) -> list[str]:
    """List all unique component categories.

    Returns:
        List[str]: A list of unique category names.
    """
    components = load_components()
    categories = {block.category for block in components.values()}
    return sorted(categories)
