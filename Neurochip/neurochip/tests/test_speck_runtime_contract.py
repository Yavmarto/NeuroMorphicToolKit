import io
import json
import zipfile

from pydantic import ValidationError

from neurochip.contracts.speck_runtime_contract import (
    SpeckDeploymentManifest,
    SpeckEnvironmentChecks,
    SpeckMappedNetworkPayloadContract,
    SpeckRuntimeStatusContract,
    SpeckSamnaConfigContract,
    validate_speck_runtime_artifact_archive,
)


def test_speck_runtime_status_contract_accepts_environment_checks() -> None:
    status = SpeckRuntimeStatusContract(
        state="mapped",
        sdk_available=False,
        sdk_status="not_available",
        sdk_issues=["samna_missing", "sdk_not_available"],
        runtime_target="software_fallback",
        device_info="SpeckSimulator",
        environment_checks=SpeckEnvironmentChecks(
            host_supported=True,
            python_supported=True,
            sinabs_available=False,
            samna_available=False,
            device_discovery_supported=False,
            device_discovered=False,
            discovered_device_count=0,
            recommended_runtime="simulator",
        ),
    )

    assert status.runtime_target == "software_fallback"
    assert status.environment_checks.recommended_runtime == "simulator"


def test_speck_mapped_network_contract_rejects_unsupported_bit_width() -> None:
    try:
        SpeckMappedNetworkPayloadContract(
            populations=[{"id": "in", "size": 16}, {"id": "out", "size": 4}],
            connections=[{"source": "in", "target": "out", "weight": 1.0}],
            network_summary={"weight_bit_width": 4},
        )
    except ValidationError as exc:
        assert "weight_bit_width" in str(exc)
    else:
        raise AssertionError("Expected validation failure for unsupported Speck bit width")


def test_validate_speck_runtime_artifact_archive_accepts_required_files() -> None:
    archive_buffer = io.BytesIO()
    with zipfile.ZipFile(archive_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(
            "speck_deploy/model.json",
            json.dumps(
                {
                    "mapped_network": {
                        "populations": [
                            {"id": "in", "size": 16, "neuron_model": "lif"},
                            {"id": "out", "size": 4, "neuron_model": "lif"},
                        ],
                        "connections": [{"source": "in", "target": "out", "weight": 1.0}],
                        "network_summary": {"weight_bit_width": 8},
                    }
                }
            ),
        )
        zf.writestr(
            "speck_deploy/compile_plan.json",
            json.dumps(
                {
                    "compiler_backend": "normalized_sequential",
                    "deployable": True,
                    "topology_mode": "linear_chain",
                }
            ),
        )
        zf.writestr(
            "speck_deploy/config.samna",
            SpeckSamnaConfigContract(
                device_type_name="Speck2fDevKit",
                samna_configuration_type="samna.speck2f.configuration.SpeckConfiguration",
                artifact_mode="scaffold",
                monitor_enable=True,
                readout_enable=False,
                input_spike_layer=0,
                output_event_mode="spike_monitor",
                configuration_json=json.dumps({"dvs_layer": {"monitor_enable": True}}),
                population_count=2,
                connection_count=1,
            ).model_dump_json(indent=2),
        )
        zf.writestr(
            "speck_deploy/manifest.json",
            SpeckDeploymentManifest(
                core_count=2,
                firmware_version="1.0.0",
                artifact_schema_version="1.0.0",
                checksum_sha256="a" * 64,
            ).model_dump_json(indent=2),
        )
        zf.writestr("speck_deploy/README.md", "# Speck")

    manifest = validate_speck_runtime_artifact_archive(archive_buffer.getvalue())

    assert manifest.target_device == "SynSense Speck 2"
    assert manifest.core_count == 2
