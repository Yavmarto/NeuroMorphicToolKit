"""Convert a trained NIR graph into a BrainChip Akida model.

Verified against akida 2.19.3 (dense path originally against 2.19.2; both
confirmed to agree). The layer semantics this relies on were measured from the
SDK rather than assumed, because the previous revision of this module had never
been executed against it: it passed a ``weights=`` argument to
``FullyConnected`` (no such parameter) and constructed ``akida.InputLayer``
(no such symbol), so every call raised.

What the SDK actually does, per experiment:

* weights live in ``layer.variables["weights"]``, shaped ``(1, 1, in, out)``
  int8 -- note the transpose relative to NIR's ``(out, in)``.
* ``predict()`` on a model whose last layer has ``activation=False`` returns the
  raw integer potential, ``sum(x_q * w_q)``.
* ``forward()`` returns
  ``clip(ceil((potential - threshold) / act_step), 0, 2**act_bits - 1)``.

Two consequences drive the design here. ``threshold`` is a plain subtracted
offset, so a NIR ``Affine`` bias folds into it exactly -- the previous revision
dropped bias entirely. And ``act_step`` sets the output scale: leave it at 1
and a 784-input layer saturates at the top of the range on every sample, which
is why `calibrate_act_steps` exists.

Akida's FullyConnected is a single-pass quantized unit, not a temporal LIF, so
a model converted from an snnTorch-trained LIF network is an approximation.
Measure the accuracy; do not assume it.

Conv2d/pooling support (``_PendingConv`` and the ``nir.Conv2d``/``nir.AvgPool2d``
branches below) has now been measured against real akida 2.19.3
(``InputConvolutional``/``Convolutional``), same as the dense path above. Per
experiment:

* the conv kernel weight layout is channel-last ``(kH, kW, C_in, C_out)`` --
  confirmed via ``layer.variables["weights"].shape``, matching what
  `_conv_weight_layout` already produced. No change needed there.
* ``akida.PoolType.Average`` is the correct member name -- confirmed.
* **``PoolType.Average`` is always global average pooling.** The SDK rejects
  any explicit ``pool_size``/``pool_stride`` for it (``pool_size should be -1
  when pool_type is set to ... PoolType.Average``) and always collapses the
  full remaining spatial extent to ``1x1``, regardless of input size or
  padding -- there is no windowed/strided average pooling on this hardware at
  all. A ``nir.AvgPool2d`` is only representable if its kernel covers the
  conv's *entire* output spatial extent (true global pooling); anything
  narrower has no Akida equivalent and must be rejected, not silently widened
  to global. Checked via ``_conv_output_spatial``, computed directly from the
  Conv2d node's own recorded ``input_shape``/``stride``/``padding`` (the CNL
  grammar requires ``input_shape`` on every Conv2d, not just the first) --
  not a guess, an SDK probe, or ``NIRGraph.infer_types()`` (which raises a
  false-positive type mismatch on a Conv2d -> LIF edge, since NIR neuron
  nodes carry per-channel parameters rather than per-spatial-position ones).
* **``groups > 1`` (grouped/depthwise Conv2d) has no Akida equivalent and is
  rejected, not routed to ``SeparableConvolutional``.** That layer turned out
  to be a depthwise+pointwise *decomposition* -- two separate weight
  variables, ``weights`` shaped ``(kH, kW, C_in, 1)`` (depthwise) and
  ``weights_pw`` shaped ``(1, 1, C_in, C_out)`` (pointwise) -- not a single
  grouped convolution. A NIR ``Conv2d`` with ``groups > 1`` carries one
  grouped-conv weight tensor, which doesn't decompose into that shape without
  real work this converter doesn't do; the original plan's assumption that
  ``groups > 1`` routes there was wrong and would have silently left
  ``weights_pw`` uninitialized. Express depthwise-separable convolutions as
  two explicit ``groups=1`` Conv2d nodes (depthwise kxk, then pointwise 1x1)
  in the NIR graph instead.
"""

from __future__ import annotations

from typing import Any

import nir
import numpy as np


class AkidaConversionError(RuntimeError):
    """The NIR graph cannot be expressed as an Akida model."""


