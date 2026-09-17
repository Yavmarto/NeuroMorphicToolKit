# User Guide: Connecting Your First Biosignal Device

Welcome to NeuroSense! This guide will walk you through the process of connecting your biosignal acquisition hardware to the toolkit.

## Prerequisites

- NeuroSense backend and frontend are running.
- Your biosignal device is powered on and within range (for Bluetooth devices) or connected via USB.

## Support Levels

NeuroSense currently distinguishes between what is validated today and what is
still exploratory:

- `validated`: Synthetic BrainFlow acquisition used for fixture-backed
  recording/replay verification
- `experimental`: OpenBCI Cyton, OpenBCI Ganglion, Muse 2 / Muse S, BITalino
- `prototype`: PYNQ and Prophesee-related ingestion paths

For the flagship forearm-EMG workflow, `OpenBCI Cyton` is the default future
real-board target, but it remains `experimental` until a hardware acceptance
script passes without mocks.

Cyton discovery is intentionally configuration-driven. Set
`NEUROSENSE_CYTON_SERIAL_PORT` or use the dedicated acceptance runbook before
expecting Cyton to appear in scan results.

Muse 2 / Muse S discovery is also configuration-driven. Set
`NEUROSENSE_MUSE_MODEL` to `muse2`, `muses`, or `bled` (BLED dongle fallback)
before expecting Muse to appear in scan results. Optional:
`NEUROSENSE_MUSE_MAC_ADDRESS` and `NEUROSENSE_MUSE_PRESET` (default `p21`).
See [Muse acceptance runbook](muse_acceptance_runbook.md).

PiEEG discovery requires a streaming-board relay on the dev host. Set
`NEUROSENSE_PIEEG_STREAM_HOST` (and optionally `NEUROSENSE_PIEEG_STREAM_PORT`)
after the Pi publishes PiEEG data. See
[PiEEG acceptance runbook](pieeg_acceptance_runbook.md).

## Step 1: Discover Devices

1. Open the NMTK launcher app and click the **Neurosense** card in the nav — this opens the native Device Config screen (`/module/neurosense`). There is no separate NeuroSense web application; the UI is embedded directly in the launcher.
2. On the main dashboard, you will see the **Device Selector** at the top.
3. Click the **Refresh** button (circular arrow) to scan for available devices.
4. Any detected hardware will appear in the dropdown list.

## Step 2: Select and Connect

1. Click the dropdown menu in the Device Selector.
2. Select your device from the list.
   - For validated no-hardware exploration, use **Synthetic Testing Board**.
   - For the flagship real-board target, use **OpenBCI Cyton** and treat the
     path as experimental until physical validation is complete.
   - For consumer EEG headbands, use **Muse 2** or **Muse S** once
     `NEUROSENSE_MUSE_MODEL` is configured.
   - For PiEEG on a Raspberry Pi relay, use **PiEEG (ADS1299)** once the
     streaming host is configured.
3. Click the **Connect** button.
4. The status indicator will turn green once the connection is established.

## Step 3: Verify Signal Quality

1. Once connected, look at the **Signal Quality** bar.
2. You should see real-time metrics for each channel (SNR, Noise Floor).
3. If any channel shows a red (unusable) or orange (marginal) indicator, click the **Troubleshooting** button for advice on improving electrode contact.

## Troubleshooting Common Issues

- **Device not found:** Ensure Bluetooth is enabled on your computer or the USB dongle is plugged in.
- **Connection failed:** Make sure no other application is currently using the device (e.g., OpenBCI GUI).
- **Noisy signals:** Check electrode placement and ensure skin is clean and prepped with conductive gel if required.
