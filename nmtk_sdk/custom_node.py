from __future__ import annotations

from abc import ABCMeta
from typing import Any, ClassVar

_REQUIRED_ATTRS: tuple[str, ...] = ("name", "category", "canvases", "frameworks")


class _CustomNodeMeta(ABCMeta):
    """Validates required class attributes at subclass definition time."""

    def __new__(
        mcs, cls_name: str, bases: tuple, namespace: dict, **kwargs: Any
    ) -> type:
        cls = super().__new__(mcs, cls_name, bases, namespace, **kwargs)
        if cls_name == "CustomNode":
            return cls
        for attr in _REQUIRED_ATTRS:
            if not hasattr(cls, attr) or getattr(cls, attr) is None:
                raise TypeError(
                    f"CustomNode subclass '{cls_name}' must define class attribute '{attr}'"
                )
        return cls


class CustomNode(metaclass=_CustomNodeMeta):
    """Base class for user-defined custom SNN canvas nodes.

    Subclasses must set:
        name: str              — display name in the component palette
        category: str          — palette category (e.g. "neurons", "synapses")
        canvases: list[str]    — which canvases show this node
                                 ("model", "training", "eval", "inference")
        frameworks: list[str]  — supported sim backends
                                 ("nengo", "norse", "spikingjelley", "brian2")

    Declare parameters with @param and ports with @port on stub methods.
    Implement to_<framework>(self, params) for each supported framework.
    """

    name: ClassVar[str]
    category: ClassVar[str]
    canvases: ClassVar[list[str]]
    frameworks: ClassVar[list[str]]
    description: ClassVar[str] = ""
    icon: ClassVar[str] = "custom_node"
    version: ClassVar[str] = "1.0.0"
    author: ClassVar[str] = ""
    # Stable identity is optional for legacy custom nodes. Newly created nodes
    # receive one from the NeuroSim save API so display-name/author edits do not
    # break canvas references.
    node_id: ClassVar[str | None] = None
    # A generated custom node may delegate to a built-in component/NIR operator
    # until the author supplies an explicit framework implementation.
    base_component_id: ClassVar[str | None] = None
    base_nir_type: ClassVar[str | None] = None

    def to_nengo(self, params: dict[str, Any]) -> Any:
        raise NotImplementedError(f"{type(self).__name__} does not support nengo")

    def to_norse(self, params: dict[str, Any]) -> Any:
        raise NotImplementedError(f"{type(self).__name__} does not support norse")

    def to_spikingjelley(self, params: dict[str, Any]) -> Any:
        raise NotImplementedError(
            f"{type(self).__name__} does not support spikingjelley"
        )

    def to_brian2(self, params: dict[str, Any]) -> Any:
        raise NotImplementedError(f"{type(self).__name__} does not support brian2")

    def to_nir(self, params: dict[str, Any]) -> Any:
        raise NotImplementedError(f"{type(self).__name__} does not support NIR export")
