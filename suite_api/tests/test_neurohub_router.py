"""Regression coverage for NeuroHub routes mounted by the Suite API."""

from suite_api.main import app


def test_suite_api_exposes_neurohub_routes() -> None:
    routes = {route.path for route in app.routes}

    assert "/api/neurohub/health" in routes
    assert "/api/neurohub/projects" in routes
    assert "/api/neurohub/workspaces" in routes


def test_suite_api_keeps_neurocnl_routes_namespaced() -> None:
    routes = {route.path for route in app.routes}

    assert "/api/neurocnl/parse" in routes
    assert "/api/neurocnl/deploy/teensy/network" in routes
