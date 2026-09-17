"""Regression tests for /api/deploy/{teensy,pynq,akida}/network endpoints.

Uses FastAPI TestClient (in-process, no live server needed).
Validates response structure and verdicts for the reflex_arc demo spec.
"""

from __future__ import annotations

from pathlib import Path
from unittest import mock

import pytest

REFLEX_ARC_SPEC = (
    Path(__file__).resolve().parent.parent / "app" / "templates" / "reflex_arc.cnl"
).read_text()

INVALID_SPEC = "This is not a valid CNL sentence at all."
NIR_NATIVE_SPEC = "\n".join(
    [
        "Define a network named deploy_test.",
        "Define an input port named input with shape (2,).",
        "Define a linear transformation named w_in with weight matrix shape (2, 2).",
        "Define a LIF neuron named pop_a "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define a linear transformation named w_out with weight matrix shape (2, 2).",
        "Define a LIF neuron named pop_b "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define an output port named output with shape (2,).",
        "input connects to w_in.",
        "w_in connects to pop_a.",
        "pop_a connects to w_out.",
        "w_out connects to pop_b.",
        "pop_b connects to output.",
    ]
)


def _mnist_fcn_spec(hidden: int) -> str:
    """The MNIST FCN walkthrough's Model canvas, as NIR-native CNL.

    784 inputs is what MNIST gives you, so the input port is always wider than
    the 256-per-NP limit — see test_mnist_input_port_does_not_block_export.
    """
    return "\n".join(
        [
            "Define a network named mnist_fcn.",
            "Define an input port named image with shape (784,).",
            f"Define a linear transformation named fc1 with weight matrix shape ({hidden}, 784).",
            "Define a LIF neuron named hidden with time constant 0.002, "
            "resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
            f"Define a linear transformation named fc2 with weight matrix shape (10, {hidden}).",
            "Define a LIF neuron named readout with time constant 0.002, "
            "resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
            "Define an output port named digit with shape (10,).",
            "image connects to fc1.",
            "fc1 connects to hidden.",
            "hidden connects to fc2.",
            "fc2 connects to readout.",
            "readout connects to digit.",
        ]
    )


STDP_SPEC = (
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.8\n"
    "The motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.6\n"
    "The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds\n"
    "The motor neuron MUST NOT fire DURING the refractory period of 0.003 seconds\n"
    "The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds\n"
    "The motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds\n"
    "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.5\n"
    "A synapse MUST strengthen IF pre-synaptic spike precedes post-synaptic spike by less than 20ms\n"
    "A synapse MUST weaken IF post-synaptic spike precedes pre-synaptic spike\n"
)


# ---------------------------------------------------------------------------
# Teensy
# ---------------------------------------------------------------------------


