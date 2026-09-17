# Changelog

All notable changes to the NeuroSense project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-15

### Added

- Initial release of the NeuroSense toolkit.
- Device management support for OpenBCI Ganglion, Cyton, Muse 2/S, BITalino, and synthetic boards via BrainFlow.
- Live multi-channel signal viewer with configurable bandpass and notch filters.
- Real-time spike encoding with rate, temporal, and delta encoding methods.
- Session recording in HDF5 format with event markers.
- Session playback and replay for offline analysis.
- Signal quality dashboard with SNR, noise floor, and impedance metrics.
- Application presets for EMG, EEG, and EOG use cases.
- Integration with the `neurocnl` simulation pipeline.
- Export functionality for spike-encoded data in HDF5, CSV, and NIR formats.
- Flutter-based web frontend for an intuitive user experience.
