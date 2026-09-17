"""Visualization tools for spiking neural networks.

Matplotlib-based plotting for debugging and documentation:
- Spike raster plots
- Membrane voltage traces
- Network topology diagrams
- Weight evolution plots (for STDP)

All functions return matplotlib Figure objects and optionally accept
an Axes to plot into (for composing multi-panel figures).
"""

import base64
import io
from typing import Any, cast

import numpy as np

try:
    import matplotlib

    matplotlib.use("Agg")  # Non-interactive backend for server/CI
    import matplotlib.pyplot as plt
    from matplotlib.axes import Axes as Axes
    from matplotlib.figure import Figure as Figure
    from matplotlib.patches import Circle

    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False

    class Figure:  # type: ignore[no-redef]
        """Placeholder for matplotlib Figure when not installed."""

        pass

    class Axes:  # type: ignore[no-redef]
        """Placeholder for matplotlib Axes when not installed."""

        pass

    class Circle:  # type: ignore[no-redef]
        """Placeholder for matplotlib Circle when not installed."""

        pass


def _check_matplotlib() -> None:
    if not HAS_MATPLOTLIB:
        raise ImportError(
            "matplotlib is required for visualization. Install with: pip install neurocnl[viz]"
        )


def spike_raster(
    spike_data: np.ndarray[Any, Any],
    dt: float = 0.001,
    ax: Axes | None = None,
    title: str = "Spike Raster Plot",
    neuron_labels: list[str] | None = None,
) -> Figure:
    """Plot a spike raster showing which neurons fired when.

    Parameters
    ----------
    spike_data : np.ndarray
        2-D array of shape (n_timesteps, n_neurons). Non-zero values indicate spikes.
        This is the format returned by Nengo probes on ensemble neurons.
    dt : float
        Simulation timestep in seconds. Used to convert indices to time axis.
    ax : matplotlib Axes, optional
        Axes to plot into. If None, creates a new figure.
    title : str
        Plot title.
    neuron_labels : list[str], optional
        Labels for each neuron (y-axis). If None, uses "Neuron 0", "Neuron 1", etc.

    Returns
    -------
    matplotlib.figure.Figure
        The figure containing the raster plot.
    """
    _check_matplotlib()

    if ax is None:
        fig, ax = plt.subplots(figsize=(12, 6))
    else:
        fig = cast(Figure, ax.figure)

    n_timesteps, n_neurons = spike_data.shape
    times = np.arange(n_timesteps) * dt

    for neuron_idx in range(n_neurons):
        spike_times = times[spike_data[:, neuron_idx] > 0]
        ax.scatter(
            spike_times,
            np.full_like(spike_times, neuron_idx),
            marker="|",
            s=10,
            c="black",
            linewidths=0.5,
        )

    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Neuron")
    ax.set_title(title)
    ax.set_ylim(-0.5, n_neurons - 0.5)
    ax.set_xlim(0, times[-1] if len(times) > 0 else 1.0)

    if neuron_labels:
        ax.set_yticks(range(min(n_neurons, len(neuron_labels))))
        ax.set_yticklabels(neuron_labels[:n_neurons])

    fig.tight_layout()
    return fig


def membrane_traces(
    voltage_data: np.ndarray[Any, Any],
    dt: float = 0.001,
    neuron_indices: list[int] | None = None,
    ax: Axes | None = None,
    title: str = "Membrane Voltage Traces",
) -> Figure:
    """Plot membrane voltage traces for selected neurons.

    Parameters
    ----------
    voltage_data : np.ndarray
        2-D array of shape (n_timesteps, n_neurons). Voltage values from Nengo
        probe on ensemble neurons with attribute 'voltage'.
    dt : float
        Simulation timestep in seconds.
    neuron_indices : list[int], optional
        Which neurons to plot. If None, plots the first 5 neurons.
    ax : matplotlib Axes, optional
        Axes to plot into.
    title : str
        Plot title.

    Returns
    -------
    matplotlib.figure.Figure
    """
    _check_matplotlib()

    if ax is None:
        fig, ax = plt.subplots(figsize=(12, 4))
    else:
        fig = cast(Figure, ax.figure)

    n_timesteps, n_neurons = voltage_data.shape
    times = np.arange(n_timesteps) * dt

    if neuron_indices is None:
        neuron_indices = list(range(min(5, n_neurons)))

    for idx in neuron_indices:
        if idx < n_neurons:
            ax.plot(times, voltage_data[:, idx], label=f"Neuron {idx}", alpha=0.7)

    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Membrane Voltage")
    ax.set_title(title)
    ax.legend(loc="upper right", fontsize=8)
    fig.tight_layout()
    return fig


