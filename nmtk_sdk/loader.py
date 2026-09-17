from __future__ import annotations

import importlib.util
import pathlib
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from nmtk_sdk.custom_node import CustomNode


class LoadError(Exception):
    """Raised when a custom node file cannot be loaded or contains no valid subclass."""


def load_custom_node(path: pathlib.Path) -> type[CustomNode]:
    """Import a .py file and return the first CustomNode subclass found."""
    from nmtk_sdk.custom_node import CustomNode as _CustomNode

    if not path.exists():
        raise LoadError(f"File not found: {path}")

    module_name = f"_nmtk_custom_{path.stem}"

    try:
        spec = importlib.util.spec_from_file_location(module_name, path)
        if spec is None or spec.loader is None:
            raise LoadError(f"Cannot create module spec for {path}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)  # type: ignore[union-attr]
    except SyntaxError as exc:
        raise LoadError(f"syntax error in {path}: {exc}") from exc
    except LoadError:
        raise
    except Exception as exc:
        raise LoadError(f"failed to load {path}: {exc}") from exc

    for obj in vars(module).values():
        if (
            isinstance(obj, type)
            and issubclass(obj, _CustomNode)
            and obj is not _CustomNode
        ):
            return obj

    raise LoadError(f"No CustomNode subclass found in {path}")
