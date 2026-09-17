"""Integration tests for NeuroCNL → Neurochip PYNQ handoff.

Covers:
- Deploy payload shape (weights, config, bitstream_path, register_map)
- DEPLOYABLE result when mock HTTP returns 200 + "configured" status
- PynqHandoffRejectedError on HTTP 5xx (OVERLAY_LOAD_FAILURE)
- PynqHandoffRejectedError on board unreachable (URLError / BOARD_UNREACHABLE)
- Export gate: NOT_EXPORTABLE → raises before any HTTP call
- Status mismatch: backend not "configured" after deploy → NOT_DEPLOYABLE
- Deterministic weight extraction across repeated calls
- Custom endpoint config (non-default URL and API key)
"""

from __future__ import annotations

import hashlib
import urllib.error
from email.message import Message
from typing import Any

import pytest

from neurocnl.contracts.pynq_deployment_contract import (
    PYNQ_LIMITS,
    PynqExportResult,
    PynqRejectionReason,
    PynqSupportState,
)
from neurocnl.contracts.pynq_runtime_artifact_contract import (
    PynqConnectionEntry,
    PynqOverlayConfigContract,
    PynqOverlayManifestContract,
    PynqPopulationEntry,
    PynqQuantisationInfo,
    PynqRegisterMap,
    PynqRuntimeArtifact,
)
from neurocnl.handoff.neurochip_pynq_handoff import (
    NeurochipEndpointConfig,
    NeurochipPynqClient,
    NeurochipPynqClientProtocol,
    PynqHandoffRejectedError,
    _build_deploy_payload,
    build_pynq_deploy_payload,
    leak_shift_for_tau,
    map_pynq_artifact_to_deploy_request,
)

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------


def _make_overlay_config(
    n_neurons: int = 4,
    n_connections: int = 2,
    bits: int = 8,
    scale_factor: float = 127.0,
) -> PynqOverlayConfigContract:
    populations = [
        PynqPopulationEntry(
            id="input",
            n_neurons=n_neurons // 2,
            neuron_model="LIF",
            params={"v_threshold": 1.0},
        ),
        PynqPopulationEntry(
            id="output",
            n_neurons=n_neurons - n_neurons // 2,
            neuron_model="LIF",
            params={"v_threshold": 1.0},
        ),
    ]
    connections = [
        PynqConnectionEntry(pre="input", post="output", weight=i + 1)
        for i in range(n_connections)
    ]
    quantisation = PynqQuantisationInfo(bits=bits, scale_factor=scale_factor)
    return PynqOverlayConfigContract(
        network_name="test_net",
        populations=populations,
        connections=connections,
        quantisation=quantisation,
    )


def _make_artifact(
    n_neurons: int = 4,
    n_connections: int = 2,
    bits: int = 8,
) -> PynqRuntimeArtifact:
    overlay_config = _make_overlay_config(
        n_neurons=n_neurons,
        n_connections=n_connections,
        bits=bits,
    )
    register_map = PynqRegisterMap()
    overlay_manifest = PynqOverlayManifestContract(register_map=register_map)
    fake_checksum = hashlib.sha256(b"dummy_weights").hexdigest()
    fake_manifest = hashlib.sha256(b"dummy_manifest").hexdigest()
    return PynqRuntimeArtifact(
        overlay_manifest=overlay_manifest,
        overlay_config=overlay_config,
        register_map=register_map,
        weight_bit_width=bits,
        weights_checksum_sha256=fake_checksum,
        manifest_checksum_sha256=fake_manifest,
        total_neurons=n_neurons,
        total_synapses=n_connections,
    )


def _exportable_result() -> PynqExportResult:
    return PynqExportResult(
        support_state=PynqSupportState.EXPORTABLE,
        rejections=[],
        warnings=[],
        network_summary={"n_neurons": 4, "n_synapses": 2},
    )


def _not_exportable_result() -> PynqExportResult:
    return PynqExportResult(
        support_state=PynqSupportState.NOT_EXPORTABLE,
        rejections=[PynqRejectionReason.EXCEEDS_NEURON_CAPACITY],
        warnings=[],
        network_summary={},
    )


