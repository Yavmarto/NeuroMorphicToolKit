# Changelog

All notable changes to the NeuroChip project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-15

### Added

- **Hardware Targets**: Added support for Teensy 4.1, Intel Loihi 2, BrainChip Akida, SpiNNaker, and BrainScaleS.
- **Constraint Analysis**: Implemented automated compatibility reporting for loaded networks against hardware targets.
- **Quantization Explorer**: Interactive tool for adjusting weight bit-widths and visualizing accuracy impact.
- **Fault Tolerance**: Tooling for injecting hardware faults and analyzing network robustness.
- **Firmware Generation**: One-click generation of C/C++ firmware for Teensy 4.1 and NxSDK deployment packages for Loihi 2.
- **Power & Latency Estimation**: Pre-deployment estimation of energy consumption and worst-case latency.
- **Deployment Log**: Persistence and tracking of deployment history using SQLite.
- **API**: FastAPI-based backend for all core toolkit functions.
- **UI**: Initial Flutter-based web frontend for interacting with the toolkit.

[0.1.0]: https://github.com/neuro-space/NeuroChip/releases/tag/v0.1.0
