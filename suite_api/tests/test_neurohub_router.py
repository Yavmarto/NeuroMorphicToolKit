"""Regression coverage for NeuroHub routes mounted by the Suite API."""

from fastapi.routing import iter_route_contexts

from suite_api.main import app


def _mounted_paths() -> set[str | None]:
    # app.routes can hold lazy _IncludedRouter wrappers (no .path of their
    # own) instead of flattened APIRoute objects; iter_route_contexts()
    # resolves them the same way FastAPI's own OpenAPI generation does.
    return {ctx.path for ctx in iter_route_contexts(app.routes)}


def test_suite_api_exposes_neurohub_routes() -> None:
    routes = _mounted_paths()

    assert "/api/neurohub/health" in routes
    assert "/api/neurohub/projects" in routes
    assert "/api/neurohub/workspaces" in routes


def test_suite_api_keeps_neurocnl_routes_namespaced() -> None:
    routes = _mounted_paths()

    assert "/api/neurocnl/parse" in routes
    assert "/api/neurocnl/deploy/teensy/network" in routes
