"""Rockpool exporter.

Exports a Nengo network to a SynSense Rockpool module via NIR.
"""

from pathlib import Path
from typing import Any

import nengo
import nir

from neurocnl.converter.rockpool_io import RockpoolIO
from neurocnl.export.nir_exporter import export_to_nir


def export_to_rockpool(net: nengo.Network, filename: str | Path | None = None) -> Any:
    """Export a Nengo network to a Rockpool module.

    Parameters
    ----------
    net : nengo.Network
        The Nengo network to export.
    filename : str or Path or None
        Optional path to write an intermediate NIR file.

    Returns
    -------
    Any
        The converted Rockpool TorchModule or Sequential.
    """
    import tempfile

    # Use temporary file if none provided
    if filename is None:
        with tempfile.NamedTemporaryFile(suffix=".nir", delete=False) as f:
            temp_filename = f.name

        export_to_nir(net, temp_filename)
        graph = nir.read(temp_filename)

        import os

        os.remove(temp_filename)
    else:
        export_to_nir(net, filename)
        graph = nir.read(str(filename))

    io = RockpoolIO()
    return io.from_nir(graph)
