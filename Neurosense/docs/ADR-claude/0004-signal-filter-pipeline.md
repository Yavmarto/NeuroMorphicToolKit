# ADR 0004: Signal Filter Pipeline

## Status
Accepted

## Context
Raw biosignals contain noise (50/60 Hz power line interference, motion artifacts, electrode drift) that must be removed before spike encoding to prevent false spike generation and encoding distortion.

## Decision
Implement a `FilterPipeline` class with configurable bandpass and notch filters using SciPy's second-order sections (SOS) for numerical stability. SciPy is lazy-loaded to keep the core module import lightweight. The pipeline follows a configure-then-process two-phase API with coefficient caching across calls.

## Consequences
- **Positive:** SOS filters are numerically stable even for high-order filters; lazy SciPy loading keeps startup fast when filtering is not needed.
- **Negative:** Filter parameter selection (cutoff frequencies, filter order) requires signal processing expertise; coefficient caching assumes stationary filter parameters within a session.
