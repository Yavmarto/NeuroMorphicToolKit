from __future__ import annotations

from collections.abc import Callable
from typing import Any, Literal


def param(
    *,
    type: Literal["float", "int", "bool", "enum", "text"],
    default: Any,
    label: str = "",
    description: str = "",
    unit: str = "",
    min: float | None = None,
    max: float | None = None,
    enum_values: list[str] | None = None,
) -> Callable[[Callable], Callable]:
    """Attach parameter metadata to a stub method on a CustomNode subclass."""

    def decorator(fn: Callable) -> Callable:
        fn._param_meta = {
            "name": fn.__name__,
            "type": type,
            "default": default,
            "label": label or fn.__name__,
            "description": description,
            "unit": unit,
            "min": min,
            "max": max,
            "enum_values": enum_values or [],
        }
        return fn

    return decorator


def port(
    *,
    direction: Literal["input", "output"],
    id: str | None = None,
    label: str = "",
    description: str = "",
) -> Callable[[Callable], Callable]:
    """Attach port metadata to a stub method on a CustomNode subclass."""

    def decorator(fn: Callable) -> Callable:
        fn._port_meta = {
            "id": id or fn.__name__,
            "direction": direction,
            "label": label or fn.__name__,
            "description": description,
        }
        return fn

    return decorator
