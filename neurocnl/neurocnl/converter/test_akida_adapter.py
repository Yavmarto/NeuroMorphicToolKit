"""Tests for the NIR -> Akida converter.

These skip wherever the Akida SDK is absent, which is most environments. That
is exactly how the previous revision of both the adapter and this file stayed
broken for so long: they were written against an API that does not exist
(`akida.InputLayer`, `FullyConnected(weights=...)`, `layer.weights`), and
nothing ever executed them to find out. Run them in the Jupyter image, which
has the SDK.
"""

from pathlib import Path
from typing import Any

import pytest

pytest.importorskip("akida")
import akida
import nir
import numpy as np

from neurocnl.converter.akida_adapter import (
    AkidaConversionError,
    calibrate_act_steps,
    nir_to_akida,
    quantize_inputs,
    quantize_weights,
)
from neurocnl.nir_cnl import NIR_CNL_Parser, NIR_Compiler

_TEMPLATES_DIR = Path(__file__).resolve().parents[2] / "backend" / "app" / "templates"


def _dense_graph(
    in_features: int = 10, out_features: int = 20, bias: np.ndarray[Any, Any] | None = None
) -> tuple[nir.NIRGraph, np.ndarray[Any, Any]]:
    weight = np.random.default_rng(0).normal(0, 0.3, (out_features, in_features))
    nodes = {
        "input": nir.Input(input_type={"input": np.array([in_features])}),
        "linear": nir.Affine(
            weight=weight.astype(np.float32),
            bias=(np.zeros(out_features) if bias is None else bias).astype(np.float32),
        ),
        "lif": nir.LIF(
            tau=np.full(out_features, 0.02),
            v_threshold=np.ones(out_features),
            v_leak=np.zeros(out_features),
            r=np.ones(out_features),
        ),
        "output": nir.Output(output_type={"output": np.array([out_features])}),
    }
    edges = [("input", "linear"), ("linear", "lif"), ("lif", "output")]
    return nir.NIRGraph(nodes=nodes, edges=edges, type_check=False), weight


def test_quantize_weights_respects_the_declared_bit_width() -> None:
    """int8 is the storage type at every width; the values must still fit.

    The previous implementation always cast to int8 regardless of `bits`, so a
    4-bit layer was handed values up to +/-127.
    """
    weights = np.linspace(-1.0, 1.0, 64).reshape(8, 8)

    q4, scale4 = quantize_weights(weights, bits=4)
    assert q4.dtype == np.int8
    assert q4.min() >= -7 and q4.max() <= 7
    assert scale4 == pytest.approx(7 / np.max(np.abs(weights)))

    q2, _ = quantize_weights(weights, bits=2)
    assert q2.min() >= -1 and q2.max() <= 1

    with pytest.raises(AkidaConversionError, match="bit width"):
        quantize_weights(weights, bits=3)


def test_all_zero_weights_do_not_divide_by_zero() -> None:
    q, scale = quantize_weights(np.zeros((4, 4)), bits=4)
    assert scale == 1.0
    assert not q.any()


def test_nir_to_akida_builds_a_dense_chain_with_the_trained_weights() -> None:
    graph, weight = _dense_graph(10, 20)

    model = nir_to_akida(graph, weight_bits=4)

    assert isinstance(model, akida.Model)
    assert len(model.layers) == 2  # InputData + fused FullyConnected
    layer = model.layers[1]
    # A built model hands back generic akida.core.Layer wrappers, so
    # isinstance(layer, akida.FullyConnected) is False even here.
    assert layer.parameters.layer_type == akida.LayerType.FullyConnected

    # The SDK stores (1, 1, in, out); NIR holds (out, in).
    stored = np.asarray(layer.variables["weights"])
    assert stored.shape == (1, 1, 10, 20)
    expected, _ = quantize_weights(weight, bits=4)
    np.testing.assert_array_equal(stored, expected.T.reshape(1, 1, 10, 20))


def test_bias_is_folded_into_the_threshold() -> None:
    """FullyConnected has no bias variable, so a dropped bias is silent damage.

    `threshold` is a plain subtracted offset on the same pre-activation sum, so
    folding the bias into it is exact rather than an approximation.
    """
    out_features = 6
    bias = np.linspace(-0.5, 0.5, out_features)
    graph, _ = _dense_graph(4, out_features, bias=bias)

    with_bias = nir_to_akida(graph, weight_bits=4, input_scale=2.0)
    zero_bias_graph, _ = _dense_graph(4, out_features, bias=np.zeros(out_features))
    without_bias = nir_to_akida(zero_bias_graph, weight_bits=4, input_scale=2.0)

    t_with = np.asarray(with_bias.layers[1].variables["threshold"])
    t_without = np.asarray(without_bias.layers[1].variables["threshold"])
    # Larger bias => lower threshold, monotonically.
    assert np.all(np.diff(t_with - t_without) <= 0)
    assert not np.array_equal(t_with, t_without)