def _require_akida() -> Any:
    """Import the Akida SDK on demand.

    Deliberately not a module-level import: this module is reachable from the
    backend, which has no SDK, and an eager import would make it unimportable
    there rather than failing only when a conversion is actually requested.
    """
    try:
        import akida
    except ImportError as exc:  # pragma: no cover - depends on the environment
        raise AkidaConversionError(
            "The Akida SDK is not installed in this environment, so a model "
            "cannot be converted. Run this from a kernel that has `akida`."
        ) from exc
    return akida


def quantize_weights(weights: np.ndarray[Any, Any], bits: int = 4) -> tuple[np.ndarray[Any, Any], float]:
    """Symmetrically quantize float weights, returning the array and its scale.

    The scale is returned rather than discarded because every downstream value
    -- thresholds, folded biases, activation steps -- has to be expressed in
    the same quantized units. Dropping it is what silently misaligns a
    converted model.

    int8 is the SDK's storage type at every width, but the *values* must fit
    `bits`: at 4 bits the usable range is [-7, 7], not [-127, 127].
    """
    if bits not in (1, 2, 4, 8):
        raise AkidaConversionError(
            f"Unsupported weight bit width {bits}; Akida accepts 1, 2, 4 or 8."
        )
    q_max = (2 ** (bits - 1)) - 1
    max_val = float(np.max(np.abs(weights))) if weights.size else 0.0
    if max_val == 0.0:
        return np.zeros(weights.shape, dtype=np.int8), 1.0
    scale = q_max / max_val
    quantized = np.clip(np.round(weights * scale), -q_max, q_max)
    return quantized.astype(np.int8), scale


def dequantize_weights(weights: np.ndarray[Any, Any], scale: float = 1.0) -> np.ndarray[Any, Any]:
    """Convert integer weights back to float32."""
    return weights.astype(np.float32) / scale if scale else weights.astype(np.float32)


def _topological_sort(graph: nir.NIRGraph) -> list[str]:
    """Kahn's algorithm over the NIR graph, so layers are built in order."""
    in_degree = dict.fromkeys(graph.nodes.keys(), 0)
    for _, target in graph.edges:
        if target in in_degree:
            in_degree[target] += 1

    queue = [key for key, degree in in_degree.items() if degree == 0]
    ordered: list[str] = []
    while queue:
        node = queue.pop(0)
        ordered.append(node)
        for source, target in graph.edges:
            if source == node and target in in_degree:
                in_degree[target] -= 1
                if in_degree[target] == 0:
                    queue.append(target)
    if len(ordered) != len(graph.nodes):
        raise AkidaConversionError(
            "The NIR graph contains a cycle; Akida requires a feed-forward chain."
        )
    return ordered


def _input_features(node: nir.Input) -> int:
    shape = (
        list(node.input_type["input"]) if getattr(node, "input_type", None) else list(node.shape)
    )
    if len(shape) != 1:
        raise AkidaConversionError(
            f"Only 1-D inputs are supported by this converter; got shape {shape}."
        )
    return int(shape[0])


def _neuron_threshold(node: Any, units: int) -> np.ndarray[Any, Any]:
    """Per-unit firing threshold in float units, broadcast to `units`."""
    raw = getattr(node, "v_threshold", None)
    if raw is None:
        return np.ones(units, dtype=np.float64)
    return np.broadcast_to(np.asarray(raw, dtype=np.float64), (units,)).copy()


class _PendingDense:
    """A weight node waiting for the neuron node that consumes it."""

    def __init__(self, name: str, weight: np.ndarray[Any, Any], bias: np.ndarray[Any, Any] | None):
        self.name = name
        self.weight = np.asarray(weight, dtype=np.float64)
        self.bias = None if bias is None else np.asarray(bias, dtype=np.float64)