def _default_endpoint(url: str = "http://pynq-z2:8000") -> NeurochipEndpointConfig:
    return NeurochipEndpointConfig(
        base_url=url,
        bitstream_path="snn_overlay.bit",
        timeout=5.0,
    )


class _MockClient:
    """Test double that returns configurable responses."""

    def __init__(
        self,
        deploy_response: dict[str, Any] | None = None,
        status_response: dict[str, Any] | None = None,
        deploy_exc: Exception | None = None,
        status_exc: Exception | None = None,
    ) -> None:
        self._deploy_response = deploy_response or {"status": "success"}
        self._status_response = status_response or {"state": "configured"}
        self._deploy_exc = deploy_exc
        self._status_exc = status_exc
        self.deploy_calls: list[dict[str, Any]] = []
        self.status_calls: list[str] = []

    def post_deploy(
        self,
        deploy_url: str,
        payload: dict[str, Any],
        headers: dict[str, str],
        timeout: float,
    ) -> dict[str, Any]:
        self.deploy_calls.append({"url": deploy_url, "payload": payload})
        if self._deploy_exc is not None:
            raise self._deploy_exc
        return self._deploy_response

    def get_status(
        self,
        status_url: str,
        headers: dict[str, str],
        timeout: float,
    ) -> dict[str, Any]:
        self.status_calls.append(status_url)
        if self._status_exc is not None:
            raise self._status_exc
        return self._status_response


# ---------------------------------------------------------------------------
# TestDeployPayloadShape
# ---------------------------------------------------------------------------


class TestDeployPayloadShape:
    """Payload built from artifact has the correct structure."""

    def test_weights_are_floats_in_connection_order(self) -> None:
        artifact = _make_artifact(n_connections=3)
        endpoint = _default_endpoint()

        payload = _build_deploy_payload(artifact, endpoint)

        assert payload["weights"] == [1.0, 2.0, 3.0]

    def test_config_includes_threshold_and_bit_width(self) -> None:
        artifact = _make_artifact(bits=8)
        endpoint = _default_endpoint()

        payload = _build_deploy_payload(artifact, endpoint)
        config = payload["config"]

        # The artifact is the *quantised* network: `quantise_network_dict` has
        # already scaled every threshold by the same factor as the weights, so
        # the payload passes it through. Scaling it again here squared it, and a
        # squared threshold is unreachable by any input the engine can present.
        assert config["threshold"] == 1
        assert config["bit_width"] == 8
        assert payload["overlay_id"] == PYNQ_LIMITS.OVERLAY_ID
        assert payload["overlay_version"] == PYNQ_LIMITS.OVERLAY_VERSION
        assert payload["weight_bit_width"] == 8
        assert payload["max_supported_neurons"] == PYNQ_LIMITS.MAX_NEURONS
        assert payload["max_supported_synapses"] == PYNQ_LIMITS.MAX_SYNAPSES
        assert payload["dma_ip_name"] == "axi_dma_0"
        assert payload["snn_ip_name"] == "snn_engine_0"

    def test_bitstream_path_from_endpoint_config(self) -> None:
        artifact = _make_artifact()
        endpoint = NeurochipEndpointConfig(
            base_url="http://board:8000",
            bitstream_path="/opt/overlays/custom.bit",
        )

        payload = _build_deploy_payload(artifact, endpoint)

        assert payload["bitstream_path"] == "/opt/overlays/custom.bit"

    def test_register_map_is_dict(self) -> None:
        artifact = _make_artifact()
        endpoint = _default_endpoint()

        payload = _build_deploy_payload(artifact, endpoint)

        reg = payload["register_map"]
        assert isinstance(reg, dict)
        assert "base_address" in reg
        assert "weights_ptr_offset" in reg
        # An artifact describes the overlay contract; the concrete offsets
        # belong to whichever bitstream the board has installed.
        assert reg["resolved_from_hwh"] is False

    def test_payload_is_json_serializable(self) -> None:
        import json

        artifact = _make_artifact()
        payload = _build_deploy_payload(artifact, _default_endpoint())
        serialized = json.dumps(payload)
        assert isinstance(serialized, str)


