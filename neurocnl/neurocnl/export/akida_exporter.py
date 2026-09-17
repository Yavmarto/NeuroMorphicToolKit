"""BrainChip Akida exporter.

Produces the ``AkidaMappedNetwork`` payload for a validated ``NetworkIR``,
ready to POST directly to Neurochip's ``/api/neurochip/akida/deploy/mapped``
(the two shapes are field-compatible — see
``Neurochip/neurochip/contracts/akida_runtime_contract.py``).
"""

from __future__ import annotations

from typing import Any

from neurocnl.ir.types import NetworkIR
from neurocnl.mapping.akida_mapper import map_network_ir_to_akida_representation


def export_akida(
    network: NetworkIR, akida_version: str | None = None, **kwargs: Any
) -> dict[str, Any]:
    """Export a validated NetworkIR as an Akida mapped-network payload.

    Args:
        network: Validated NeuroCNL network IR (single faithful feed-forward chain).
        akida_version: Target Akida hardware version (e.g. "akida1", "akida2").
            Falls back to ``network.akida_hardware.version`` or the mapper's default.

    Returns:
        A JSON-ready dict matching Neurochip's ``AkidaMappedNetworkPayloadContract``.

    Raises:
        AkidaMappingRejectedError: If the network cannot be lowered to Akida
            (unsupported topology, unsupported concepts, etc).
    """
    mapped = map_network_ir_to_akida_representation(network, akida_version=akida_version)
    return mapped.model_dump(mode="json")