def _conv_output_spatial(
    input_hw: tuple[int, int],
    kernel_size: tuple[int, int],
    stride: tuple[int, int],
    padding: str,
) -> tuple[int, int]:
    """Compute a Conv2d's output spatial shape from its own recorded params.

    Uses the standard TensorFlow/Akida-style `same`/`valid` formulas. This is
    deliberately self-contained to one node's own fields (the CNL grammar
    requires `input_shape` on every Conv2d, not just the first -- see
    `grammar_tables.py`'s `"Conv2d"` table, `has_default=False`) rather than
    relying on `NIRGraph.infer_types()` across the whole graph: NIR's
    spiking-neuron nodes carry per-channel parameters, not per-spatial-
    position ones, so `infer_types()` raises a false-positive type mismatch
    on a perfectly valid Conv2d -> LIF edge (measured while verifying this
    against the real SDK).
    """
    in_h, in_w = input_hw
    kh, kw = kernel_size
    sh, sw = stride
    if padding == "valid":
        return ((in_h - kh) // sh + 1, (in_w - kw) // sw + 1)
    return (-(-in_h // sh), -(-in_w // sw))  # "same": ceil(in / stride)


class _PendingConv:
    """A Conv2d node waiting for the pooling and/or neuron node that fuses with it.

    Akida's Convolutional/InputConvolutional layers fuse conv + pooling +
    activation into one object -- there is no separate pooling layer to add,
    so a following AvgPool2d has to be folded into this instead of being
    emitted on its own (same reason `_PendingDense` exists for Affine).
    `groups > 1` is rejected before this is ever constructed (see
    `nir_to_akida`'s `nir.Conv2d` branch) -- `self.groups` is always 1.
    """

    def __init__(
        self,
        name: str,
        weight: np.ndarray[Any, Any],
        bias: np.ndarray[Any, Any] | None,
        stride: tuple[int, int],
        padding: Any,
        groups: int,
        input_shape: tuple[int, int] | None,
    ):
        self.name = name
        self.weight = np.asarray(weight, dtype=np.float64)
        self.bias = None if bias is None else np.asarray(bias, dtype=np.float64)
        self.stride = stride
        self.padding = padding
        self.groups = groups
        self.input_shape = input_shape
        self.pool_size: tuple[int, int] | None = None
        self.pool_stride: tuple[int, int] | None = None
        kernel_size = (weight.shape[2], weight.shape[3])
        self.output_shape: tuple[int, int] | None = (
            None
            if input_shape is None
            else _conv_output_spatial(input_shape, kernel_size, stride, padding)
        )


def _resolve_akida_padding(padding: Any, node_name: str) -> str:
    """Map a NIR Conv2d padding value onto Akida's Padding enum.

    Akida only knows `Padding.Valid`/`Padding.Same`/`Padding.SameUpper` -- NIR's
    padding field can also be an arbitrary integer amount per side, which has no
    guaranteed correspondence to either. Rather than replicate NIR's own
    same-padding arithmetic (and risk an off-by-one that silently shifts every
    feature map), only the two forms that map exactly are accepted; anything
    else fails loudly instead of guessing.

    Returns the literal string `"valid"` or `"same"` -- the caller resolves it
    against the real `akida.Padding` enum, since that import is deferred.
    """
    if isinstance(padding, str):
        lowered = padding.lower()
        if lowered in ("valid", "same"):
            return lowered
        raise AkidaConversionError(
            f"Conv2d {node_name!r} has padding {padding!r}, which Akida cannot "
            "represent (only 'valid' or 'same' padding is supported)."
        )
    values = tuple(np.asarray(padding).flatten().tolist())
    if all(v == 0 for v in values):
        return "valid"
    raise AkidaConversionError(
        f"Conv2d {node_name!r} has explicit numeric padding {values}, which "
        "Akida cannot represent -- only zero padding ('valid') or 'same' "
        "padding are supported. Use padding='same' or padding=0 in the "
        "network definition instead."
    )


def _conv_weight_layout(weight: np.ndarray[Any, Any]) -> np.ndarray[Any, Any]:
    """Reorder a NIR Conv2d weight `(C_out, C_in, kH, kW)` for the Akida SDK.

    Akida wants channel-last `(kH, kW, C_in, C_out)`, confirmed against a real
    `akida.Convolutional`/`InputConvolutional` instance's
    `layer.variables["weights"].shape` (see module docstring).
    """
    return np.transpose(weight, (2, 3, 1, 0))


def _build_conv_layer(
    akida: Any,
    model: Any,
    pending: _PendingConv,
    *,
    key: str,
    weight_bits: int,
    act_bits: int,
    with_activation: bool,
    is_first_layer: bool,
) -> tuple[Any, int, float]:
    """Build, add, and load weights for a fused Akida conv layer.

    Chooses InputConvolutional/Convolutional the same way `_PendingDense`'s
    branch chooses FullyConnected -- one call site, one place the
    weight/threshold-loading logic lives. `pending.groups` is always 1 here;
    `groups > 1` is rejected earlier in `nir_to_akida`'s `nir.Conv2d` branch
    (see the comment there -- Akida's SeparableConvolutional is a
    depthwise+pointwise decomposition, not a grouped conv, so there's no
    single-layer target for it). Returns the built layer, its output channel
    count (needed by the caller for threshold shaping), and the weight
    quantization scale.

    Akida's ``PoolType.Average`` is always global -- confirmed against the
    real SDK (see module docstring), it rejects any explicit `pool_size`, so
    a fused AvgPool2d always maps to `pool_size=(-1, -1)` here. Whether the
    NIR graph's AvgPool2d was actually a valid global pool (kernel covering
    the conv's whole output extent) is checked earlier, in `nir_to_akida`'s
    `nir.AvgPool2d` branch, via `pending.output_shape` -- not here.
    """
    filters, in_channels, kernel_h, kernel_w = pending.weight.shape
    kernel_size = (kernel_h, kernel_w)
    pool_type = akida.PoolType.NoPooling if pending.pool_size is None else akida.PoolType.Average
    padding = akida.Padding.Valid if pending.padding == "valid" else akida.Padding.Same

    if is_first_layer:
        if pending.input_shape is None:
            raise AkidaConversionError(
                f"Conv2d {key!r} is the first layer but carries no input_shape; "
                "InputConvolutional needs the spatial input height/width."
            )
        layer = akida.InputConvolutional(
            input_shape=(*pending.input_shape, in_channels),
            kernel_size=kernel_size,
            filters=filters,
            name=key,
            padding=padding,
            kernel_stride=pending.stride,
            weights_bits=weight_bits,
            pool_size=(-1, -1),
            pool_type=pool_type,
            pool_stride=(-1, -1),
            activation=with_activation,
            act_bits=act_bits,
        )
    else:
        layer = akida.Convolutional(
            kernel_size=kernel_size,
            filters=filters,
            name=key,
            padding=padding,
            kernel_stride=pending.stride,
            weights_bits=weight_bits,
            pool_size=(-1, -1),
            pool_type=pool_type,
            pool_stride=(-1, -1),
            activation=with_activation,
            act_bits=act_bits,
        )

    model.add(layer)
    quantized, weight_scale = quantize_weights(pending.weight, bits=weight_bits)
    layer.variables["weights"] = _conv_weight_layout(quantized).astype(np.int8)
    return layer, filters, weight_scale


def nir_to_akida(
    graph: nir.NIRGraph,
    weight_bits: int = 4,
    *,
    input_bits: int = 4,
    act_bits: int = 4,
    input_scale: float = 1.0,
    act_steps: dict[str, np.ndarray[Any, Any]] | None = None,
    activation_on_last: bool = True,
) -> Any:
    """Build an ``akida.Model`` from a NIR graph, carrying its trained weights.

    `input_scale` is the factor the caller used to quantize its inputs (a float
    input ``x`` becomes ``round(x * input_scale)``). Thresholds are expressed in
    the same quantized potential units as the weights, so this has to be known
    to place them correctly; the caller owns input quantization, so it owns
    this number too.

    `act_steps` maps a neuron node's name to its per-unit activation step. Pass
    the output of `calibrate_act_steps`; the default of 1.0 saturates on any
    realistically sized layer.

    `activation_on_last` exists because ``predict()`` -- the only way to read
    raw potentials -- requires the final layer to have activation disabled.
    """
    akida = _require_akida()
    act_steps = act_steps or {}
    max_act = (2**act_bits) - 1

    ordered = _topological_sort(graph)
    neuron_keys = [
        key for key in ordered if isinstance(graph.nodes[key], nir.IF | nir.LIF | nir.CubaLIF)
    ]
    if not neuron_keys:
        raise AkidaConversionError("The graph has no spiking layers; nothing to build on Akida.")
    last_neuron = neuron_keys[-1]

    successors: dict[str, list[str]] = {}
    for source, target in graph.edges:
        successors.setdefault(source, []).append(target)

    model = akida.Model()
    pending: _PendingDense | _PendingConv | None = None
    built_any = False

    for key in ordered:
        node = graph.nodes[key]

        if isinstance(node, nir.Input):
            next_keys = successors.get(key, [])
            feeds_conv = len(next_keys) == 1 and isinstance(graph.nodes[next_keys[0]], nir.Conv2d)
            if feeds_conv:
                # InputConvolutional fuses the input layer into the first conv
                # layer -- nothing to emit here, the Conv2d branch below builds
                # it once it reaches the neuron node that follows.
                continue
            features = _input_features(node)
            model.add(
                akida.InputData(
                    input_shape=(1, 1, features),
                    input_bits=input_bits,
                    name=key,
                )
            )

        elif isinstance(node, nir.Affine | nir.Linear):
            bias = getattr(node, "bias", None)
            pending = _PendingDense(key, node.weight, bias)

        elif isinstance(node, nir.Conv2d):
            if int(node.groups) > 1:
                # Confirmed against the real SDK (module docstring):
                # Akida's SeparableConvolutional is a depthwise+pointwise
                # decomposition (two weight tensors, `weights` shaped
                # (kH, kW, C_in, 1) and `weights_pw` shaped (1, 1, C_in,
                # C_out)) -- not a single grouped convolution. A NIR Conv2d
                # with groups>1 is one grouped-conv weight tensor, which has
                # no direct Akida equivalent; mapping it onto
                # SeparableConvolutional would silently leave `weights_pw`
                # uninitialized rather than fail. Express depthwise+pointwise
                # explicitly as two separate groups=1 Conv2d nodes instead.
                raise AkidaConversionError(
                    f"Conv2d {key!r} has groups={node.groups}, which Akida "
                    "cannot represent as a single layer -- express a "
                    "depthwise-separable convolution as two groups=1 Conv2d "
                    "nodes (depthwise kxk, then pointwise 1x1) instead."
                )
            padding = _resolve_akida_padding(node.padding, key)
            stride = tuple(np.asarray(node.stride).flatten().tolist()[:2])
            input_shape = getattr(node, "input_shape", None)
            input_hw: tuple[int, int] | None = None
            if input_shape is not None:
                in_h, in_w = (int(v) for v in input_shape)
                input_hw = (in_h, in_w)
            pending = _PendingConv(
                key,
                node.weight,
                getattr(node, "bias", None),
                stride=stride,
                padding=padding,
                groups=int(node.groups),
                input_shape=input_hw,
            )

        elif isinstance(node, nir.SumPool2d):
            raise AkidaConversionError(
                f"SumPool2d {key!r} has no Akida equivalent -- only average "
                "pooling is supported. Use AvgPool2d instead."
            )

        elif isinstance(node, nir.AvgPool2d):
            if not isinstance(pending, _PendingConv):
                raise AkidaConversionError(
                    f"AvgPool2d {key!r} does not directly follow a Conv2d layer; "
                    "Akida fuses pooling into the preceding convolution layer, "
                    "it cannot stand alone."
                )
            # Akida's average pooling is always global -- confirmed against
            # the real SDK (module docstring): it rejects any explicit
            # pool_size and always collapses the whole spatial extent to
            # 1x1. Only accept this AvgPool2d if its kernel truly covers the
            # conv's own output extent (`_conv_output_spatial`, computed from
            # that Conv2d node's own recorded input_shape/stride/padding).
            kernel_size = tuple(np.asarray(node.kernel_size).flatten().tolist()[:2])
            input_spatial = pending.output_shape
            if input_spatial is None:
                raise AkidaConversionError(
                    f"AvgPool2d {key!r} follows a Conv2d with no input_shape "
                    "recorded, so its output extent can't be checked; Akida's "
                    "average pooling is only valid as a global pool over the "
                    "conv's exact output extent."
                )
            if kernel_size != input_spatial:
                raise AkidaConversionError(
                    f"AvgPool2d {key!r} has kernel_size {kernel_size}, but "
                    "Akida's average pooling is always global -- it can only "
                    f"pool the full {input_spatial} extent to 1x1, not a "
                    f"smaller window. Use kernel_size={input_spatial} for a "
                    "global average pool, or remove the AvgPool2d (Akida has "
                    "no windowed/strided average pooling)."
                )
            pending.pool_size = kernel_size
            pending.pool_stride = tuple(np.asarray(node.stride).flatten().tolist()[:2])

        elif isinstance(node, nir.Flatten):
            # A 1-D chain is already flat; Akida flattens implicitly between
            # Conv and Dense, so there is nothing to emit.
            continue

        elif isinstance(node, nir.IF | nir.LIF | nir.CubaLIF):
            if pending is None:
                raise AkidaConversionError(
                    f"Spiking layer {key!r} has no weight layer before it; "
                    "Akida fuses weights and neurons into one layer."
                )
            with_activation = activation_on_last or key != last_neuron

            if isinstance(pending, _PendingConv):
                layer, out_features, weight_scale = _build_conv_layer(
                    akida,
                    model,
                    pending,
                    key=key,
                    weight_bits=weight_bits,
                    act_bits=act_bits,
                    with_activation=with_activation,
                    is_first_layer=len(model.layers) == 0,
                )
            else:
                out_features, in_features = pending.weight.shape
                quantized, weight_scale = quantize_weights(pending.weight, bits=weight_bits)

                layer = akida.FullyConnected(
                    units=out_features,
                    name=key,
                    weights_bits=weight_bits,
                    activation=with_activation,
                    act_bits=act_bits,
                )
                model.add(layer)

                # NIR stores (out, in); the SDK wants (1, 1, in, out).
                layer.variables["weights"] = quantized.T.reshape(
                    1, 1, in_features, out_features
                ).astype(np.int8)

            if with_activation:
                # Potentials are in quantized units, so the threshold must be
                # too. A bias is an offset on the same pre-activation sum, so
                # subtracting it from the threshold is exact rather than an
                # approximation -- and it is the only way to keep it, since
                # neither FullyConnected nor Convolutional exposes a bias
                # variable.
                threshold = _neuron_threshold(node, out_features)
                if pending.bias is not None:
                    threshold = threshold - pending.bias
                scaled = threshold * input_scale * weight_scale
                layer.variables["threshold"] = np.round(scaled).astype(np.int32)

                step = act_steps.get(key)
                if step is None:
                    step = np.ones(out_features, dtype=np.float32)
                layer.variables["act_step"] = np.broadcast_to(
                    np.asarray(step, dtype=np.float32), (out_features,)
                ).copy()

            built_any = True
            pending = None

        elif isinstance(node, nir.Output):
            continue

        else:
            raise AkidaConversionError(
                f"Node {key!r} of type {type(node).__name__} is not supported by "
                "this converter. Akida takes a feed-forward chain of "
                "Linear/Affine or Conv2d/AvgPool2d, followed by IF/LIF."
            )

    if not built_any:
        raise AkidaConversionError("No Akida layers were produced from this graph.")
    if max_act <= 0:  # pragma: no cover - guarded by act_bits validation upstream
        raise AkidaConversionError(f"Invalid act_bits {act_bits}.")
    return model


def calibrate_act_steps(
    graph: nir.NIRGraph,
    samples: np.ndarray[Any, Any],
    *,
    weight_bits: int = 4,
    input_bits: int = 4,
    act_bits: int = 4,
    input_scale: float = 1.0,
    percentile: float = 99.0,
) -> dict[str, np.ndarray[Any, Any]]:
    """Choose a per-layer activation step from real data.

    Without this every layer keeps ``act_step = 1`` and saturates at
    ``2**act_bits - 1`` on essentially every sample, which destroys accuracy in
    a way that looks like a conversion bug rather than a scaling one.

    Works the only way the SDK allows: build the model truncated after each
    neuron layer with that layer's activation disabled, read the raw potentials
    with ``predict()``, and pick a step that maps their high percentile onto
    the top of the output range. Layers already calibrated keep their step, so
    each measurement sees the same activations the final model will.
    """
    ordered = _topological_sort(graph)
    neuron_keys = [
        key for key in ordered if isinstance(graph.nodes[key], nir.IF | nir.LIF | nir.CubaLIF)
    ]
    max_act = (2**act_bits) - 1
    steps: dict[str, np.ndarray[Any, Any]] = {}

    for index, key in enumerate(neuron_keys):
        truncated = _truncate_after(graph, key)
        model = nir_to_akida(
            truncated,
            weight_bits=weight_bits,
            input_bits=input_bits,
            act_bits=act_bits,
            input_scale=input_scale,
            act_steps=steps,
            activation_on_last=False,
        )
        potentials = np.asarray(model.predict(samples), dtype=np.float64)
        flat = potentials.reshape(-1, potentials.shape[-1])
        high = np.percentile(np.maximum(flat, 0.0), percentile, axis=0)
        # A layer that never fires would give step 0; keep it at 1 so the model
        # stays buildable and the dead layer is visible in the accuracy instead.
        step = np.where(high > 0, high / max_act, 1.0)
        steps[key] = np.maximum(step, 1e-6).astype(np.float32)
        del index

    return steps


def _truncate_after(graph: nir.NIRGraph, last_key: str) -> nir.NIRGraph:
    """Return a copy of `graph` keeping only nodes up to and including `last_key`."""
    ordered = _topological_sort(graph)
    cut = ordered.index(last_key)
    keep = set(ordered[: cut + 1])
    nodes = {key: graph.nodes[key] for key in ordered[: cut + 1]}
    edges = [(a, b) for a, b in graph.edges if a in keep and b in keep]
    return nir.NIRGraph(nodes=nodes, edges=edges, type_check=False)


def quantize_inputs(values: np.ndarray[Any, Any], *, input_bits: int = 4) -> tuple[np.ndarray[Any, Any], float]:
    """Quantize float inputs to the uint8 (batch, 1, 1, features) form Akida wants.

    Returns the array and the scale used, which `nir_to_akida` needs in order to
    express thresholds in the same units.
    """
    flat = np.asarray(values, dtype=np.float64).reshape(len(values), -1)
    max_val = float(np.max(np.abs(flat))) if flat.size else 0.0
    q_max = (2**input_bits) - 1
    scale = (q_max / max_val) if max_val > 0 else 1.0
    quantized = np.clip(np.round(flat * scale), 0, q_max).astype(np.uint8)
    return quantized.reshape(len(values), 1, 1, flat.shape[1]), scale


def akida_to_nir(model: Any) -> nir.NIRGraph:
    """Export an Akida model back into a NIR graph.

    Splits each fused Akida layer back into an Affine -> IF pair. Weights are
    dequantized with the layer's own scale unavailable, so this is lossy and
    intended for inspection rather than round-tripping a trained model.
    """
    akida = _require_akida()
    nodes: dict[str, Any] = {}
    edges: list[tuple[str, str]] = []
    previous: str | None = None

    for layer in model.layers:
        # Once added to a Model, layers come back as generic `akida.core.Layer`
        # wrappers -- `isinstance(layer, akida.FullyConnected)` is False for
        # every layer in a built model, so it must be discriminated by
        # parameters.layer_type instead.
        layer_type = layer.parameters.layer_type

        if layer_type == akida.LayerType.InputData:
            nodes[layer.name] = nir.Input(input_type={"input": np.array(layer.output_dims)})
            previous = layer.name

        elif layer_type == akida.LayerType.FullyConnected:
            weight_name = f"{layer.name}_affine"
            neuron_name = f"{layer.name}_if"
            weights = np.asarray(layer.variables["weights"])
            # (1, 1, in, out) -> (out, in)
            matrix = weights.reshape(weights.shape[2], weights.shape[3]).T.astype(np.float32)
            nodes[weight_name] = nir.Affine(
                weight=matrix, bias=np.zeros(matrix.shape[0], dtype=np.float32)
            )
            nodes[neuron_name] = nir.IF(
                r=np.ones(matrix.shape[0], dtype=np.float32),
                v_threshold=np.ones(matrix.shape[0], dtype=np.float32),
            )
            if previous is not None:
                edges.append((previous, weight_name))
            edges.append((weight_name, neuron_name))
            previous = neuron_name

        elif layer_type in (
            akida.LayerType.InputConvolutional,
            akida.LayerType.Convolutional,
            akida.LayerType.SeparableConvolutional,
        ):
            # Not implemented: reversing `_conv_weight_layout` needs the same
            # weight-layout assumption `nir_to_akida` makes going the other
            # way, and that assumption is unverified (see module docstring).
            # Silently skipping the layer would drop it from the reconstructed
            # graph with no sign anything was lost -- fail loudly instead.
            raise AkidaConversionError(
                f"Conv layer {layer.name!r} ({layer_type}) cannot be round-tripped "
                "back to NIR yet -- akida_to_nir only reconstructs InputData and "
                "FullyConnected layers today."
            )

    if previous is not None:
        nodes["output"] = nir.Output(output_type={"output": np.array(model.layers[-1].output_dims)})
        edges.append((previous, "output"))

    return nir.NIRGraph(nodes=nodes, edges=edges, type_check=False)