# ---------------------------------------------------------------------------
# TestDeployableResult
# ---------------------------------------------------------------------------


class TestDeployableResult:
    """A successful deploy + configured status → DEPLOYABLE."""

    def test_returns_deployable_state(self) -> None:
        client = _MockClient(
            deploy_response={"status": "success"},
            status_response={"state": "configured"},
        )
        result = map_pynq_artifact_to_deploy_request(
            artifact=_make_artifact(),
            export_result=_exportable_result(),
            endpoint_config=_default_endpoint(),
            client=client,
        )

        assert result.support_state == PynqSupportState.DEPLOYABLE
        assert result.runtime_rejections == []

    def test_deploy_response_stored_in_result(self) -> None:
        deploy_resp = {"status": "success", "message": "configured"}
        client = _MockClient(deploy_response=deploy_resp)
        result = map_pynq_artifact_to_deploy_request(
            artifact=_make_artifact(),
            export_result=_exportable_result(),
            endpoint_config=_default_endpoint(),
            client=client,
        )

        assert result.deploy_response == deploy_resp

    def test_status_response_stored_in_result(self) -> None:
        status_resp = {"state": "configured", "bitstream_path": "snn_overlay.bit"}
        client = _MockClient(status_response=status_resp)
        result = map_pynq_artifact_to_deploy_request(
            artifact=_make_artifact(),
            export_result=_exportable_result(),
            endpoint_config=_default_endpoint(),
            client=client,
        )

        assert result.status_response == status_resp

    def test_deploy_payload_stored_in_result(self) -> None:
        client = _MockClient()
        result = map_pynq_artifact_to_deploy_request(
            artifact=_make_artifact(n_connections=2),
            export_result=_exportable_result(),
            endpoint_config=_default_endpoint(),
            client=client,
        )

        assert result.deploy_payload is not None
        assert "weights" in result.deploy_payload
        assert len(result.deploy_payload["weights"]) == 2

    def test_endpoint_url_stored(self) -> None:
        client = _MockClient()
        result = map_pynq_artifact_to_deploy_request(
            artifact=_make_artifact(),
            export_result=_exportable_result(),
            endpoint_config=_default_endpoint("http://board:9000"),
            client=client,
        )

        assert result.endpoint_url == "http://board:9000"


# ---------------------------------------------------------------------------
# TestHttpErrorRejection
# ---------------------------------------------------------------------------


class TestHttpErrorRejection:
    """5xx HTTP errors map to OVERLAY_LOAD_FAILURE / NOT_DEPLOYABLE."""

    def test_raises_on_http_error(self) -> None:
        http_err = urllib.error.HTTPError(
            url="http://pynq-z2:8000/hardware/pynq/deploy",
            code=500,
            msg="Internal Server Error",
            hdrs=Message(),
            fp=None,
        )
        client = _MockClient(deploy_exc=http_err)

        with pytest.raises(PynqHandoffRejectedError) as exc_info:
            map_pynq_artifact_to_deploy_request(
                artifact=_make_artifact(),
                export_result=_exportable_result(),
                endpoint_config=_default_endpoint(),
                client=client,
            )

        err_result = exc_info.value.handoff_result
        assert err_result.support_state == PynqSupportState.NOT_DEPLOYABLE
        assert PynqRejectionReason.OVERLAY_LOAD_FAILURE in err_result.runtime_rejections

    def test_deploy_payload_preserved_on_failure(self) -> None:
        client = _MockClient(
            deploy_exc=urllib.error.HTTPError(
                url="", code=503, msg="Service Unavailable", hdrs=Message(), fp=None
            )
        )

        with pytest.raises(PynqHandoffRejectedError) as exc_info:
            map_pynq_artifact_to_deploy_request(
                artifact=_make_artifact(n_connections=3),
                export_result=_exportable_result(),
                endpoint_config=_default_endpoint(),
                client=client,
            )

        err = exc_info.value.handoff_result
        assert err.deploy_payload is not None
        assert len(err.deploy_payload["weights"]) == 3


# ---------------------------------------------------------------------------
# TestBoardUnreachable
# ---------------------------------------------------------------------------


