from __future__ import annotations

import numpy as np
import numpy.typing as npt
import pytest

from neurosense.app.schemas.encoding import EncodingConfig
from neurosense.app.services.spike_encoder import SpikeEncoder


def test_rate_encoding(
    sample_signal: npt.NDArray[np.float64], rate_encoding_config: EncodingConfig
) -> None:
    encoder = SpikeEncoder()
    encoder.configure(rate_encoding_config, sampling_rate=250.0)
    result = encoder.encode(sample_signal)

    assert "spike_trains" in result
    assert "spike_counts" in result
    assert result["method"] == "rate"
    assert len(result["spike_trains"]) == sample_signal.shape[0]
    assert len(result["spike_counts"]) == sample_signal.shape[0]


def test_temporal_encoding(
    sample_signal: npt.NDArray[np.float64], temporal_encoding_config: EncodingConfig
) -> None:
    encoder = SpikeEncoder()
    encoder.configure(temporal_encoding_config, sampling_rate=250.0)
    result = encoder.encode(sample_signal)

    assert "spike_trains" in result
    assert "spike_counts" in result
    assert result["method"] == "temporal"
    assert len(result["spike_trains"]) == sample_signal.shape[0]


def test_delta_encoding(
    sample_signal: npt.NDArray[np.float64], delta_encoding_config: EncodingConfig
) -> None:
    encoder = SpikeEncoder()
    encoder.configure(delta_encoding_config, sampling_rate=250.0)
    result = encoder.encode(sample_signal)

    assert "spike_trains" in result
    assert "spike_counts" in result
    assert result["method"] == "delta"
    assert len(result["spike_trains"]) == sample_signal.shape[0]


def test_encode_batch(
    sample_signal: npt.NDArray[np.float64], rate_encoding_config: EncodingConfig
) -> None:
    encoder = SpikeEncoder()
    data_list = sample_signal.tolist()
    result = encoder.encode_batch(data_list, rate_encoding_config, sampling_rate=250.0)

    assert "spike_trains" in result
    assert len(result["spike_trains"]) == len(data_list)


def test_unconfigured_error(sample_signal: npt.NDArray[np.float64]) -> None:
    encoder = SpikeEncoder()
    with pytest.raises(RuntimeError, match="Encoder not configured"):
        encoder.encode(sample_signal)


def test_unknown_method_error(sample_signal: npt.NDArray[np.float64]) -> None:
    encoder = SpikeEncoder()
    # Use patch to bypass Pydantic validation for the unknown method test
    from unittest.mock import MagicMock

    config = MagicMock(spec=EncodingConfig)
    config.method = "invalid"
    encoder.configure(config)
    with pytest.raises(ValueError, match="Unknown encoding method"):
        encoder.encode(sample_signal)
