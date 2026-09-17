"""Tests for visualization tools."""

from unittest.mock import patch

import numpy as np
import pytest

from neurocnl.visualization import (
    HAS_MATPLOTLIB,
    _check_matplotlib,
    membrane_traces,
    network_topology,
    spike_raster,
    to_html,
    weight_evolution,
)


class TestSpikeRaster:
    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_returns_figure(self) -> None:
        rng = np.random.default_rng()
        data = rng.choice([0.0, 1.0], size=(100, 10), p=[0.9, 0.1])
        fig = spike_raster(data, dt=0.001)
        assert fig is not None
        assert hasattr(fig, "savefig")

    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_custom_labels(self) -> None:
        rng = np.random.default_rng()
        data = rng.choice([0.0, 1.0], size=(100, 3), p=[0.9, 0.1])
        labels = ["Sensory", "Inter", "Motor"]
        fig = spike_raster(data, dt=0.001, neuron_labels=labels)
        assert fig is not None

    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_empty_spikes(self) -> None:
        data = np.zeros((100, 5))
        fig = spike_raster(data, dt=0.001)
        assert fig is not None


class TestMembraneTraces:
    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_returns_figure(self) -> None:
        rng = np.random.default_rng()
        data = rng.random((100, 10)) * 0.5
        fig = membrane_traces(data, dt=0.001)
        assert fig is not None

    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_select_neurons(self) -> None:
        rng = np.random.default_rng()
        data = rng.random((100, 10)) * 0.5
        fig = membrane_traces(data, dt=0.001, neuron_indices=[0, 5, 9])
        assert fig is not None

    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_single_neuron(self) -> None:
        rng = np.random.default_rng()
        data = rng.random((100, 1)) * 0.5
        fig = membrane_traces(data, dt=0.001)
        assert fig is not None


class TestNetworkTopology:
    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_returns_figure(self) -> None:
        pops = [
            {"label": "sensory", "n_neurons": 50, "type": "excitatory"},
            {"label": "motor", "n_neurons": 50, "type": "excitatory"},
        ]
        conns = [{"source": "sensory", "target": "motor", "weight": 1.0}]
        fig = network_topology(pops, conns)
        assert fig is not None

    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_empty_network(self) -> None:
        fig = network_topology([], [])
        assert fig is not None

    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_inhibitory_connection(self) -> None:
        pops = [
            {"label": "sensory", "n_neurons": 50},
            {"label": "inter", "n_neurons": 30, "type": "inhibitory"},
            {"label": "motor", "n_neurons": 50},
        ]
        conns = [
            {"source": "sensory", "target": "motor", "weight": 1.0},
            {"source": "inter", "target": "motor", "weight": -0.5},
        ]
        fig = network_topology(pops, conns)
        assert fig is not None

    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_learning_rule_connection(self) -> None:
        pops = [
            {"label": "sensory", "n_neurons": 50},
            {"label": "motor", "n_neurons": 50},
        ]
        conns = [
            {
                "source": "sensory",
                "target": "motor",
                "weight": 1.0,
                "learning_rule": "PES",
            }
        ]
        fig = network_topology(pops, conns)
        assert fig is not None


class TestWeightEvolution:
    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_returns_figure(self) -> None:
        rng = np.random.default_rng()
        data = np.cumsum(rng.standard_normal((100, 5)) * 0.01, axis=0)
        fig = weight_evolution(data, dt=0.001)
        assert fig is not None

    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_1d_weights(self) -> None:
        rng = np.random.default_rng()
        data = np.cumsum(rng.standard_normal(100) * 0.01)
        fig = weight_evolution(data, dt=0.001)
        assert fig is not None

    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_custom_labels(self) -> None:
        rng = np.random.default_rng()
        data = np.cumsum(rng.standard_normal((100, 3)) * 0.01, axis=0)
        labels = ["S→M", "S→I", "I→M"]
        fig = weight_evolution(data, dt=0.001, connection_labels=labels)
        assert fig is not None


class TestToHtml:
    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_returns_html_string(self) -> None:
        rng = np.random.default_rng()
        data = rng.choice([0.0, 1.0], size=(100, 10), p=[0.9, 0.1])
        fig = spike_raster(data, dt=0.001)
        html = to_html(fig)
        assert html.startswith('<img src="data:image/png;base64,')
        assert html.endswith('" />')


class TestNoMatplotlibFallback:
    def test_check_matplotlib_raises(self) -> None:
        with (
            patch("neurocnl.visualization.HAS_MATPLOTLIB", False),
            pytest.raises(ImportError) as excinfo,
        ):
            _check_matplotlib()
        assert "matplotlib is required" in str(excinfo.value)

    def test_spike_raster_raises(self) -> None:
        with (
            patch("neurocnl.visualization.HAS_MATPLOTLIB", False),
            pytest.raises(ImportError),
        ):
            spike_raster(np.zeros((10, 10)))

    def test_figure_placeholder(self) -> None:
        from neurocnl.visualization import Figure as PlaceholderFigure

        with patch("neurocnl.visualization.HAS_MATPLOTLIB", False):
            fig = PlaceholderFigure()
            assert fig is not None


class TestVisualizationEdgeCases:
    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_network_topology_minimal(self) -> None:
        # Already covered by empty network, but let's add one with just one pop
        pops = [{"label": "p1", "n_neurons": 10}]
        fig = network_topology(pops, [])
        assert fig is not None

    @pytest.mark.skipif(not HAS_MATPLOTLIB, reason="matplotlib not installed")
    def test_spike_raster_no_times(self) -> None:
        data = np.zeros((0, 5))
        fig = spike_raster(data)
        assert fig is not None