class TestBoardUnreachable:
    """Connection failures map to BOARD_UNREACHABLE / NOT_DEPLOYABLE."""

    def test_raises_on_url_error(self) -> None:
        url_err = urllib.error.URLError("Connection refused")
        client = _MockClient(deploy_exc=url_err)

        with pytest.raises(PynqHandoffRejectedError) as exc_info:
            map_pynq_artifact_to_deploy_request(
                artifact=_make_artifact(),
                export_result=_exportable_result(),
                endpoint_config=_default_endpoint(),
                client=client,
            )

        err = exc_info.value.handoff_result
        assert err.support_state == PynqSupportState.NOT_DEPLOYABLE
        assert PynqRejectionReason.BOARD_UNREACHABLE in err.runtime_rejections

    def test_raises_on_os_error(self) -> None:
        client = _MockClient(deploy_exc=OSError("Network unreachable"))

        with pytest.raises(PynqHandoffRejectedError) as exc_info:
            map_pynq_artifact_to_deploy_request(
                artifact=_make_artifact(),
                export_result=_exportable_result(),
                endpoint_config=_default_endpoint(),
                client=client,
            )

        err = exc_info.value.handoff_result
        assert PynqRejectionReason.BOARD_UNREACHABLE in err.runtime_rejections

    def test_status_unreachable_raises(self) -> None:
        client = _MockClient(
            deploy_response={"status": "success"},
            status_exc=urllib.error.URLError("Connection refused"),
        )

        with pytest.raises(PynqHandoffRejectedError) as exc_info:
            map_pynq_artifact_to_deploy_request(
                artifact=_make_artifact(),
                export_result=_exportable_result(),
                endpoint_config=_default_endpoint(),
                client=client,
            )

        err = exc_info.value.handoff_result
        assert err.support_state == PynqSupportState.NOT_DEPLOYABLE
        assert PynqRejectionReason.BOARD_UNREACHABLE in err.runtime_rejections


# ---------------------------------------------------------------------------
# TestExportGate
# ---------------------------------------------------------------------------


class TestExportGate:
    """NOT_EXPORTABLE network raises before any HTTP call."""

    def test_not_exportable_raises_immediately(self) -> None:
        client = _MockClient()

        with pytest.raises(PynqHandoffRejectedError) as exc_info:
            map_pynq_artifact_to_deploy_request(
                artifact=_make_artifact(),
                export_result=_not_exportable_result(),
                endpoint_config=_default_endpoint(),
                client=client,
            )

        assert client.deploy_calls == []
        assert client.status_calls == []

    def test_not_exportable_state_in_result(self) -> None:
        client = _MockClient()

        with pytest.raises(PynqHandoffRejectedError) as exc_info:
            map_pynq_artifact_to_deploy_request(
                artifact=_make_artifact(),
                export_result=_not_exportable_result(),
                endpoint_config=_default_endpoint(),
                client=client,
            )

        err = exc_info.value.handoff_result
        assert err.support_state == PynqSupportState.NOT_EXPORTABLE
        assert err.deploy_payload is None

    def test_error_message_contains_rejection(self) -> None:
        client = _MockClient()

        with pytest.raises(PynqHandoffRejectedError) as exc_info:
            map_pynq_artifact_to_deploy_request(
                artifact=_make_artifact(),
                export_result=_not_exportable_result(),
                endpoint_config=_default_endpoint(),
                client=client,
            )

        assert "exceeds_neuron_capacity" in str(exc_info.value)


# ---------------------------------------------------------------------------
# TestStatusMismatch
# ---------------------------------------------------------------------------


