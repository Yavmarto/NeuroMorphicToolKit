"""Quantisation pass for transforming float weights to integer representations."""

import copy
from dataclasses import dataclass
from typing import Any

import numpy as np

from neurocnl.ir.types import NetworkIR


def quantise_weights_array(
    weights: np.ndarray[Any, Any], bits: int = 8, scale_factor: float | None = None
) -> tuple[np.ndarray[Any, Any], float]:
    """Quantise an array of floating point weights to an n-bit integer range.

    Parameters
    ----------
    weights : np.ndarray[Any, Any]
        Array of floating-point weights.
    bits : int, optional
        Target bit-width (e.g. 8 for int8), by default 8.
    scale_factor : float | None, optional
        Pre-defined scaling factor. If None, it will be calculated
        based on the maximum absolute value in the weights array.

    Returns
    -------
    tuple[np.ndarray[Any, Any], float]
        A tuple containing:
        - The quantized integer weights (as np.ndarray[Any, Any]).
        - The applied scale factor.
    """
    max_val = (1 << (bits - 1)) - 1
    min_val = -(1 << (bits - 1))

    if scale_factor is None:
        max_abs = np.max(np.abs(weights))
        if max_abs == 0:
            scale_factor = 1.0
        else:
            scale_factor = max_val / max_abs

    quantised = np.round(weights * scale_factor)
    quantised = np.clip(quantised, min_val, max_val)

    return quantised.astype(np.int32), scale_factor


@dataclass(frozen=True)
class QuantisationFidelity:
    """What quantising a weight set to *bits* actually costs.

    Exists because "can these weights be quantised?" had been implemented as
    "does every weight land exactly on an integer after scaling?", which is a
    test almost no trained matrix passes — `quantise_weights_array` calls
    `np.round` precisely because values do not land on integers. That guard was
    invisible while PYNQ weights were always zeros (max_abs 0 skips it) or
    hand-picked literals, and rejected every trained network the moment real
    values arrived.

    The two failures actually worth refusing are represented here:
    non-finite weights, which have no fixed-point image at all, and a matrix
    whose every non-zero weight collapses to zero, which deploys a dead network.
    Everything else is ordinary lossy quantisation, reported so a caller can warn
    proportionally.
    """

    scale_factor: float
    max_abs_error: float
    collapsed: int
    total_nonzero: int
    has_non_finite: bool

    @property
    def is_total_loss(self) -> bool:
        """Every non-zero weight quantised to zero — nothing left to compute with."""
        return self.total_nonzero > 0 and self.collapsed == self.total_nonzero

    @property
    def representable(self) -> bool:
        return not self.has_non_finite and not self.is_total_loss

    @property
    def collapsed_fraction(self) -> float:
        if self.total_nonzero == 0:
            return 0.0
        return self.collapsed / self.total_nonzero


def quantisation_fidelity(
    weights: np.ndarray[Any, Any] | list[float], bits: int = 8
) -> QuantisationFidelity:
    """Measure the round-trip cost of quantising *weights* to *bits*.

    The reported ``max_abs_error`` is in the original weight units, so it is
    directly comparable against the weights themselves — for a symmetric scale it
    is bounded by ``max_abs / (2 * ((1 << (bits - 1)) - 1))``.
    """
    array = np.asarray(weights, dtype=float).ravel()
    if array.size == 0:
        return QuantisationFidelity(1.0, 0.0, 0, 0, False)
    if not np.all(np.isfinite(array)):
        return QuantisationFidelity(
            1.0, float("inf"), 0, int(np.count_nonzero(array)), True
        )

    quantised, scale_factor = quantise_weights_array(array, bits=bits)
    # Back to weight units so the error means something to a caller holding the
    # original floats.
    restored = quantised.astype(float) / scale_factor if scale_factor else array
    nonzero_mask = array != 0
    return QuantisationFidelity(
        scale_factor=float(scale_factor),
        max_abs_error=float(np.max(np.abs(array - restored))),
        collapsed=int(np.count_nonzero(nonzero_mask & (quantised == 0))),
        total_nonzero=int(np.count_nonzero(nonzero_mask)),
        has_non_finite=False,
    )


def quantise_network_dict(net_dict: dict[str, Any], bits: int = 8) -> dict[str, Any]:
    """Quantise the weights in a serialized network dictionary.

    Parameters
    ----------
    net_dict : dict[str, Any]
        Network configuration dictionary (e.g., from export_pynq).
    bits : int, optional
        Target bit-width, by default 8.

    Returns
    -------
    dict[str, Any]
        A new network dictionary with quantized weights and adjusted thresholds.
    """
    # Simple copy for non-nested dict to keep it functional
    import copy

    out_dict = copy.deepcopy(net_dict)

    # First pass: collect all weights to find a global scale factor
    # (Or we could do per-layer. Here we do a global scale for simplicity in direct overlay)
    all_weights = []
    for conn in out_dict.get("connections", []):
        all_weights.append(conn["weight"])

    if not all_weights:
        return out_dict

    # Calculate global scale factor
    _, scale_factor = quantise_weights_array(np.array(all_weights), bits=bits)

    # Apply to connections
    for conn in out_dict.get("connections", []):
        # We process single scalar weights in this simple implementation
        w_arr = np.array([conn["weight"]])
        qw, _ = quantise_weights_array(w_arr, bits=bits, scale_factor=scale_factor)
        conn["weight"] = int(qw[0])

    # Apply to populations (thresholds)
    # If weights are scaled by S, the threshold needs to be scaled by S to keep dynamics
    for pop in out_dict.get("populations", []):
        if "params" in pop and "v_threshold" in pop["params"]:
            # We don't want to clip thresholds to the integer bit range here
            # because thresholds might need to be higher than the max weight
            # depending on the network connectivity. We just apply the scale.
            t_val = pop["params"]["v_threshold"] * scale_factor
            pop["params"]["v_threshold"] = int(max(1, round(t_val)))

    out_dict["quantisation"] = {"bits": bits, "scale_factor": float(scale_factor)}
    return out_dict


def quantise_weights(ir: NetworkIR, bits: int = 4) -> NetworkIR:
    """Return a copy of the IR with weights clipped and rounded to `bits`-bit integers.

    Parameters
    ----------
    ir : NetworkIR
        The Network Intermediate Representation.
    bits : int, optional
        Target bit-width, by default 4.

    Returns
    -------
    NetworkIR
        A new NetworkIR with quantized weights and adjusted thresholds.
    """
    ir_copy = copy.deepcopy(ir)

    all_weights = []
    for conn in ir_copy.connections:
        if conn.weight is not None:
            all_weights.append(conn.weight)

    if not all_weights:
        return ir_copy

    _, scale_factor = quantise_weights_array(np.array(all_weights), bits=bits)

    for conn in ir_copy.connections:
        if conn.weight is not None:
            w_arr = np.array([conn.weight])
            qw, _ = quantise_weights_array(w_arr, bits=bits, scale_factor=scale_factor)
            conn.weight = float(qw[0])

    for pop in ir_copy.populations.values():
        if pop.threshold is not None:
            t_val = pop.threshold * scale_factor
            pop.threshold = float(max(1, round(t_val)))

    ir_copy.metadata["quantisation"] = {
        "bits": bits,
        "scale_factor": float(scale_factor),
    }
    return ir_copy
