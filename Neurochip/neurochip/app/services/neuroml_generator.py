"""NeuroML format generator."""

import hashlib
import io
import zipfile
from collections.abc import Callable
from datetime import datetime

from ..._compat import UTC
from ...contracts.deployment_contracts import DeploymentManifest, TargetDevice
from ..schemas.estimation import NetworkInput


def generate_neuroml_package(
    network: NetworkInput,
    bit_width: int = 8,
    progress_callback: Callable[[float, str], None] | None = None,
) -> bytes:
    """Generate a complete NeuroML export as a zip archive."""
    if progress_callback:
        progress_callback(0.1, "Starting NeuroML package generation")

    timestamp = datetime.now(UTC).isoformat()

    if progress_callback:
        progress_callback(0.4, "Building NeuroML XML representation")

    neuroml_content = (
        f'<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<neuroml xmlns="http://www.neuroml.org/schema/neuroml2" '
        f'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        f'xsi:schemaLocation="http://www.neuroml.org/schema/neuroml2 '
        f'https://raw.githubusercontent.com/NeuroML/NeuroML2/master/Schemas/NeuroML2/NeuroML_v2.3.xsd" '
        f'id="SNNNetwork">\n'
        f"  <!-- Generated on {timestamp} -->\n"
        f"  <notes>SNN with {network.num_neurons} neurons and {network.num_synapses} synapses</notes>\n"
        f'  <property tag="bit_width" value="{bit_width}"/>\n'
        f'  <network id="network" type="networkWithConstantConcentration">\n'
        f'    <population id="pop" component="lif" size="{network.num_neurons}"/>\n'
        f"  </network>\n"
        f"</neuroml>\n"
    )

    readme = (
        f"# NeuroML Export\n\n"
        f"Generated on {timestamp}\n\n"
        f"## Network Summary\n"
        f"- Neurons: {network.num_neurons}\n"
        f"- Synapses: {network.num_synapses}\n"
        f"- Weight bit-width: {bit_width}-bit\n"
    )

    manifest = DeploymentManifest(
        target_device=TargetDevice.NEUROML,
        core_count=1,
        firmware_version="1.0.0",
        checksum_sha256=hashlib.sha256(neuroml_content.encode()).hexdigest(),
    )

    if progress_callback:
        progress_callback(0.8, "Creating ZIP archive")

    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("neuroml_export/network.nml", neuroml_content)
        zf.writestr("neuroml_export/manifest.json", manifest.model_dump_json(indent=2))
        zf.writestr("neuroml_export/README.md", readme)

    if progress_callback:
        progress_callback(1.0, "NeuroML package generation complete")

    return buffer.getvalue()
