# OpenBCI Cyton Acceptance Runbook

## Overview
This runbook describes the procedure to validate the hardware bridge with a real OpenBCI Cyton board. This establishes OpenBCI Cyton as the primary supported acquisition target for NeuroSense.

## Procedure
1. Connect the OpenBCI Cyton dongle to your computer.
2. Turn on the Cyton board.
3. Run the validation script: `python -m neurosense.tests.validate_hardware` (do not use `--mock`).
4. Verify the script runs successfully without errors.

## Reproducible Sample Data
Recorded data from a valid Cyton session is stored in `neurosense/tests/fixtures/cyton_sample.hdf5` for unit testing and reproducibility.
