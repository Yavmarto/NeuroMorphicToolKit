import time

import numpy as np

from neurosense.app.schemas.presets import FilterConfig
from neurosense.app.services.filter_pipeline import FilterPipeline


def profile_filter_pipeline() -> None:
    pipeline = FilterPipeline()
    config = FilterConfig(
        bandpass_low_hz=1.0, bandpass_high_hz=40.0, notch_hz=50.0, artifact_rejection=True
    )
    sampling_rate = 250.0
    pipeline.configure(config, sampling_rate)

    # 8 channels, 250 samples (1 second of data)
    n_channels = 8
    n_samples = 250
    rng = np.random.default_rng()
    data = rng.standard_normal((n_channels, n_samples))

    # Warm up
    for _ in range(10):
        pipeline.apply(data)

    n_iterations = 1000
    start_time = time.perf_counter()
    for _ in range(n_iterations):
        pipeline.apply(data)
    end_time = time.perf_counter()

    avg_time_ms = (end_time - start_time) / n_iterations * 1000
    print(
        f"Average processing time for {n_channels} channels, {n_samples} samples: {avg_time_ms:.4f} ms"
    )

    # Calculate CPU usage percentage assuming 250Hz sampling rate (4ms per sample)
    # A batch of 250 samples represents 1000ms of real-time data.
    cpu_usage = (avg_time_ms / 1000.0) * 100
    print(f"Estimated CPU usage at 250Hz: {cpu_usage:.2f}%")


if __name__ == "__main__":
    profile_filter_pipeline()
