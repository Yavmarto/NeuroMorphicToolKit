import pytest
from pydantic import ValidationError

from neurosense.app.schemas.encoding import build_encoding_config
from neurosense.contracts.device_contracts import DeviceConfig
from neurosense.contracts.encoding_contracts import EncodingConfig
from neurosense.contracts.performance_contracts import (
    DisplayLatencyContract,
    PipelineLatencyContract,
)
from neurosense.contracts.recording_contracts import RecordingParams


def test_device_config_valid() -> None:
    config = DeviceConfig(channel_count=8, sample_rate_hz=1000, gain=1.0)
    assert config.channel_count == 8
    assert config.sample_rate_hz == 1000
    assert config.gain == 1.0


def test_device_config_invalid_channel_count() -> None:
    with pytest.raises(ValidationError):
        DeviceConfig(channel_count=0, sample_rate_hz=1000, gain=1.0)
    with pytest.raises(ValidationError):
        DeviceConfig(channel_count=1025, sample_rate_hz=1000, gain=1.0)


def test_device_config_invalid_sample_rate() -> None:
    with pytest.raises(ValidationError):
        DeviceConfig(channel_count=8, sample_rate_hz=50, gain=1.0)
    with pytest.raises(ValidationError):
        DeviceConfig(channel_count=8, sample_rate_hz=41000, gain=1.0)


def test_device_config_invalid_gain() -> None:
    with pytest.raises(ValidationError):
        DeviceConfig(channel_count=8, sample_rate_hz=1000, gain=0.05)
    with pytest.raises(ValidationError):
        DeviceConfig(channel_count=8, sample_rate_hz=1000, gain=1001)


def test_recording_params_valid() -> None:
    params = RecordingParams(
        id="test-id",
        timestamp="2026-03-15T14:30:00Z",
        duration_seconds=10.0,
        buffer_size=1024,
        file_format="hdf5",
        device_type="ganglion",
        preset_id="emg_prosthetic",
        channels=8,
        sampling_rate_hz=1000.0,
        encoding_config=build_encoding_config("rate", rate_max_hz=200.0),
        subject_id=None,
        file_path=None,
        file_size_bytes=None,
    )
    assert params.duration_seconds == 10.0
    assert params.buffer_size == 1024
    assert params.file_format == "hdf5"


def test_recording_params_invalid_duration() -> None:
    with pytest.raises(ValidationError):
        RecordingParams(
            id="test-id",
            timestamp="2026-03-15T14:30:00Z",
            duration_seconds=-1.0,
            buffer_size=1024,
            file_format="hdf5",
            device_type="ganglion",
            preset_id="emg_prosthetic",
            channels=8,
            sampling_rate_hz=1000.0,
            encoding_config=build_encoding_config("rate", rate_max_hz=200.0),
            subject_id=None,
            file_path=None,
            file_size_bytes=None,
        )


def test_recording_params_invalid_format() -> None:
    with pytest.raises(ValidationError):
        RecordingParams(
            id="test-id",
            timestamp="2026-03-15T14:30:00Z",
            duration_seconds=10.0,
            buffer_size=1024,
            file_format="txt",  # type: ignore[arg-type]
            device_type="ganglion",
            preset_id="emg_prosthetic",
            channels=8,
            sampling_rate_hz=1000.0,
            encoding_config=build_encoding_config("rate", rate_max_hz=200.0),
            subject_id=None,
            file_path=None,
            file_size_bytes=None,
        )


def test_encoding_config_valid() -> None:
    # Delta encoding requires delta_threshold
    config = build_encoding_config(
        "delta", delta_threshold=5.0, refractory_period=1.0, temporal_resolution=0.1
    )
    assert config.method == "delta"
    assert config.delta_threshold == 5.0
    assert config.refractory_period == 1.0
    assert config.temporal_resolution == 0.1

    # Rate encoding requires rate_max_hz
    config_rate = build_encoding_config("rate", rate_max_hz=200.0, refractory_period=0.005)
    assert config_rate.method == "rate"
    assert config_rate.rate_max_hz == 200.0

    # Temporal encoding requires temporal_phase_bins
    config_temporal = build_encoding_config(
        "temporal", temporal_phase_bins=8, refractory_period=0.002
    )
    assert config_temporal.method == "temporal"
    assert config_temporal.temporal_phase_bins == 8


def test_encoding_config_invalid_refractory_period() -> None:
    with pytest.raises(ValidationError):
        build_encoding_config(
            "delta", delta_threshold=5.0, refractory_period=0, temporal_resolution=0.1
        )
    with pytest.raises(ValidationError):
        build_encoding_config(
            "delta", delta_threshold=5.0, refractory_period=-1.0, temporal_resolution=0.1
        )


def test_encoding_config_missing_method_params() -> None:
    # Missing rate_max_hz for rate
    with pytest.raises(ValidationError):
        EncodingConfig(
            method="rate",
            refractory_period=0.001,
            temporal_resolution=0.001,
            rate_max_hz=None,
            temporal_phase_bins=None,
            delta_threshold=None,
        )
    # Missing temporal_phase_bins for temporal
    with pytest.raises(ValidationError):
        EncodingConfig(
            method="temporal",
            refractory_period=0.001,
            temporal_resolution=0.001,
            rate_max_hz=None,
            temporal_phase_bins=None,
            delta_threshold=None,
        )
    # Missing delta_threshold for delta
    with pytest.raises(ValidationError):
        EncodingConfig(
            method="delta",
            refractory_period=0.001,
            temporal_resolution=0.001,
            rate_max_hz=None,
            temporal_phase_bins=None,
            delta_threshold=None,
        )


def test_display_latency_contract() -> None:
    config = DisplayLatencyContract(latency_ms=45.0)
    assert config.latency_ms == 45.0
    with pytest.raises(ValidationError):
        DisplayLatencyContract(latency_ms=50.0)


def test_pipeline_latency_contract() -> None:
    config = PipelineLatencyContract(latency_ms=95.0)
    assert config.latency_ms == 95.0
    with pytest.raises(ValidationError):
        PipelineLatencyContract(latency_ms=100.0)