def test_calibration_prevents_activation_saturation() -> None:
    """The whole point of act_step: at 1 every unit pins to the top of the range."""
    graph, _ = _dense_graph(16, 12)
    rng = np.random.default_rng(1)
    samples, scale = quantize_inputs(np.abs(rng.normal(0, 1, (64, 16))), input_bits=4)

    uncalibrated = nir_to_akida(graph, weight_bits=4, input_scale=scale)
    steps = calibrate_act_steps(graph, samples, weight_bits=4, input_scale=scale)
    calibrated = nir_to_akida(graph, weight_bits=4, input_scale=scale, act_steps=steps)

    saturated_before = (np.asarray(uncalibrated.forward(samples)) == 15).mean()
    saturated_after = (np.asarray(calibrated.forward(samples)) == 15).mean()
    assert saturated_after < saturated_before
    assert saturated_after < 0.25


def test_quantize_inputs_produces_the_shape_the_sdk_requires() -> None:
    values = np.abs(np.random.default_rng(2).normal(0, 1, (8, 5)))
    quantized, scale = quantize_inputs(values, input_bits=4)

    assert quantized.shape == (8, 1, 1, 5)
    assert quantized.dtype == np.uint8
    assert quantized.max() <= 15
    assert scale > 0


def test_a_spiking_layer_without_weights_is_rejected() -> None:
    nodes = {
        "input": nir.Input(input_type={"input": np.array([4])}),
        "lif": nir.LIF(
            tau=np.full(4, 0.02),
            v_threshold=np.ones(4),
            v_leak=np.zeros(4),
            r=np.ones(4),
        ),
    }
    graph = nir.NIRGraph(nodes=nodes, edges=[("input", "lif")], type_check=False)

    with pytest.raises(AkidaConversionError, match="no weight layer"):
        nir_to_akida(graph)


def _conv_graph(
    in_hw: tuple[int, int] = (8, 8),
    in_channels: int = 1,
    filters: int = 4,
    kernel: tuple[int, int] = (3, 3),
    out_classes: int = 5,
    padding: Any = 0,
    global_pool: bool = False,
) -> nir.NIRGraph:
    rng = np.random.default_rng(7)
    kh, kw = kernel
    conv_weight = rng.normal(0, 0.3, (filters, in_channels, kh, kw)).astype(np.float32)
    out_h, out_w = in_hw[0] - kh + 1, in_hw[1] - kw + 1  # valid padding
    # A global AvgPool2d collapses the spatial extent to 1x1 before the dense
    # tail -- confirmed against the real SDK (akida_adapter.py's module
    # docstring). The dense layer's input feature count has to match that,
    # not the pre-pool conv output size.
    pooled_h, pooled_w = (1, 1) if global_pool else (out_h, out_w)
    flat = filters * pooled_h * pooled_w
    dense_weight = rng.normal(0, 0.3, (out_classes, flat)).astype(np.float32)
    nodes = {
        "input": nir.Input(input_type={"input": np.array([in_channels, *in_hw])}),
        "conv": nir.Conv2d(
            input_shape=in_hw,
            weight=conv_weight,
            bias=np.zeros(filters, dtype=np.float32),
            stride=1,
            padding=padding,
            dilation=1,
            groups=1,
        ),
        "conv_lif": nir.LIF(
            tau=np.full(filters, 0.02),
            v_threshold=np.ones(filters),
            v_leak=np.zeros(filters),
            r=np.ones(filters),
        ),
        "flatten": nir.Flatten(input_type={"input": np.array([filters, pooled_h, pooled_w])}),
        "dense": nir.Affine(weight=dense_weight, bias=np.zeros(out_classes, dtype=np.float32)),
        "classes_lif": nir.LIF(
            tau=np.full(out_classes, 0.02),
            v_threshold=np.ones(out_classes),
            v_leak=np.zeros(out_classes),
            r=np.ones(out_classes),
        ),
        "output": nir.Output(output_type={"output": np.array([out_classes])}),
    }
    edges = [
        ("input", "conv"),
        ("conv", "conv_lif"),
        ("conv_lif", "flatten"),
        ("flatten", "dense"),
        ("dense", "classes_lif"),
        ("classes_lif", "output"),
    ]
    if global_pool:
        nodes["pool"] = nir.AvgPool2d(
            kernel_size=np.array([out_h, out_w]),
            stride=np.array([out_h, out_w]),
            padding=np.array([0, 0]),
        )
        edges = [
            ("input", "conv"),
            ("conv", "pool"),
            ("pool", "conv_lif"),
            ("conv_lif", "flatten"),
            ("flatten", "dense"),
            ("dense", "classes_lif"),
            ("classes_lif", "output"),
        ]
    return nir.NIRGraph(nodes=nodes, edges=edges, type_check=False)