class TestTeensyDeploy:
    def test_success(self, client):
        resp = client.post(
            "/api/deploy/teensy/network",
            json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["verdict"] == "faithful"
        assert data["rejection_reasons"] == []
        payload = data["payload"]
        assert payload is not None
        assert "num_neurons" in payload
        assert "neuron_model" in payload
        assert "populations" in payload
        assert "connections" in payload
        assert payload["weight_bit_width"] == 8

    @pytest.mark.parametrize("bit_width", [8, 16, 32])
    def test_bit_widths(self, client, bit_width):
        resp = client.post(
            "/api/deploy/teensy/network",
            json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": bit_width},
        )
        assert resp.status_code == 200
        assert resp.json()["payload"]["weight_bit_width"] == bit_width

    def test_invalid_bit_width(self, client):
        resp = client.post(
            "/api/deploy/teensy/network",
            json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": 7},
        )
        # Pydantic validation: weight_bit_width ge=8
        assert resp.status_code == 422

    def test_parse_error(self, client):
        resp = client.post(
            "/api/deploy/teensy/network",
            json={"spec": INVALID_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 422
        detail = resp.json()["detail"]
        assert detail["error"] == "parse_failed"
        assert detail["items"][0]["code"] is not None
        assert detail["items"][0]["message"] is not None
        assert detail["items"][0]["line"] == 1


# ---------------------------------------------------------------------------
# PYNQ
# ---------------------------------------------------------------------------


class TestPynqDeploy:
    def test_success(self, client):
        resp = client.post(
            "/api/deploy/pynq/network",
            json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["support_state"] in ("exportable", "exportable_with_warnings")
        assert data["network_summary"] is not None
        assert data["deploy_payload"] is not None
        assert data["deploy_payload"]["weights"]
        # Read from the contract, not written out here: hardcoding the overlay id
        # and capacity is what left this test asserting v1 after the v2 migration.
        from neurocnl.contracts.pynq_deployment_contract import PYNQ_LIMITS

        assert data["deploy_payload"]["overlay_id"] == PYNQ_LIMITS.OVERLAY_ID
        assert data["deploy_payload"]["overlay_version"] == PYNQ_LIMITS.OVERLAY_VERSION
        assert data["deploy_payload"]["weight_bit_width"] == 8
        assert data["deploy_payload"]["max_supported_synapses"] == PYNQ_LIMITS.MAX_SYNAPSES
        assert "register_map" in data["deploy_payload"]
        # The layer chain the board derives every size from — see
        # `PynqLayerDescriptor` on the Dart side.
        assert data["deploy_payload"]["layers"]

    def test_bit_widths(self, client):
        resp = client.post(
            "/api/deploy/pynq/network",
            json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 200

    def test_invalid_bit_width(self, client):
        resp = client.post(
            "/api/deploy/pynq/network",
            json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": 3},
        )
        assert resp.status_code == 422

    def test_parse_error(self, client):
        resp = client.post(
            "/api/deploy/pynq/network",
            json={"spec": INVALID_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 422
        detail = resp.json()["detail"]
        assert detail["error"] == "parse_failed"
        assert detail["items"][0]["code"] is not None
        assert detail["items"][0]["message"] is not None
        assert detail["items"][0]["line"] == 1

    def test_payload_build_failures_return_structured_detail(self, client):
        with mock.patch(
            "neurocnl.handoff.neurochip_pynq_handoff.build_pynq_deploy_payload",
            side_effect=RuntimeError("pynq payload exploded"),
        ):
            resp = client.post(
                "/api/deploy/pynq/network",
                json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": 8},
            )

        assert resp.status_code == 500
        detail = resp.json()["detail"]
        assert detail["error"] == "pynq_deploy_payload_failed"
        assert "pynq payload exploded" in detail["messages"][0]

    def test_response_serialization_failures_return_structured_detail(self, client):
        with mock.patch(
            "neurocnl.handoff.neurochip_pynq_handoff.build_pynq_deploy_payload",
            return_value={"weights": [float("nan")]},
        ):
            resp = client.post(
                "/api/deploy/pynq/network",
                json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": 8},
            )

        assert resp.status_code == 500
        detail = resp.json()["detail"]
        assert detail["error"] == "pynq_exportability_response_failed"
        assert "non-finite float" in detail["messages"][0]

    def test_nir_native_spec_returns_exportability_payload(self, client):
        resp = client.post(
            "/api/deploy/pynq/network",
            json={"spec": NIR_NATIVE_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["support_state"] in (
            "exportable",
            "exportable_with_warnings",
            "not_exportable",
        )
        assert data["network_summary"] is not None


# ---------------------------------------------------------------------------
# Akida
# ---------------------------------------------------------------------------


class TestAkidaDeploy:
    def test_success(self, client):
        resp = client.post(
            "/api/deploy/akida/network",
            json={"spec": REFLEX_ARC_SPEC},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["support_state"].startswith("exportable_scaffold")
        assert data["akida_version"] == "akida1"
        assert data["network_summary"] is not None
        assert data["mapped_network"] is not None

    @pytest.mark.parametrize("version", ["akida1", "akida2"])
    def test_versions(self, client, version):
        resp = client.post(
            "/api/deploy/akida/network",
            json={"spec": REFLEX_ARC_SPEC, "akida_version": version},
        )
        assert resp.status_code == 200
        assert resp.json()["akida_version"] == version

    @pytest.mark.parametrize("bit_width", [1, 2, 4])
    def test_valid_bit_widths(self, client, bit_width):
        resp = client.post(
            "/api/deploy/akida/network",
            json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": bit_width},
        )
        assert resp.status_code == 200

    def test_invalid_bit_width(self, client):
        resp = client.post(
            "/api/deploy/akida/network",
            json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": 5},
        )
        assert resp.status_code == 422

    def test_parse_error(self, client):
        resp = client.post(
            "/api/deploy/akida/network",
            json={"spec": INVALID_SPEC},
        )
        assert resp.status_code == 422
        detail = resp.json()["detail"]
        assert detail["error"] == "parse_failed"
        assert detail["items"][0]["code"] is not None
        assert detail["items"][0]["message"] is not None
        assert detail["items"][0]["line"] == 1

    def test_network_summary_shape(self, client):
        resp = client.post(
            "/api/deploy/akida/network",
            json={"spec": REFLEX_ARC_SPEC},
        )
        assert resp.status_code == 200
        summary = resp.json()["network_summary"]
        assert summary is not None
        assert "n_populations" in summary
        assert "n_neurons" in summary
        assert "n_connections" in summary

    def test_mnist_input_port_does_not_block_export(self, client):
        """784 -> 256 -> 10 is the guide's Akida canvas; it must pass the gate.

        The 784-wide input port used to be counted as a neuron population
        against the 256-per-NP limit, so every MNIST network was rejected no
        matter how narrow the hidden layer was.
        """
        resp = client.post(
            "/api/deploy/akida/network",
            json={"spec": _mnist_fcn_spec(256), "akida_version": "akida1"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["rejections"] == []
        assert data["support_state"].startswith("exportable_scaffold")
        assert data["mapped_network"] is not None

    def test_oversized_layer_rejection_names_the_node_and_the_field(self, client):
        resp = client.post(
            "/api/deploy/akida/network",
            json={"spec": _mnist_fcn_spec(1000), "akida_version": "akida1"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["support_state"] == "unsupported"

        # One cause must produce one message, not exceeds_np_size plus a
        # redundant unsupported_topology.
        assert len(data["rejections"]) == 1
        message = data["rejections"][0]
        assert "hidden" in message
        assert "1000" in message
        assert "256" in message
        assert "Neurons" in message

    def test_rejections_are_never_raw_enum_codes(self, client):
        """The endpoint used to return AkidaRejectionReason values verbatim."""
        from neurocnl.contracts.akida_deployment_contract import AkidaRejectionReason

        resp = client.post(
            "/api/deploy/akida/network",
            json={"spec": _mnist_fcn_spec(1000), "akida_version": "akida1"},
        )
        assert resp.status_code == 200
        codes = {reason.value for reason in AkidaRejectionReason}
        assert not codes.intersection(resp.json()["rejections"])

    def test_exportability_endpoint_stays_scaffold_only(self, client):
        resp = client.post(
            "/api/deploy/akida/network",
            json={"spec": REFLEX_ARC_SPEC},
        )
        assert resp.status_code == 200
        support_state = resp.json()["support_state"]
        assert support_state in {
            "exportable_scaffold",
            "exportable_scaffold_with_warnings",
            "unsupported",
        }

    def test_unexpected_akida_exportability_failures_return_structured_detail(self, client):
        with mock.patch(
            "neurocnl.mapping.akida_mapper.map_network_ir_to_akida_representation",
            side_effect=RuntimeError("akida mapper exploded"),
        ):
            resp = client.post(
                "/api/deploy/akida/network",
                json={"spec": REFLEX_ARC_SPEC},
            )

        assert resp.status_code == 500
        detail = resp.json()["detail"]
        assert detail["error"] == "akida_exportability_failed"
        assert "akida mapper exploded" in detail["messages"][0]

    def test_nir_native_spec_returns_scaffold_verdict(self, client):
        resp = client.post(
            "/api/deploy/akida/network",
            json={"spec": NIR_NATIVE_SPEC},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["support_state"] in {
            "exportable_scaffold",
            "exportable_scaffold_with_warnings",
            "unsupported",
        }
        assert data["network_summary"] is not None


# ---------------------------------------------------------------------------
# Lava
# ---------------------------------------------------------------------------


class TestLavaDeploy:
    def test_success(self, client):
        resp = client.post(
            "/api/deploy/lava/network",
            json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["support_state"] in ("exportable", "exportable_with_warnings")
        assert data["network_summary"] is not None
        payload = data["deploy_payload"]
        assert payload is not None
        assert payload["num_neurons"] > 0
        assert payload["num_synapses"] > 0
        assert payload["neuron_model"] == "LIF"
        assert payload["weight_bit_width"] == 8
        assert payload["populations"]
        assert payload["connections"]

    def test_parse_error(self, client):
        resp = client.post(
            "/api/deploy/lava/network",
            json={"spec": INVALID_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 422
        detail = resp.json()["detail"]
        assert detail["error"] == "parse_failed"
        assert detail["items"][0]["code"] is not None
        assert detail["items"][0]["message"] is not None
        assert detail["items"][0]["line"] == 1

    def test_invalid_bit_width(self, client):
        resp = client.post(
            "/api/deploy/lava/network",
            json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": 0},
        )
        assert resp.status_code == 422

    def test_warning_tier_network_returns_exportable_with_warnings(self, client):
        resp = client.post(
            "/api/deploy/lava/network",
            json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["support_state"] in {"exportable", "exportable_with_warnings"}
        if data["support_state"] == "exportable_with_warnings":
            assert data["warnings"]

    @pytest.mark.xfail(
        reason=(
            "STDP_SPEC uses the legacy biological grammar ('MUST strengthen/"
            "weaken'), which the parser rejects outright ('MUST' is a "
            "forbidden keyword in NIR-native CNL) — every request here 422s "
            "before reaching the Lava planner this test targets. There is "
            "also no NIR-native syntax for declaring a learning rule at all: "
            "_nir_native_records_to_deploy_ir never populates "
            "NetworkIR.learning_rules, so this rejection path has no way to "
            "be exercised through the current deploy pipeline."
        ),
        strict=False,
    )
    def test_unsupported_learning_rule_returns_unsupported(self, client):
        resp = client.post(
            "/api/deploy/lava/network",
            json={"spec": STDP_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["support_state"] == "unsupported"
        assert data["deploy_payload"] is None
        assert data["rejections"]

    def test_payload_build_failures_return_structured_detail(self, client):
        with mock.patch(
            "backend.app.routers.deploy.build_lava_deploy_payload",
            side_effect=RuntimeError("lava payload exploded"),
        ):
            resp = client.post(
                "/api/deploy/lava/network",
                json={"spec": REFLEX_ARC_SPEC, "weight_bit_width": 8},
            )

        assert resp.status_code == 500
        detail = resp.json()["detail"]
        assert detail["error"] == "lava_deploy_payload_failed"
        assert "lava payload exploded" in detail["messages"][0]

    def test_nir_native_spec_returns_lava_deployability(self, client):
        resp = client.post(
            "/api/deploy/lava/network",
            json={"spec": NIR_NATIVE_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["support_state"] in (
            "exportable",
            "exportable_with_warnings",
            "unsupported",
        )
        assert data["network_summary"] is not None


# ---------------------------------------------------------------------------
# SC-NeuroCore
# ---------------------------------------------------------------------------


class TestScNeuroCoreDeploy:
    def test_check_toolchain_exists(self, client):
        with mock.patch("shutil.which", return_value="/usr/bin/vivado"):
            resp = client.get(
                "/api/deploy/sc_neurocore/check_toolchain",
                params={"toolchain": "vivado"},
            )
        assert resp.status_code == 200
        data = resp.json()
        assert data["installed"] is True
        assert data["resolved_path"] == "/usr/bin/vivado"

    def test_check_toolchain_missing(self, client):
        with mock.patch("shutil.which", return_value=None):
            resp = client.get(
                "/api/deploy/sc_neurocore/check_toolchain",
                params={"toolchain": "quartus"},
            )
        assert resp.status_code == 200
        data = resp.json()
        assert data["installed"] is False
        assert data["resolved_path"] is None

    def test_check_toolchain_with_custom_path(self, client):
        with mock.patch("shutil.which", return_value="/opt/my_custom/vivado_bin"):
            resp = client.get(
                "/api/deploy/sc_neurocore/check_toolchain",
                params={"toolchain": "vivado", "bin_path": "/opt/my_custom/vivado_bin"},
            )
        assert resp.status_code == 200
        data = resp.json()
        assert data["installed"] is True
        assert data["resolved_path"] == "/opt/my_custom/vivado_bin"
