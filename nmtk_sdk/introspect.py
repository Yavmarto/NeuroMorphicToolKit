from __future__ import annotations

import pathlib
import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from nmtk_sdk.custom_node import CustomNode


def _slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def introspect_node(cls: type[CustomNode], source_path: str | None = None) -> object:
    """Convert a CustomNode subclass into a ComponentBlock for the registry.

    Note: empty enum_values lists are normalised to None in the output ComponentBlock.
    """
    from neurosim.contracts.design_contracts import (
        ComponentBlock,
        ParameterDef,
        PortDef,
    )

    author = cls.author or "user"
    declared_node_id = getattr(cls, "node_id", None)
    node_id = declared_node_id or f"custom_{_slugify(author)}_{_slugify(cls.name)}"
    if not isinstance(node_id, str) or not re.fullmatch(r"custom_[a-z0-9_]+", node_id):
        raise ValueError(
            "CustomNode.node_id must start with 'custom_' and contain only "
            "lowercase letters, numbers, and underscores"
        )

    parameters = []
    ports = []

    for attr_name in dir(cls):
        if attr_name.startswith("_"):
            continue
        attr = getattr(cls, attr_name, None)
        if attr is None:
            continue
        if hasattr(attr, "_param_meta"):
            m = attr._param_meta
            try:
                parameters.append(
                    ParameterDef(
                        name=m["name"],
                        label=m["label"],
                        description=m.get("description", ""),
                        type=m["type"],
                        default=m["default"],
                        min=m.get("min"),
                        max=m.get("max"),
                        unit=m.get("unit", ""),
                        enum_values=m.get("enum_values")
                        or None,  # normalise [] → None for Pydantic ParameterDef
                    )
                )
            except (KeyError, Exception) as exc:
                import logging as _logging

                _logging.getLogger(__name__).warning(
                    "Skipping malformed @param metadata on '%s.%s': %s",
                    cls.__name__,
                    attr_name,
                    exc,
                )
        elif hasattr(attr, "_port_meta"):
            m = attr._port_meta
            ports.append(
                PortDef(
                    id=m["id"],
                    direction=m["direction"],
                    label=m["label"],
                )
            )

    return ComponentBlock(
        id=node_id,
        name=cls.name,
        category=cls.category,
        description=cls.description,
        icon=cls.icon,
        parameters=parameters,
        ports=ports,
        cnl_template="",
        is_custom=True,
        canvas_contexts=list(cls.canvases),
        supported_frameworks=list(cls.frameworks),
        author=cls.author,
        version=cls.version,
        source_path=source_path,
        source_filename=pathlib.Path(source_path).name if source_path else None,
        source_available=source_path is not None,
        base_component_id=getattr(cls, "base_component_id", None),
        base_nir_type=getattr(cls, "base_nir_type", None),
        base_pipeline_type=getattr(cls, "base_pipeline_type", None),
    )