class TestStatusMismatch:
    """Non-'configured' backend state after deploy → NOT_DEPLOYABLE."""

    @pytest.mark.parametrize("state", ["not_initialised", "loaded", "running", "error"])
    def test_bad_status_raises(self, state: str) -> None:
        client = _MockClient(
            deploy_response={"status": "success"},
            status_response={"state": state},
        )

        with pytest.raises(PynqHandoffRejectedError) as exc_info:
            map_pynq_artifact_to_deploy_request(
                artifact=_make_artifact(),
                export_result=_exportable_result(),
                endpoint_config=_default_endpoint(),
                client=client,
            )

        err = exc_info.value.handoff_result
        assert err.support_state == PynqSupportState.NOT_DEPLOYABLE
        assert PynqRejectionReason.OVERLAY_LOAD_FAILURE in err.runtime_rejections

    def test_status_response_preserved_on_mismatch(self) -> None:
        status_resp = {"state": "loaded", "bitstream_path": "snn_overlay.bit"}
        client = _MockClient(status_response=status_resp)

        with pytest.raises(PynqHandoffRejectedError) as exc_info:
            map_pynq_artifact_to_deploy_request(
                artifact=_make_artifact(),
                export_result=_exportable_result(),
                endpoint_config=_default_endpoint(),
                client=client,
            )

        assert exc_info.value.handoff_result.status_response == status_resp


# ---------------------------------------------------------------------------
# TestDeterminism
# ---------------------------------------------------------------------------


class TestDeterminism:
    """Repeated calls on the same artifact produce identical payloads."""

    def test_weights_order_is_stable(self) -> None:
        artifact = _make_artifact(n_connections=5)
        endpoint = _default_endpoint()

        payload_a = _build_deploy_payload(artifact, endpoint)
        payload_b = _build_deploy_payload(artifact, endpoint)

        assert payload_a["weights"] == payload_b["weights"]

    def test_full_handoff_payload_is_stable(self) -> None:
        artifact = _make_artifact(n_connections=3)
        export_result = _exportable_result()
        endpoint = _default_endpoint()

        client_a = _MockClient()
        result_a = map_pynq_artifact_to_deploy_request(
            artifact=artifact,
            export_result=export_result,
            endpoint_config=endpoint,
            client=client_a,
        )

        client_b = _MockClient()
        result_b = map_pynq_artifact_to_deploy_request(
            artifact=artifact,
            export_result=export_result,
            endpoint_config=endpoint,
            client=client_b,
        )

        assert result_a.deploy_payload == result_b.deploy_payload


# ---------------------------------------------------------------------------
# TestCustomEndpointConfig
# ---------------------------------------------------------------------------


class TestCustomEndpointConfig:
    """Non-default URL and API key are respected."""

    def test_deploy_url_uses_base_url(self) -> None:
        client = _MockClient()
        endpoint = NeurochipEndpointConfig(
            base_url="http://198.51.100.50:8080",
            bitstream_path="custom.bit",
        )
        map_pynq_artifact_to_deploy_request(
            artifact=_make_artifact(),
            export_result=_exportable_result(),
            endpoint_config=endpoint,
            client=client,
        )

        assert (
            client.deploy_calls[0]["url"]
            == "http://198.51.100.50:8080/hardware/pynq/deploy"
        )
        assert client.status_calls[0] == "http://198.51.100.50:8080/hardware/pynq/status"

    def test_api_key_header_forwarded(self) -> None:
        """API key is included in the client call headers."""
        from neurocnl.handoff.neurochip_pynq_handoff import _build_deploy_headers

        endpoint = NeurochipEndpointConfig(
            base_url="http://board:8000",
            api_key="secret-token-123",
        )
        headers = _build_deploy_headers(endpoint)

        assert headers.get("X-API-Key") == "secret-token-123"

    def test_no_api_key_yields_empty_headers(self) -> None:
        from neurocnl.handoff.neurochip_pynq_handoff import _build_deploy_headers

        endpoint = NeurochipEndpointConfig(base_url="http://board:8000")
        headers = _build_deploy_headers(endpoint)

        assert "X-API-Key" not in headers

    def test_trailing_slash_in_base_url_normalised(self) -> None:
        client = _MockClient()
        endpoint = NeurochipEndpointConfig(base_url="http://board:8000/")
        map_pynq_artifact_to_deploy_request(
            artifact=_make_artifact(),
            export_result=_exportable_result(),
            endpoint_config=endpoint,
            client=client,
        )
        assert not client.deploy_calls[0]["url"].startswith(
            "http://board:8000//hardware"
        )


# ---------------------------------------------------------------------------
# TestClientProtocolCompliance
# ---------------------------------------------------------------------------


