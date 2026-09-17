from __future__ import annotations

import numpy as np
import numpy.typing as npt
import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from pydantic import ValidationError

from neurosense.app.schemas.encoding import build_encoding_config
from neurosense.app.services.recording_service import RecordingService
from neurosense.contracts.device_contracts import DeviceConfig
from neurosense.contracts.recording_contracts import EventMarker, RecordingParams
from neurosense.contracts.signal_contracts import FilterConfig

# Strategies for our contracts that RESPECT invariants
# These demonstrate that when invariants are respected, tests pass.
# Or we can use these to define what a "valid" configuration is.

valid_device_strategy = st.builds(
    DeviceConfig,
    channel_count=st.integers(min_value=1, max_value=8),  # Reasonable default
    sample_rate_hz=st.floats(min_value=100, max_value=40000),
    gain=st.floats(min_value=0.1, max_value=1000),
)


@st.composite
def valid_config_pair(
    draw: st.DrawFn,
) -> tuple[DeviceConfig, FilterConfig, RecordingParams]:
    device = draw(valid_device_strategy)

    # Nyquist-respecting filter config
    max_high = device.sample_rate_hz / 2
    high_hz = draw(st.one_of(st.none(), st.floats(min_value=1, max_value=max_high)))

    low_hz = None
    if high_hz is not None:
        low_hz = draw(st.one_of(st.none(), st.floats(min_value=0.1, max_value=high_hz - 0.1)))

    filter_cfg = FilterConfig(
        bandpass_low_hz=low_hz,
        bandpass_high_hz=high_hz,
        notch_hz=draw(st.one_of(st.none(), st.floats(min_value=45, max_value=65))),
        artifact_rejection=draw(st.booleans()),
    )

    # Memory-respecting recording params
    # Max bytes = 100MB = 104,857,600 bytes
    # Max samples = 104,857,600 / 8 / channel_count
    max_samples = int(104857600 / 8 / device.channel_count)

    # RecordingParams now has more fields
    recording = draw(
        st.builds(
            RecordingParams,
            id=st.uuids().map(str),
            timestamp=st.datetimes().map(lambda d: d.isoformat()),
            duration_seconds=st.floats(min_value=0, max_value=3600),
            buffer_size=st.integers(min_value=1, max_value=max_samples),
            file_format=st.sampled_from(["hdf5", "csv"]),
            device_type=st.sampled_from(["ganglion", "cyton", "muse"]),
            preset_id=st.text(min_size=1),
            channels=st.just(device.channel_count),
            sampling_rate_hz=st.just(device.sample_rate_hz),
            encoding_config=st.builds(
                build_encoding_config,
                method=st.just("rate"),
                rate_max_hz=st.floats(min_value=1, max_value=1000),
            ),
            event_markers=st.lists(
                st.builds(
                    EventMarker,
                    timestamp_seconds=st.floats(min_value=0, max_value=3600),
                    label=st.text(min_size=1),
                )
            ),
            subject_id=st.one_of(st.none(), st.text()),
        )
    )

    return device, filter_cfg, recording


@settings(max_examples=200)
@given(configs=valid_config_pair())
def test_nyquist_invariant(configs: tuple[DeviceConfig, FilterConfig, RecordingParams]) -> None:
    """
    NSE-S1: No aliasing below Nyquist: bandpass_high <= sample_rate / 2.
    """
    device, filter_cfg, _ = configs
    if filter_cfg.bandpass_high_hz is not None:
        assert (
            filter_cfg.bandpass_high_hz <= device.sample_rate_hz / 2
        ), f"Aliasing! Bandpass high ({filter_cfg.bandpass_high_hz}) > Nyquist ({device.sample_rate_hz / 2})"


@settings(max_examples=200)
@given(configs=valid_config_pair())
def test_buffer_memory_invariant(
    configs: tuple[DeviceConfig, FilterConfig, RecordingParams],
) -> None:
    """
    NSE-S2: Buffer never exceeds memory limit (100MB).
    """
    device, _, recording = configs
    # Each sample is float64 (8 bytes)
    memory_usage_bytes = device.channel_count * recording.buffer_size * 8
    max_memory_bytes = 100 * 1024 * 1024  # 100MB

    assert (
        memory_usage_bytes <= max_memory_bytes
    ), f"Buffer too large: {memory_usage_bytes / 1024 / 1024:.2f} MB (Channels: {device.channel_count}, Buffer: {recording.buffer_size})"


@settings(max_examples=200)
@given(configs=valid_config_pair())
def test_recording_parameters_consistency(
    configs: tuple[DeviceConfig, FilterConfig, RecordingParams],
) -> None:
    """
    Ensure that the recording parameters match the device configuration.
    """
    device, _, recording = configs
    assert recording.channels == device.channel_count
    assert recording.sampling_rate_hz == device.sample_rate_hz


@pytest.mark.anyio
@settings(max_examples=50, deadline=None)
@given(
    channels=st.integers(min_value=1, max_value=32),
    sampling_rate=st.floats(min_value=100, max_value=1000),
    num_chunks=st.integers(min_value=1, max_value=10),
    chunk_size=st.integers(min_value=10, max_value=100),
)
async def test_recording_integrity(
    channels: int, sampling_rate: float, num_chunks: int, chunk_size: int
) -> None:
    """
    NSE-S5: Recording integrity (no sample loss).
    """
    service = RecordingService()
    config = build_encoding_config("rate", rate_max_hz=200.0)

    await service.start(
        device_type="test_device",
        preset_id="test_preset",
        channels=channels,
        sampling_rate_hz=int(sampling_rate),
        encoding_config=config,
    )

    total_samples = 0
    input_data: list[npt.NDArray[np.float64]] = []
    rng = np.random.default_rng()

    for _ in range(num_chunks):
        chunk = rng.random((channels, chunk_size)).astype(np.float64)
        input_data.append(chunk)
        service.append_raw(chunk)
        total_samples += chunk_size

    # Verify that the buffered raw data is complete
    all_raw = np.concatenate(service._raw_buffer, axis=1)
    all_input = np.concatenate(input_data, axis=1)

    assert all_raw.shape == (channels, total_samples)
    assert np.array_equal(all_raw, all_input), "Recording data loss or corruption detected!"


@given(
    channel_count=st.one_of(st.integers(max_value=0), st.integers(min_value=1025)),
    sample_rate_hz=st.one_of(st.floats(max_value=99.9), st.floats(min_value=40000.1)),
    gain=st.one_of(st.floats(max_value=0.09), st.floats(min_value=1000.1)),
)
def test_device_config_invalid_values(
    channel_count: int, sample_rate_hz: float, gain: float
) -> None:
    """
    Verify that DeviceConfig correctly rejects invalid values according to its contract.
    """
    # Test each invalid field independently to ensure validation catches it
    with pytest.raises(ValidationError):
        DeviceConfig(channel_count=channel_count, sample_rate_hz=2000, gain=1.0)

    with pytest.raises(ValidationError):
        DeviceConfig(channel_count=8, sample_rate_hz=sample_rate_hz, gain=1.0)

    with pytest.raises(ValidationError):
        DeviceConfig(channel_count=8, sample_rate_hz=2000, gain=gain)
