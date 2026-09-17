from __future__ import annotations

from pathlib import Path

import numpy as np
import numpy.typing as npt
import pytest

from neurosense.app.schemas.encoding import EncodingConfig, build_encoding_config
from neurosense.app.schemas.presets import FilterConfig


@pytest.fixture
def sample_signal() -> npt.NDArray[np.float64]:
    """Generates a sample 2-channel signal: 10Hz sine wave + noise."""
    fs = 250.0
    rng = np.random.default_rng(42)
    t = np.linspace(0, 1, int(fs), endpoint=False)
    ch1 = np.sin(2 * np.pi * 10 * t) + 0.1 * rng.standard_normal(len(t))
    ch2 = 0.5 * np.sin(2 * np.pi * 10 * t) + 0.1 * rng.standard_normal(len(t))
    return np.array([ch1, ch2])


@pytest.fixture
def rate_encoding_config() -> EncodingConfig:
    return build_encoding_config("rate", rate_max_hz=200.0)


@pytest.fixture
def temporal_encoding_config() -> EncodingConfig:
    return build_encoding_config("temporal", temporal_phase_bins=8)


@pytest.fixture
def delta_encoding_config() -> EncodingConfig:
    return build_encoding_config("delta", delta_threshold=0.5)


@pytest.fixture
def filter_config() -> FilterConfig:
    return FilterConfig(
        bandpass_low_hz=1.0, bandpass_high_hz=40.0, notch_hz=50.0, artifact_rejection=True
    )


@pytest.fixture
def session_fixture_dir() -> Path:
    return Path(__file__).parent / "fixtures"


@pytest.fixture
def canonical_session_id() -> str:
    return "canonical_emg_session"


@pytest.fixture
def canonical_session_path(session_fixture_dir: Path, canonical_session_id: str) -> Path:
    return session_fixture_dir / f"{canonical_session_id}.hdf5"
