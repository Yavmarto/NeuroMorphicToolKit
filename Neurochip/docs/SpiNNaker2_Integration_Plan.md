# SpiNNaker2 Hardware Interfacing Plan

## 1. Differences between PyNN-SpiNNaker 1 and py-spinnaker2

The interface for SpiNNaker2 using `py-spinnaker2` represents a significant shift from the previous `sPyNNaker` interface used for SpiNNaker 1. `py-spinnaker2` does not rely on standard PyNN setups, but instead uses a similar custom PyNN-inspired object model defined in the `spinnaker2.snn` namespace.
- **Namespaces**: Rather than `import pyNN.spiNNaker as p`, networks are built using objects from `spinnaker2.snn` like `Population` and `Projection`, and mapped directly onto the chip utilizing `spinnaker2.hardware.SpiNNaker2Chip`.
- **Hardware Connection Layer**: In py-spinnaker2, network simulation is orchestrated by calling `hw.run(net, timesteps)`. This maps the populations to the cores and configures the connection directly. Re-running the identical setup requires using a cached binary or compiling via `hw.run(net, timesteps, make_clean=True)`.
- **Advanced Attributes**: SpiNNaker2 natively supports `record_on_dram` to stream large recordings back seamlessly, and also allows extracting computation telemetry by adding `"time_done"` to the `record` argument.

## 2. SpiNNaker2Backend Service
A new service (`neurochip/app/services/spinnaker2_backend.py`) will be implemented using the `SpiNNaker2Backend` class.

- **Board Discovery & Connection**: Will map through `hardware.SpiNNaker2Chip()`. If no chip is present, we could employ `spinnaker2.brian2_sim` for emulation to ensure graceful degradation. To support specific IP mapping (as of py-spinnaker2 v0.5.0), the application needs to read `SPINNAKER_CONFIG_PATH` to resolve host connections.
- **Network Loading (`compile_network`)**: Network objects passed down from `NetworkInput` will be transformed into `snn.Population` objects. Connections are handled through `snn.Projection`.
- **Run & Retrieve (`run_network`)**: Execution proceeds via `hw.run(net, timesteps)`. Results can be asynchronously fetched or fetched synchronously with methods like `pop.get_spikes()` and `pop.get_voltages()`.

## 3. Partitioning Model
SpiNNaker2 chips possess an explicit multi-core distributed architecture. The compilation step in Neurochip must respect the boundaries of core partitioning:
- When transforming a large `NetworkInput` into `snn.Population` and `snn.Projection`, populations are distributed depending on available RAM and Processing Elements (PEs).
- If a population exceeds the limit for a single core, `spinnaker2` supports chunking parameters. Neurochip will define specific chunking bounds in the backend if `py-spinnaker2` does not auto-partition the SNN implicitly.

## 4. Real-time Monitoring
- **Spike Event Streaming**: Unlike static batch extraction (`get_spikes()`), `py-spinnaker2` allows advanced streaming setups via Host-driven Spike Replicator or Gather and Stream (GAS) modes. We can expose an async generator pulling event pipelines from SpiNNaker2 streaming components and sending them to the frontend over existing Neurochip websockets.

## 5. API Endpoints
A new router module `neurochip/app/routers/spinnaker2.py` will expose:
- `POST /api/neurochip/hardware/spinnaker2/compile`: Transforms standard JSON definition to a deployable configuration package.
- `POST /api/neurochip/hardware/spinnaker2/run`: Connects to hardware, deploys the network via `SpiNNaker2Backend`, executes the run, and returns spikes/voltages.

## 6. Connection Configuration
- **Board IP / Hostname**: As introduced in py-spinnaker2 v0.5.0, a central hardware config must be mapped by `SPINNAKER_CONFIG_PATH`. The API request should map `board_id` optionally to an entry within this config directory, which specifies standard cluster IPs.
- **Partitioning Parameters**: Users can provide optional arguments in the API to specify custom partitioning sizes, overriding `py-spinnaker2`'s default PE allocations.

## 7. Dependency Changes
- Under `[tool.poetry.dependencies]`, we add an optional extra grouping for spinnaker2, containing `py-spinnaker2`.