class TestClientProtocolCompliance:
    """NeurochipPynqClient is structurally compatible with the protocol."""

    def test_default_client_satisfies_protocol(self) -> None:
        client = NeurochipPynqClient()
        assert isinstance(client, NeurochipPynqClientProtocol)


class TestDeployPayloadLayerDescriptors:
    """Overlay-v2 programs each layer separately, so the payload describes each.

    v1 carried one flat weight list and one global threshold, which is all a
    single-matrix engine could use.
    """

    @staticmethod
    def _chain_artifact() -> PynqRuntimeArtifact:
        populations = [
            PynqPopulationEntry(
                id="a", n_neurons=2, neuron_model="LIF", params={"v_threshold": 1.0}
            ),
            # Thresholds as the quantiser leaves them: already in the engine's
            # units, alongside int8 weights.
            PynqPopulationEntry(
                id="b",
                n_neurons=3,
                neuron_model="LIF",
                params={"v_threshold": 64, "tau_m": 0.008},
            ),
            PynqPopulationEntry(
                id="c",
                n_neurons=1,
                neuron_model="LIF",
                params={"v_threshold": 254, "refractory_steps": 3},
            ),
        ]
        connections = [
            # Deliberately exported out of chain order: b->c first.
            *[PynqConnectionEntry(pre="b", post="c", weight=10) for _ in range(3)],
            *[PynqConnectionEntry(pre="a", post="b", weight=5) for _ in range(6)],
        ]
        overlay_config = PynqOverlayConfigContract(
            network_name="chain",
            populations=populations,
            connections=connections,
            quantisation=PynqQuantisationInfo(bits=8, scale_factor=127.0),
        )
        register_map = PynqRegisterMap()
        return PynqRuntimeArtifact(
            overlay_manifest=PynqOverlayManifestContract(register_map=register_map),
            overlay_config=overlay_config,
            register_map=register_map,
            weight_bit_width=8,
            weights_checksum_sha256=hashlib.sha256(b"w").hexdigest(),
            manifest_checksum_sha256=hashlib.sha256(b"m").hexdigest(),
            total_neurons=6,
            total_synapses=9,
        )

    def test_layers_are_emitted_in_chain_order(self) -> None:
        payload = build_pynq_deploy_payload(self._chain_artifact())

        assert [(layer["source"], layer["target"]) for layer in payload["layers"]] == [
            ("a", "b"),
            ("b", "c"),
        ]

    def test_weight_offsets_address_contiguous_blocks(self) -> None:
        payload = build_pynq_deploy_payload(self._chain_artifact())
        first, second = payload["layers"]

        assert first["weight_offset"] == 0
        assert second["weight_offset"] == first["input_size"] * first["output_size"]
        # Weights are reordered to match, so an offset always addresses its own
        # matrix even when the export order differed.
        assert payload["weights"][: second["weight_offset"]] == [5.0] * 6
        assert payload["weights"][second["weight_offset"] :] == [10.0] * 3

    def test_layer_sizes_come_from_the_populations(self) -> None:
        payload = build_pynq_deploy_payload(self._chain_artifact())
        first, second = payload["layers"]

        assert (first["input_size"], first["output_size"]) == (2, 3)
        assert (second["input_size"], second["output_size"]) == (3, 1)

    def test_thresholds_are_retuned_for_the_leak_the_fabric_can_apply(self) -> None:
        payload = build_pynq_deploy_payload(self._chain_artifact())
        first, second = payload["layers"]

        # The quantiser left 64 and the engine's decay is 1 - 2**-6, so the
        # threshold moves by 2**6 to keep the firing point where the model put
        # it. See `hardware_threshold`.
        assert first["threshold"] == 64 * 2**6
        # No tau means a pure integrator: nothing to compensate for.
        assert second["threshold"] == 254

    def test_a_threshold_is_never_scaled_twice(self) -> None:
        """The defect that made every MNIST run on real silicon return silence.

        `quantise_network_dict` scales thresholds by the same factor as the
        weights, and this used to scale them again — squaring them. For a
        784-input layer the accumulator tops out at 784 x 127 = 99,568, so a
        threshold of 4,129,161 could not be reached by any input, and the board
        returned a full-length frame of zeros that looked like a working run.
        """
        artifact = self._chain_artifact()
        scale = artifact.overlay_config.quantisation.scale_factor
        payload = build_pynq_deploy_payload(artifact)

        for layer in payload["layers"]:
            # Reachable at all: the accumulator saturates at fan-in x 127 per
            # step, and the leak caps the steady state at 2**shift times that.
            reachable = layer["input_size"] * 127 * 2 ** max(layer["leak_shift"], 0)
            assert (
                layer["threshold"] <= reachable
            ), f"{layer['source']} -> {layer['target']} cannot reach its own threshold"
            assert layer["threshold"] < scale * scale

    def test_the_exporter_s_tau_name_produces_a_leak(self) -> None:
        """`pynq_exporter` writes `tau_rc`; reading only `tau_m` meant no leak."""
        populations = [
            PynqPopulationEntry(
                id="a", n_neurons=2, neuron_model="LIF", params={"v_threshold": 1}
            ),
            PynqPopulationEntry(
                id="b",
                n_neurons=2,
                neuron_model="LIF",
                params={"v_threshold": 1, "tau_rc": 0.008},
            ),
        ]
        overlay_config = PynqOverlayConfigContract(
            network_name="leaky",
            populations=populations,
            connections=[
                PynqConnectionEntry(pre="a", post="b", weight=1) for _ in range(4)
            ],
            quantisation=PynqQuantisationInfo(bits=8, scale_factor=127.0),
        )
        register_map = PynqRegisterMap()
        artifact = PynqRuntimeArtifact(
            overlay_manifest=PynqOverlayManifestContract(register_map=register_map),
            overlay_config=overlay_config,
            register_map=register_map,
            weight_bit_width=8,
            weights_checksum_sha256=hashlib.sha256(b"w").hexdigest(),
            manifest_checksum_sha256=hashlib.sha256(b"m").hexdigest(),
            total_neurons=4,
            total_synapses=4,
        )

        payload = build_pynq_deploy_payload(artifact)

        # 8 ms against the 0.1 ms timestep the model is trained under.
        assert payload["layers"][0]["leak_shift"] == 6

    def test_tau_becomes_a_leak_shift(self) -> None:
        payload = build_pynq_deploy_payload(self._chain_artifact())
        first, second = payload["layers"]

        # The decay has to be the one the network was trained with, so the
        # timestep is snnTorch's 0.1 ms for a NIR LIF, not the overlay's 1 ms
        # wall-clock step: 8 ms of tau is a shift of 6, not 3.
        assert first["leak_shift"] == 6
        # No tau at all means no leak.
        assert second["leak_shift"] == 0

    def test_refractory_steps_are_carried_through(self) -> None:
        payload = build_pynq_deploy_payload(self._chain_artifact())
        first, second = payload["layers"]

        assert first["refractory"] == 0
        assert second["refractory"] == 3

    def test_branching_topology_is_refused(self) -> None:
        artifact = self._chain_artifact()
        branching = artifact.overlay_config.model_copy(
            update={
                "connections": [
                    PynqConnectionEntry(pre="a", post="b", weight=1),
                    PynqConnectionEntry(pre="a", post="c", weight=1),
                ]
            }
        )
        with pytest.raises(ValueError, match="feedforward chain"):
            build_pynq_deploy_payload(
                artifact.model_copy(update={"overlay_config": branching})
            )


class TestLeakShiftForTau:
    def test_no_tau_means_no_leak(self) -> None:
        assert leak_shift_for_tau(None) == 0
        assert leak_shift_for_tau(0.0) == 0

    def test_tau_below_a_timestep_means_no_leak(self) -> None:
        assert leak_shift_for_tau(0.0005) == 0

    def test_shift_tracks_log2_of_the_ratio(self) -> None:
        assert leak_shift_for_tau(0.002) == 1
        assert leak_shift_for_tau(0.004) == 2
        assert leak_shift_for_tau(0.016) == 4

    def test_shift_is_clamped_to_the_engine_range(self) -> None:
        assert leak_shift_for_tau(1e9) == 31
