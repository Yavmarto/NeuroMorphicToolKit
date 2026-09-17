import pytest

from neurocnl.converter.spinnaker2_io import (
    format_spinnaker2_inputs,
    parse_spinnaker2_outputs,
)


def test_format_spinnaker2_inputs_raises() -> None:
    """format_spinnaker2_inputs must fail closed with a descriptive error."""
    with pytest.raises(NotImplementedError, match="SpiNNaker2 runtime I/O mapping"):
        format_spinnaker2_inputs({})


def test_parse_spinnaker2_outputs_raises() -> None:
    """parse_spinnaker2_outputs must fail closed with a descriptive error."""
    with pytest.raises(NotImplementedError, match="SpiNNaker2 runtime I/O mapping"):
        parse_spinnaker2_outputs({}, {})
