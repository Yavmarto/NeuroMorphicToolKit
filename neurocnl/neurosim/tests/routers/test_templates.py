from fastapi.testclient import TestClient

from neurosim.app.main import app

client = TestClient(app)


def test_list_templates() -> None:
    response = client.get("/api/neurosim/templates")
    assert response.status_code == 200
    templates = response.json()
    assert isinstance(templates, list)
    assert len(templates) >= 1
    template_ids = [t["id"] for t in templates]
    assert "reflex_arc" in template_ids
    assert "graph" not in templates[0]


def test_get_template() -> None:
    response = client.get("/api/neurosim/templates/reflex_arc")
    assert response.status_code == 200
    template = response.json()
    assert template["id"] == "reflex_arc"
    assert "graph" in template
    assert "cnl_spec" in template
    assert "threshold" in template["graph"]["nodes"][0]["parameters"]
    assert "Define a network named reflex_arc." in template["cnl_spec"]
    assert "Define a LIF neuron named efferent" in template["cnl_spec"]
    assert "Connect afferent to efferent." in template["cnl_spec"]


def test_get_template_not_found() -> None:
    response = client.get("/api/neurosim/templates/nonexistent")
    assert response.status_code == 404