def test_nir_to_akida_builds_an_input_convolutional_layer() -> None:
    graph = _conv_graph()

    model = nir_to_akida(graph, weight_bits=4)

    # InputConvolutional (fused with the Input node) + Convolutional's LIF
    # fusion + the dense tail's FullyConnected -- no standalone InputData.
    assert len(model.layers) == 2
    conv_layer = model.layers[0]
    assert conv_layer.parameters.layer_type == akida.LayerType.InputConvolutional
    dense_layer = model.layers[1]
    assert dense_layer.parameters.layer_type == akida.LayerType.FullyConnected


def test_avgpool2d_fuses_into_the_preceding_conv_layer_not_a_new_one() -> None:
    # Akida's average pooling is always global (confirmed against the real
    # SDK -- see akida_adapter.py's module docstring): it only accepts an
    # AvgPool2d whose kernel covers the conv's *entire* output extent. The
    # default `_conv_graph()` is an 8x8 input, 3x3 kernel, valid padding, so
    # the conv's output is 6x6 -- `global_pool=True` sizes the pool kernel
    # (and the dense tail's input features) to match that exactly.
    graph = _conv_graph(global_pool=True)

    model = nir_to_akida(graph, weight_bits=4)

    # Still exactly one conv-family layer, not conv + a separate pool layer.
    assert len(model.layers) == 2
    assert model.layers[0].parameters.layer_type == akida.LayerType.InputConvolutional
    assert tuple(model.layers[0].output_dims[:2]) == (1, 1)


def test_avgpool2d_narrower_than_the_full_extent_is_rejected() -> None:
    # Akida's average pooling is always global -- there is no windowed or
    # strided average pooling on the hardware. A kernel_size smaller than the
    # conv's full 6x6 output (see the test above) has no Akida equivalent and
    # must be rejected rather than silently widened to global.
    graph = _conv_graph()
    graph.nodes["pool"] = nir.AvgPool2d(
        kernel_size=np.array([2, 2]), stride=np.array([2, 2]), padding=np.array([0, 0])
    )
    graph.edges = [
        ("input", "conv"),
        ("conv", "pool"),
        ("pool", "conv_lif"),
        ("conv_lif", "flatten"),
        ("flatten", "dense"),
        ("dense", "classes_lif"),
        ("classes_lif", "output"),
    ]

    with pytest.raises(AkidaConversionError, match="always global"):
        nir_to_akida(graph)


def test_grouped_conv2d_has_no_akida_equivalent() -> None:
    # Akida's SeparableConvolutional turned out to be a depthwise+pointwise
    # *decomposition* (two weight variables), not a single grouped
    # convolution -- confirmed against the real SDK. A NIR Conv2d with
    # groups > 1 carries one grouped-conv weight tensor that doesn't map onto
    # that shape, so it must be rejected rather than silently mis-mapped.
    graph = _conv_graph(in_channels=2, filters=4)
    graph.nodes["conv"] = nir.Conv2d(
        input_shape=(8, 8),
        weight=np.zeros((4, 1, 3, 3), dtype=np.float32),
        bias=np.zeros(4, dtype=np.float32),
        stride=1,
        padding=0,
        dilation=1,
        groups=2,
    )

    with pytest.raises(AkidaConversionError, match="groups"):
        nir_to_akida(graph)


def test_sumpool2d_is_rejected_not_silently_approximated() -> None:
    graph = _conv_graph()
    graph.nodes["pool"] = nir.SumPool2d(
        kernel_size=np.array([2, 2]), stride=np.array([2, 2]), padding=np.array([0, 0])
    )
    graph.edges = [
        ("input", "conv"),
        ("conv", "pool"),
        ("pool", "conv_lif"),
        ("conv_lif", "flatten"),
        ("flatten", "dense"),
        ("dense", "classes_lif"),
        ("classes_lif", "output"),
    ]

    with pytest.raises(AkidaConversionError, match="SumPool2d"):
        nir_to_akida(graph)


