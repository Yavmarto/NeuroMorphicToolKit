# 04: Simulation and Monitoring

Before deploying a neuromorphic model to physical hardware, it is critical to verify its behavior in simulation. CNLStudio provides an integrated simulator powered by the backend Neural Intermediate Representation (NIR) engine.

## Simulator Panel

The **Simulator Panel** provides the controls to execute and manage a network simulation.
- **Controls:** Features Play/Pause/Stop buttons.
- **Duration:** You can set the simulation duration (e.g., 1.0 seconds).
- **Execution:** Clicking 'Run' pushes the compiled NIR graph to the backend simulator (e.g., Norse or snnTorch). The status is reflected in the Pipeline Bar at the bottom.

## Simulation Dashboard

Once a simulation is running or completed, the **Simulation Dashboard** becomes your primary view for observing the network's dynamics.

### Sensor Time Series Chart
- **Visual:** A line chart plotting activity over time.
- **Content:** It displays spike rasters, membrane potentials, or external sensor inputs (if connected to a simulator stream like MuJoCo).
- **Usage:** Use this chart to verify that your populations are spiking as expected in response to stimuli.

### Energy Bar Chart
- **Visual:** A bar or pie chart detailing power metrics.
- **Content:** It provides an *estimated* energy profile of the network. Neuromorphic hardware derives its efficiency from sparse spiking; this chart estimates the dynamic power consumption based on the spike rates observed during the simulation.
- **Usage:** Optimize your network parameters to minimize spikes while maintaining accuracy to improve the energy score here.

### MuJoCo Stream View
If your network is coupled to a robotic environment, the **MuJoCo Stream View** may appear.
- **Content:** It provides a live telemetry stream or visual render of the simulated robotic agent responding to your network's motor outputs.

## Agent Workflows
- **Agent Note:** Agents must use the `simulationProvider` to trigger runs. After completion, agents should parse the JSON telemetry returned from the backend rather than attempting to read the visual charts to evaluate network fitness.

---
*Next:* Read `05_Hardware_Deployment.md` to learn how to deploy your validated model to edge devices.
