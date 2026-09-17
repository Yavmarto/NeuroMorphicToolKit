# Deploying your first SNN to hardware

This guide will walk you through the process of deploying a Spiking Neural Network (SNN) model to hardware using the NeuroChip toolkit.

## Prerequisites

- A trained SNN model (e.g., in Nengo or CNL format).
- Access to a supported hardware target (e.g., Teensy 4.1, Intel Loihi 2).
- Necessary drivers and toolchains installed (e.g., PlatformIO for Teensy, NxSDK for Loihi).

## Step-by-Step Deployment

### 1. Select Your Target Hardware
Open the NeuroChip dashboard and select your target platform from the **Gallery**. Consider the neuron capacity, power envelope, and weight bit-width of each target.

### 2. Load Your Model
Upload your network specification (CNL or Nengo export) to the **Analysis** screen.

### 3. Run Constraint Analysis
NeuroChip will automatically compare your network against the target's hardware profile.
- **Green**: Compatible.
- **Yellow**: Requires modification (e.g., weight quantization).
- **Red**: Incompatible (e.g., exceeds neuron capacity).

### 4. Quantize Weights (If Necessary)
If your target requires lower bit-widths (e.g., 8-bit for Teensy, 4-bit for Akida), use the **Quantization Explorer** to find the best balance between memory reduction and accuracy loss. Aim for less than 25% accuracy loss.

### 5. Generate Firmware/Deployment Package
- **Teensy 4.1**: Click "Generate Firmware" to download a PlatformIO project.
- **Loihi 2**: Click "Export for Loihi" to generate an NxSDK-compatible Python package.

### 6. Flash to Device
For Teensy, connect your device via USB and use the "Flash to Device" tool within NeuroChip. Ensure the correct serial port is selected.

### 7. Monitor and Verify
Once flashed, monitor the output to verify that the network is running as expected on the physical hardware.