def test_conv2d_with_unrepresentable_padding_is_rejected() -> None:
    graph = _conv_graph(padding=2)  # not 0 ("valid") and not "same"

    with pytest.raises(AkidaConversionError, match="padding"):
        nir_to_akida(graph)


def test_unsupported_node_types_are_named_rather_than_ignored() -> None:
    graph, _ = _dense_graph(4, 4)
    graph.nodes["conv"] = nir.Conv2d(
        input_shape=(8, 8),
        weight=np.zeros((2, 1, 3, 3), dtype=np.float32),
        bias=np.zeros(2, dtype=np.float32),
        stride=1,
        padding=0,
        dilation=1,
        groups=1,
    )
    graph.edges.append(("lif", "conv"))

    with pytest.raises(AkidaConversionError, match="Conv2d"):
        nir_to_akida(graph)


def test_converted_model_runs_in_software_without_a_device() -> None:
    """No card required -- which is what makes this stage verifiable at all."""
    graph, _ = _dense_graph(8, 4)
    samples, scale = quantize_inputs(
        np.abs(np.random.default_rng(3).normal(0, 1, (10, 8))), input_bits=4
    )
    steps = calibrate_act_steps(graph, samples, weight_bits=4, input_scale=scale)
    model = nir_to_akida(graph, weight_bits=4, input_scale=scale, act_steps=steps)

    output = np.asarray(model.forward(samples))

    assert output.shape == (10, 1, 1, 4)
    assert output.dtype == np.uint8


def test_saved_model_can_be_reopened_by_this_sdk(tmp_path: Path) -> None:
    """Guards the save -> reopen round trip the deploy path depends on.

    The Akida host receives a bundle containing a `.fbz` written by
    `akida.Model.save()` in the Jupyter kernel, and reopens it with
    `akida.Model(path)`. Nothing asserted that this worked: the host's own tests
    use a `b"fake-fbz-payload"` stub, and every test above stops at an in-memory
    model. A `.fbz` is a version-gated flatbuffer, so this also fails loudly if
    the writing and reading SDKs ever diverge inside one environment.
    """
    graph, _ = _dense_graph(8, 4)
    samples, scale = quantize_inputs(
        np.abs(np.random.default_rng(4).normal(0, 1, (6, 8))), input_bits=4
    )
    steps = calibrate_act_steps(graph, samples, weight_bits=4, input_scale=scale)
    # activation_on_last=False is the form the host actually serves: `predict()`
    # needs raw potentials, so the round trip has to hold for this shape too.
    model = nir_to_akida(
        graph,
        weight_bits=4,
        input_scale=scale,
        act_steps=steps,
        activation_on_last=False,
    )
    expected = np.asarray(model.predict(samples))

    path = tmp_path / "model.fbz"
    model.save(str(path))
    assert path.stat().st_size > 0

    reloaded = akida.Model(str(path))
    np.testing.assert_allclose(np.asarray(reloaded.predict(samples)), expected)


def test_guide_mnist_cnn_template_is_akida_exportable() -> None:
    """The shipped `mnist_cnn_classifier_akida.cnl` template must actually
    convert -- not a synthetic fixture standing in for it. Parses and
    compiles the real template file through the real CNL pipeline (the same
    one Studio uses), then runs the result through `nir_to_akida`.

    `plan_akida_exportability` (the NetworkIR-based pre-flight contract that
    the SHD/N-TIDIGITS templates use for this check, see
    `test_akida_deployment_contract.py`) can't do this for a conv template --
    `NetworkIR`/`PopulationIR` have no way to represent a Conv2d layer at
    all, only a neuron count. This test is this template's equivalent
    exportability proof, against the real trained-model converter instead.
    """
    text = (_TEMPLATES_DIR / "mnist_cnn_classifier_akida.cnl").read_text()
    records = NIR_CNL_Parser().parse(text)
    graph = NIR_Compiler().compile(records)

    model = nir_to_akida(graph, weight_bits=4)

    assert len(model.layers) == 2
    assert model.layers[0].parameters.layer_type == akida.LayerType.InputConvolutional
    assert model.layers[1].parameters.layer_type == akida.LayerType.FullyConnected
    # The pool must have actually collapsed the spatial extent to 1x1 -- a
    # regression here would mean the template's pool kernel no longer
    # matches the conv's output extent (see the module docstring on why
    # Akida's average pooling can only ever be global).
    assert tuple(model.layers[0].output_dims[:2]) == (1, 1)
