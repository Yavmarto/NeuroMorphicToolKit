from neurosim.app.schemas.components import ComponentBlock


def test_component_block_has_custom_fields():
    cb = ComponentBlock(
        id="test",
        name="Test",
        category="neurons",
        description="",
        icon="test",
        parameters=[],
        ports=[],
        cnl_template="",
    )
    # defaults
    assert cb.is_custom is False
    assert cb.canvas_contexts == []
    assert cb.supported_frameworks == []
    assert cb.author == ""
    assert cb.version == "1.0.0"
    assert cb.source_path is None
    assert cb.base_pipeline_type is None


def test_custom_fields_round_trip():
    cb = ComponentBlock(
        id="custom_user_mynode",
        name="My Node",
        category="neurons",
        description="",
        icon="custom_node",
        parameters=[],
        ports=[],
        cnl_template="",
        is_custom=True,
        canvas_contexts=["model", "training"],
        supported_frameworks=["nengo"],
        author="user",
        version="1.0.0",
        source_path="/home/user/.nmtk/custom_nodes/my_node.py",
        base_pipeline_type="forwardPass",
    )
    assert cb.is_custom is True
    assert cb.canvas_contexts == ["model", "training"]
    assert cb.supported_frameworks == ["nengo"]
    assert cb.source_path == "/home/user/.nmtk/custom_nodes/my_node.py"
    assert cb.base_pipeline_type == "forwardPass"
