import pathlib
import textwrap
import pytest
from nmtk_sdk.loader import load_custom_node, LoadError
from nmtk_sdk import CustomNode


VALID_SOURCE = textwrap.dedent("""
    from nmtk_sdk import CustomNode, param, port

    class MyNode(CustomNode):
        name = "My Node"
        category = "neurons"
        canvases = ["model"]
        frameworks = ["nengo"]

        @param(type="float", default=0.02, label="Tau")
        def tau_m(self): ...

        @port(direction="input", label="In")
        def spikes_in(self): ...

        def to_nengo(self, params):
            return object()
""")

NO_SUBCLASS_SOURCE = textwrap.dedent("""
    def helper():
        pass

    class NotANode:
        name = "Nope"
""")

SYNTAX_ERROR_SOURCE = "def (((broken"


def test_load_valid_file(tmp_path: pathlib.Path):
    p = tmp_path / "my_node.py"
    p.write_text(VALID_SOURCE)
    cls = load_custom_node(p)
    assert issubclass(cls, CustomNode)
    assert cls.name == "My Node"


def test_load_returns_first_subclass(tmp_path: pathlib.Path):
    p = tmp_path / "my_node.py"
    p.write_text(VALID_SOURCE)
    cls = load_custom_node(p)
    assert cls.__name__ == "MyNode"


def test_no_subclass_raises(tmp_path: pathlib.Path):
    p = tmp_path / "bad.py"
    p.write_text(NO_SUBCLASS_SOURCE)
    with pytest.raises(LoadError, match="No CustomNode subclass"):
        load_custom_node(p)


def test_syntax_error_raises(tmp_path: pathlib.Path):
    p = tmp_path / "broken.py"
    p.write_text(SYNTAX_ERROR_SOURCE)
    with pytest.raises(LoadError, match="syntax"):
        load_custom_node(p)


def test_nonexistent_file_raises():
    with pytest.raises(LoadError, match="not found"):
        load_custom_node(pathlib.Path("/nonexistent/file.py"))
