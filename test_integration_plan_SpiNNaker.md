# Test Integration Plan: SpiNNaker 2

## Overview
This document outlines the testing integration plan for **SpiNNaker 2** within the NeuroMorphicToolKit. The integration leverages `py-spinnaker2`, an object-oriented API that explicitly defines `snn.Population` and `snn.Projection` connected to physical cores on the SpiNNaker2 chip, distinguishing it from the older PyNN abstraction layer.

## Usable Tutorials & Examples to Test

### 1. Software Simulation / Brian2 Backend Test
Because access to physical SpiNNaker 2 boards might be restricted, `py-spinnaker2` provides a software simulation fallback utilizing Brian2. 

**What it tests**:
- Evaluates the transcription of NeuroCNL's intermediate `nengo.Network` objects into the target `spinnaker2.snn` graph API format.
- Checks that the custom `spinnaker2_exporter.py` faithfully compiles and translates timing metrics and connections (using the `[pre_idx, post_idx, weight, delay]` format) suitable for SpiNNaker.

**How to run**:
The exporter verification can be tested locally using the dedicated test suite.
```bash
pytest neurocnl/neurocnl/export/test_spinnaker2_exporter.py
```

### 2. Hardware Test Pipeline (Requires SpiNNaker2 Cluster)
To validate execution against the physical board:
1. Ensure the `py-spinnaker2` library is installed natively.
2. Formulate a simple generic reflex network using the provided full-pipeline execution in `neurocnl/examples/04_full_pipeline.py`.
3. In your script or test environment, swap the simulation backend from `nengo.Simulator(net)` to the `spinnaker2.hardware.SpiNNaker2Chip().run(net, timesteps)` exporter path.
4. Retrieve the actual spikes by verifying `pop.get_spikes()` outputs format matches NMTK standards using the `spinnaker2_io.py` converter. 

*Note: Since hardware execution is usually mocked out via `@pytest.mark.hardware`, ensure your execution server is tied to the board cluster before running any CI steps targeting the hardware directly.*

## Official Documentation and External Tutorials

To ensure NMTK's exporter builds valid graph topologies, you can reference the official py-spinnaker2 tutorials:

- **SpiNNaker2 Developer Portal:** [spinnaker2.gitlab.io/](https://spinnaker2.gitlab.io/) (Documentation, guides, and setup instructions)
- **py-spinnaker2 Repository & Tutorials:** Navigate to [gitlab.com/spinnaker2/py-spinnaker2](https://gitlab.com/spinnaker2/py-spinnaker2). Referencing the example scripts here will help you test the `test_spinnaker2_exporter.py` outputs against "gold-standard" PyNN-like scripts designed by the SpiNNaker team.
