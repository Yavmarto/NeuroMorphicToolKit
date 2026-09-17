"""Tests for the shared Akida deployment contract."""

import pytest
from pydantic import ValidationError

from neurocnl.contracts.akida_deployment_contract import (
    AKIDA_LIMITS,
    AkidaExportResult,
    AkidaRejectionReason,
    AkidaSdkStatus,
    AkidaSupportState,
    format_akida_rejection,
)
from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR
from neurocnl.planner import plan_akida_exportability


def test_akida_export_result_is_fail_closed() -> None:
    with pytest.raises(ValidationError):
        AkidaExportResult(
            support_state=AkidaSupportState.EXPORTABLE_SCAFFOLD,
            akida_version="akida1",
            rejections=[AkidaRejectionReason.UNSUPPORTED_TOPOLOGY],
        )


def test_akida_export_result_requires_sdk_status_for_sdk_deployable() -> None:
    with pytest.raises(ValidationError):
        AkidaExportResult(
            support_state=AkidaSupportState.SDK_DEPLOYABLE,
            akida_version="akida2",
        )


def test_akida_export_result_accepts_sdk_deployable_shape() -> None:
    result = AkidaExportResult(
        support_state=AkidaSupportState.SDK_DEPLOYABLE,
        akida_version="akida2",
        sdk_status=AkidaSdkStatus.DEPLOYABLE,
    )
    assert result.sdk_status == AkidaSdkStatus.DEPLOYABLE


def _mnist_fcn_ir(hidden: int) -> NetworkIR:
    return NetworkIR(
        populations={
            "inp": PopulationIR(
                name="inp",
                size=784,
                shape=(784,),
                role="input",
                population_type="input",
            ),
            "lif1": PopulationIR(name="lif1", size=hidden, population_type="lif"),
            "lif2": PopulationIR(name="lif2", size=10, population_type="lif"),
            "out": PopulationIR(
                name="out",
                size=10,
                shape=(10,),
                role="output",
                population_type="output",
            ),
        },
        connections=[
            ConnectionIR("inp", "lif1", weight=1.0),
            ConnectionIR("lif1", "lif2", weight=1.0),
            ConnectionIR("lif2", "out", weight=1.0),
        ],
    )


def _shd_fcn_ir(hidden: int) -> NetworkIR:
    return NetworkIR(
        populations={
            "inp": PopulationIR(
                name="inp",
                size=700,
                shape=(700,),
                role="input",
                population_type="input",
            ),
            "lif1": PopulationIR(name="lif1", size=hidden, population_type="lif"),
            "lif2": PopulationIR(name="lif2", size=20, population_type="lif"),
            "out": PopulationIR(
                name="out",
                size=20,
                shape=(20,),
                role="output",
                population_type="output",
            ),
        },
        connections=[
            ConnectionIR("inp", "lif1", weight=1.0),
            ConnectionIR("lif1", "lif2", weight=1.0),
            ConnectionIR("lif2", "out", weight=1.0),
        ],
    )


def test_guide_shd_topology_is_exportable() -> None:
    """700 -> 128 -> 20 is the Akida-variant SHD template; it must pass."""
    result = plan_akida_exportability(_shd_fcn_ir(128), akida_version="akida1")
    assert result.support_state == AkidaSupportState.EXPORTABLE_SCAFFOLD
    assert result.rejections == []
    assert result.topology_verdict == "faithful"


def test_shd_cochlea_width_exceeds_np_size() -> None:
    """The full-fidelity template's 700-neuron cochlea stage must never pass:
    a regression guard against ever believing it is Akida-exportable."""
    result = plan_akida_exportability(_shd_fcn_ir(700), akida_version="akida1")
    assert result.rejections == [AkidaRejectionReason.EXCEEDS_NP_SIZE]

    (message,) = result.rejection_messages()
    assert "lif1" in message
    assert "700" in message
    assert str(AKIDA_LIMITS.MAX_NEURONS_PER_NP) in message


def _ntidigits_fcn_ir(hidden: int) -> NetworkIR:
    return NetworkIR(
        populations={
            "inp": PopulationIR(
                name="inp",
                size=64,
                shape=(64,),
                role="input",
                population_type="input",
            ),
            "lif1": PopulationIR(name="lif1", size=hidden, population_type="lif"),
            "lif2": PopulationIR(name="lif2", size=11, population_type="lif"),
            "out": PopulationIR(
                name="out",
                size=11,
                shape=(11,),
                role="output",
                population_type="output",
            ),
        },
        connections=[
            ConnectionIR("inp", "lif1", weight=1.0),
            ConnectionIR("lif1", "lif2", weight=1.0),
            ConnectionIR("lif2", "out", weight=1.0),
        ],
    )


def test_guide_ntidigits_topology_is_exportable() -> None:
    """64 -> 64 -> 11 is the N-TIDIGITS template; both channel counts already
    fit under 256, so unlike SHD it needs no separate Akida-sized variant."""
    result = plan_akida_exportability(_ntidigits_fcn_ir(64), akida_version="akida1")
    assert result.support_state == AkidaSupportState.EXPORTABLE_SCAFFOLD
    assert result.rejections == []
    assert result.topology_verdict == "faithful"


def test_every_rejection_reason_has_a_template() -> None:
    """A missing template would silently fall back to the bare code."""
    for reason in AkidaRejectionReason:
        message = format_akida_rejection(reason, {})
        assert reason.value not in message, reason


def test_format_akida_rejection_never_raises_on_missing_details() -> None:
    message = format_akida_rejection(AkidaRejectionReason.EXCEEDS_NP_SIZE, {})
    assert "<population>" in message


def test_guide_mnist_topology_is_exportable() -> None:
    """784 -> 256 -> 10 is the guide's Akida-ready canvas; it must pass."""
    result = plan_akida_exportability(_mnist_fcn_ir(256), akida_version="akida1")
    assert result.support_state == AkidaSupportState.EXPORTABLE_SCAFFOLD
    assert result.rejections == []
    assert result.topology_verdict == "faithful"


def test_oversized_layer_reports_one_actionable_rejection() -> None:
    result = plan_akida_exportability(_mnist_fcn_ir(1000), akida_version="akida1")

    # One cause, one code: the same 256 check also drives the topology verdict,
    # and reporting UNSUPPORTED_TOPOLOGY too hid which code was actionable.
    assert result.rejections == [AkidaRejectionReason.EXCEEDS_NP_SIZE]

    (message,) = result.rejection_messages()
    assert "lif1" in message
    assert "1000" in message
    assert str(AKIDA_LIMITS.MAX_NEURONS_PER_NP) in message
    assert "Neurons" in message


def test_rejection_messages_are_never_bare_enum_codes() -> None:
    """Regression guard: the endpoint used to return r.value verbatim."""
    result = plan_akida_exportability(_mnist_fcn_ir(1000), akida_version="akida1")
    codes = {reason.value for reason in AkidaRejectionReason}
    assert not codes.intersection(result.rejection_messages())


def test_unsupported_topology_names_the_offending_structure() -> None:
    ir = _mnist_fcn_ir(64)
    ir.populations["lif3"] = PopulationIR(name="lif3", size=10, population_type="lif")
    ir.connections.append(ConnectionIR("lif1", "lif3", weight=1.0))

    result = plan_akida_exportability(ir, akida_version="akida1")
    assert result.rejections == [AkidaRejectionReason.UNSUPPORTED_TOPOLOGY]

    (message,) = result.rejection_messages()
    assert "lif1" in message
    assert "Akida 1" in message
