"""The suite API must expose the custom-node editor contract."""

from fastapi import FastAPI

from suite_api.domains.neurosim.router import router


def test_custom_node_source_validation_and_save_routes_are_mounted() -> None:
    app = FastAPI()
    app.include_router(router)
    paths = app.openapi()["paths"]

    assert "post" in paths["/api/neurosim/custom-nodes/source"]
    assert "post" in paths["/api/neurosim/custom-nodes/validate"]
    assert "post" in paths["/api/neurosim/custom-nodes/save"]
