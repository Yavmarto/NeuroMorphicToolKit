"""Pure shape inference for compiled NIR-CNL nodes."""

from __future__ import annotations

from typing import Any

import nir
import numpy as np

from neurocnl.nir_cnl.ir_types import NIREdgeRecord

__all__ = [
    "conv2d_output_shape",
    "infer_known_shapes",
    "infer_output_shape",
    "pair",
    "pool2d_output_shape",
    "shape_tuple",
    "vector_node_shape",
]


def shape_tuple(value: Any) -> tuple[int, ...] | None:
    """Normalize an NIR shape value to a Python tuple."""
    if value is None:
        return None
    if isinstance(value, dict):
        if not value:
            return None
        value = next(iter(value.values()))
    array = np.asarray(value, dtype=int).flatten()
    if array.size == 0:
        return None
    return tuple(int(item) for item in array)


def pair(value: Any, default: tuple[int, int]) -> tuple[int, int]:
    """Normalize a scalar or sequence to a two-dimensional parameter."""
    if value is None:
        return default
    array = np.asarray(value, dtype=int).flatten()
    if array.size == 0:
        return default
    if array.size == 1:
        item = int(array[0])
        return (item, item)
    return (int(array[0]), int(array[1]))


def conv2d_output_shape(
    node: nir.Conv2d,
    input_shape: tuple[int, ...] | None,
) -> tuple[int, ...] | None:
    """Infer the output shape of a two-dimensional convolution."""
    weight = np.asarray(node.weight)
    if weight.ndim != 4:
        return None
    out_channels = int(weight.shape[0])
    spatial_shape: tuple[int, int] | None = None
    if input_shape is not None and len(input_shape) >= 3:
        spatial_shape = (int(input_shape[-2]), int(input_shape[-1]))
    else:
        candidate = shape_tuple(getattr(node, "input_shape", None))
        if candidate is not None and len(candidate) >= 2:
            spatial_shape = (int(candidate[-2]), int(candidate[-1]))
    if spatial_shape is None:
        return None

    stride = pair(getattr(node, "stride", None), (1, 1))
    padding = pair(getattr(node, "padding", None), (0, 0))
    dilation = pair(getattr(node, "dilation", None), (1, 1))
    kernel_h, kernel_w = int(weight.shape[2]), int(weight.shape[3])
    out_h = (
        (spatial_shape[0] + 2 * padding[0] - dilation[0] * (kernel_h - 1) - 1) // stride[0]
    ) + 1
    out_w = (
        (spatial_shape[1] + 2 * padding[1] - dilation[1] * (kernel_w - 1) - 1) // stride[1]
    ) + 1
    return (out_channels, max(1, int(out_h)), max(1, int(out_w)))


def pool2d_output_shape(
    node: nir.AvgPool2d | nir.SumPool2d,
    input_shape: tuple[int, ...] | None,
) -> tuple[int, ...] | None:
    """Infer the output shape of a two-dimensional pooling node."""
    if input_shape is None or len(input_shape) < 3:
        return input_shape
    kernel = pair(getattr(node, "kernel_size", None), (2, 2))
    stride = pair(getattr(node, "stride", None), kernel)
    padding = pair(getattr(node, "padding", None), (0, 0))
    out_h = ((int(input_shape[-2]) + 2 * padding[0] - kernel[0]) // stride[0]) + 1
    out_w = ((int(input_shape[-1]) + 2 * padding[1] - kernel[1]) // stride[1]) + 1
    return (int(input_shape[0]), max(1, int(out_h)), max(1, int(out_w)))


def vector_node_shape(node: Any) -> tuple[int, ...] | None:
    """Infer a one-dimensional shape from a vector-valued node field."""
    for attribute in (
        "tau",
        "tau_mem",
        "r",
        "v_threshold",
        "scale",
        "delay",
        "threshold",
    ):
        value = getattr(node, attribute, None)
        if value is None:
            continue
        size = int(np.asarray(value).size)
        if size > 0:
            return (size,)
    return None


def infer_output_shape(
    node: nir.NIRNode,
    input_shape: tuple[int, ...] | None,
) -> tuple[int, ...] | None:
    """Infer one node's output shape from its value and upstream shape."""
    if isinstance(node, nir.Input):
        return shape_tuple(node.input_type)
    if isinstance(node, nir.Output):
        return shape_tuple(node.output_type)
    if isinstance(node, nir.Conv2d):
        return conv2d_output_shape(node, input_shape)
    if isinstance(node, nir.AvgPool2d | nir.SumPool2d):
        return pool2d_output_shape(node, input_shape)
    if isinstance(node, nir.Linear | nir.Affine):
        weight = np.asarray(node.weight)
        if weight.ndim >= 1:
            return (int(weight.shape[0]),)
    if isinstance(node, nir.Flatten):
        raw_shape = shape_tuple(getattr(node, "input_type", None)) or input_shape
        if raw_shape is None:
            return None
        return (int(np.prod(raw_shape, dtype=int)),)
    if input_shape is not None:
        return input_shape
    return vector_node_shape(node)


def infer_known_shapes(
    nodes: dict[str, nir.NIRNode],
    edges: list[NIREdgeRecord],
) -> dict[str, tuple[int, ...]]:
    """Propagate known shapes through the graph until reaching a fixed point."""
    shapes: dict[str, tuple[int, ...]] = {}
    incoming: dict[str, list[str]] = {}
    for edge in edges:
        incoming.setdefault(edge.target, []).append(edge.src)

    changed = True
    while changed:
        changed = False
        for name, node in nodes.items():
            upstream_shape = next(
                (
                    shapes[source_name]
                    for source_name in incoming.get(name, [])
                    if source_name in shapes
                ),
                None,
            )
            inferred = infer_output_shape(node, upstream_shape)
            if inferred is not None and shapes.get(name) != inferred:
                shapes[name] = inferred
                changed = True
    return shapes