def network_topology(
    populations: list[dict[str, Any]],
    connections: list[dict[str, Any]],
    ax: Axes | None = None,
    title: str = "Network Topology",
) -> Figure:
    """Plot a network topology diagram showing populations and connections.

    Parameters
    ----------
    populations : list[dict]
        List of population dicts with keys: 'label' (str), 'n_neurons' (int),
        optional 'type' ('excitatory', 'inhibitory', 'input').
    connections : list[dict]
        List of connection dicts with keys: 'source' (str), 'target' (str),
        optional 'weight' (float), optional 'learning_rule' (str).
    ax : matplotlib Axes, optional
        Axes to plot into.
    title : str
        Plot title.

    Returns
    -------
    matplotlib.figure.Figure
    """
    _check_matplotlib()

    if ax is None:
        fig, ax = plt.subplots(figsize=(10, 8))
    else:
        fig = cast(Figure, ax.figure)

    # Position populations in a circle layout
    n_pops = len(populations)
    if n_pops == 0:
        ax.text(
            0.5, 0.5, "No populations", ha="center", va="center", transform=ax.transAxes
        )
        return fig

    angles = np.linspace(0, 2 * np.pi, n_pops, endpoint=False)
    # Start from top (pi/2) and go clockwise
    angles = np.pi / 2 - angles
    radius = 0.35
    center = (0.5, 0.5)

    positions = {}
    colors = {"excitatory": "#4CAF50", "inhibitory": "#F44336", "input": "#2196F3"}

    for i, pop in enumerate(populations):
        x = center[0] + radius * np.cos(angles[i])
        y = center[1] + radius * np.sin(angles[i])
        positions[pop["label"]] = (x, y)

        pop_type = pop.get("type", "excitatory")
        color = colors.get(pop_type, "#9E9E9E")
        n = pop.get("n_neurons", "?")

        circle = Circle(
            (x, y), 0.06, color=color, alpha=0.7, transform=ax.transAxes, zorder=3
        )
        ax.add_patch(circle)
        ax.text(
            x,
            y,
            f"{pop['label']}\n({n})",
            ha="center",
            va="center",
            fontsize=8,
            fontweight="bold",
            transform=ax.transAxes,
            zorder=4,
        )

    # Draw connections as arrows
    for conn in connections:
        src = conn.get("source", "")
        tgt = conn.get("target", "")
        if src in positions and tgt in positions:
            x1, y1 = positions[src]
            x2, y2 = positions[tgt]

            weight = conn.get("weight", None)
            learning = conn.get("learning_rule", "")
            color = "#F44336" if (weight is not None and weight < 0) else "#333333"
            style = "dashed" if learning else "solid"

            ax.annotate(
                "",
                xy=(x2, y2),
                xytext=(x1, y1),
                arrowprops=dict(arrowstyle="->", color=color, linestyle=style, lw=1.5),
                transform=ax.transAxes,
                zorder=2,
            )

            # Label
            mid_x = (x1 + x2) / 2
            mid_y = (y1 + y2) / 2
            label_parts = []
            if weight is not None:
                label_parts.append(f"w={weight}")
            if learning:
                label_parts.append(learning)
            if label_parts:
                ax.text(
                    mid_x,
                    mid_y + 0.02,
                    ", ".join(label_parts),
                    ha="center",
                    fontsize=7,
                    color=color,
                    transform=ax.transAxes,
                    zorder=5,
                )

    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.set_aspect("equal")
    ax.axis("off")
    ax.set_title(title, fontsize=14, fontweight="bold")
    fig.tight_layout()
    return fig


def weight_evolution(
    weight_data: np.ndarray[Any, Any],
    dt: float = 0.001,
    ax: Axes | None = None,
    title: str = "Weight Evolution",
    connection_labels: list[str] | None = None,
) -> Figure:
    """Plot how connection weights change over time (e.g., during STDP).

    Parameters
    ----------
    weight_data : np.ndarray
        2-D array of shape (n_timesteps, n_connections). Weight values from
        Nengo probe on a connection's learning rule.
    dt : float
        Simulation timestep in seconds.
    ax : matplotlib Axes, optional
        Axes to plot into.
    title : str
        Plot title.
    connection_labels : list[str], optional
        Labels for each connection.

    Returns
    -------
    matplotlib.figure.Figure
    """
    _check_matplotlib()

    if ax is None:
        fig, ax = plt.subplots(figsize=(12, 4))
    else:
        fig = cast(Figure, ax.figure)

    if weight_data.ndim == 1:
        weight_data = weight_data.reshape(-1, 1)

    n_timesteps, n_connections = weight_data.shape
    times = np.arange(n_timesteps) * dt

    for i in range(n_connections):
        label = (
            connection_labels[i]
            if connection_labels and i < len(connection_labels)
            else f"Connection {i}"
        )
        ax.plot(times, weight_data[:, i], label=label, alpha=0.8)

    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Weight")
    ax.set_title(title)
    ax.axhline(y=0, color="gray", linestyle="--", alpha=0.3)
    if n_connections <= 10:
        ax.legend(loc="best", fontsize=8)
    fig.tight_layout()
    return fig


def to_html(fig: "Figure") -> str:
    """Convert a matplotlib figure to an embeddable HTML img tag.

    Parameters
    ----------
    fig : matplotlib.figure.Figure
        The figure to convert.

    Returns
    -------
    str
        HTML string with base64-encoded PNG image.
    """
    _check_matplotlib()

    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=100, bbox_inches="tight")
    buf.seek(0)
    b64 = base64.b64encode(buf.read()).decode("utf-8")
    plt.close(fig)
    return f'<img src="data:image/png;base64,{b64}" />'
