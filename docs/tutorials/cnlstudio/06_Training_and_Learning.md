# 06: Training and Learning

Neuromorphic networks can learn and adapt. CNLStudio provides interfaces to trigger and monitor training jobs (like surrogate gradient descent or on-chip learning methods) through the **Training Inspector Panel**.

## Training Inspector Panel

The Training Inspector Panel is a capability-driven interface for submitting networks to various training backends.

### Capabilities and Configuration
- **Backend Selection:** You must first select a Training Backend from the dropdown. Backends are defined by the server (e.g., standard surrogate gradient training, or biologically-inspired methods like `sleep_pes`).
- **Availability:** If a backend is greyed out with a lock icon, the server does not currently have the resources (or the specific hardware accelerators) to run that training mode.
- **Epochs Slider:** Controls how many passes the training algorithm makes over the dataset.
- **Homeostasis Factor:** (Specific to certain learning modes like sleep training) Controls the rate at which neurons adjust their baseline firing thresholds.

### Job Monitoring
Training is an asynchronous, potentially long-running process.
- **Status:** Once submitted, the panel polls the server.
- **Elapsed Time:** A live timer tracks how long the job has been running.
- **Results:** Upon completion, the panel displays a summary including the final loss, duration, and the specific adapter/mode used.

## Execution Flow for Humans & Agents

1. Open the Training Inspector Panel.
2. Ensure the active workspace has a valid, compiled CNL spec.
3. Select an available Training Backend.
4. Adjust the Epochs (e.g., to 10 for a quick test or 50 for full training).
5. Click `Start Training`.
6. Wait for the `success` or `failure` state.
   - If successful, the server automatically updates the backend weights. You can re-simulate the network to observe the improved behavior.

- **Agent Note:** Agents must use `trainingProvider.notifier.submitTraining(...)` with the required payload (`n_epochs`, `dataset`, and the raw `spec`). Agents should poll the `trainingProvider` state until `status == TrainingProviderStatus.success` and read the `state.result` object for `finalLoss`.
