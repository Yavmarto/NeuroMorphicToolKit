"""SNN-MLIR text generator.

Translates a compiled NIR graph to SNN-MLIR dialect text via the
``snn-mlir`` package (https://github.com/INTERA-GROUP/snn-mlir).

``snn-mlir`` only supports strictly feedforward, fully-connected networks —
this matches NMTK's current Simple Reflex Topology (sensory -> motor,
single projection) but not recurrent or convolutional graphs.
"""

import os
from typing import cast


def generate_mlir(nir_path: str | os.PathLike[str], *, quantize: bool = False) -> str:
    """Generate SNN-MLIR dialect text from a compiled ``.nir`` file.

    Parameters
    ----------
    nir_path : str or Path
        Path to a ``.nir`` file produced by :func:`neurocnl.compile.compile_to_nir`.
    quantize : bool
        When True, emit int8 + Q12 fixed-point MLIR instead of float32.

    Returns
    -------
    str
        SNN-MLIR dialect text.

    Raises
    ------
    RuntimeError
        If the graph uses topology snn-mlir cannot represent (e.g. recurrent
        or convolutional connections) or if ``snn-mlir`` is not installed.
    """
    try:
        import snn_mlir
    except ImportError as exc:
        raise RuntimeError(
            "The 'snn-mlir' package is required for MLIR export. "
            "Install the 'studio' extra: pip install 'neurocnl[studio]'."
        ) from exc

    try:
        return cast(str, snn_mlir.to_mlir(str(nir_path), quantize=quantize))
    except Exception as exc:
        raise RuntimeError(f"snn-mlir failed to lower NIR graph: {exc}") from exc
