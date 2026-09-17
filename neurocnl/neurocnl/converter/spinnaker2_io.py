"""SpiNNaker2 runtime I/O mapping.

Runtime input/output mapping for py-spinnaker2 is not yet implemented.
Use ``spinnaker2_exporter`` to generate deployable py-spinnaker2 Python code instead.
"""

from typing import Any


def format_spinnaker2_inputs(inputs: dict[str, Any]) -> dict[str, Any]:
    """Format abstract input signals into py-spinnaker2 compatible structures.

    Not yet implemented. Use ``spinnaker2_exporter.export_spinnaker2`` to generate
    deployable py-spinnaker2 code instead of using this runtime helper.

    Raises
    ------
    NotImplementedError
        Always — SpiNNaker2 runtime I/O mapping is not yet implemented.
    """
    raise NotImplementedError(
        "SpiNNaker2 runtime I/O mapping is not yet implemented. "
        "Use spinnaker2_exporter to generate py-spinnaker2 deployment code instead."
    )


def parse_spinnaker2_outputs(
    spikes_dict: dict[int, list[int]], voltages_dict: dict[int, Any]
) -> dict[str, Any]:
    """Parse output from py-spinnaker2 into standard format.

    Not yet implemented. Use ``spinnaker2_exporter.export_spinnaker2`` to generate
    deployable py-spinnaker2 code instead of using this runtime helper.

    Raises
    ------
    NotImplementedError
        Always — SpiNNaker2 runtime I/O mapping is not yet implemented.
    """
    raise NotImplementedError(
        "SpiNNaker2 runtime I/O mapping is not yet implemented. "
        "Use spinnaker2_exporter to generate py-spinnaker2 deployment code instead."
    )
