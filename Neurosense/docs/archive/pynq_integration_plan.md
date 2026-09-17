# PYNQ Z2 — Edge Sensor Data Acquisition Plan

Support level for this path: `prototype`

This document is a design/integration plan. It should not be read as evidence
that PYNQ ingestion is validated hardware-ready today.

## Overview

The PYNQ Z2 FPGA board acts as an edge sensor node, allowing acquisition from
high-bandwidth or custom neuromorphic sensors. This integration plan details
the path to run a lightweight Neurosense FastAPI service on its ARM cores, with
programmable logic (PL) pre-processing.

## 1. PYNQ Z2 ARM Service

The ARM cores on the Zynq-7000 will run a lightweight, PYNQ-specific FastAPI service. This service will:
*   Expose endpoints to list available sensors and start/stop streams.
*   Manage PL bitstream loading via the `pynq.Overlay` class.
*   Handle DMA transfers from the PL to the ARM processor's memory space.
*   Forward the processed spike data to the main Neurosense backend over a network stream.

## 2. Peripheral Interfaces

The PYNQ Z2 exposes several interfaces that can be used to attach sensors:
*   **MIPI CSI-2:** Suitable for neuromorphic DVS (Dynamic Vision Sensor) cameras, providing high-bandwidth event data.
*   **SPI / I2C / I2S:** Suitable for IMUs (Inertial Measurement Units) and microphone arrays.
*   **Pmod / Arduino headers:** Used for custom or lower-speed sensor integration.

## 3. PL-Side Spike Pre-processing

To offload the ARM cores, spike pre-processing will occur in the FPGA Programmable Logic (PL):
*   **Rate Coding / Delta Modulation:** Logic blocks (IP cores) in the PL will convert raw sensor inputs (e.g., analog voltages from custom ADCs or IMU data) into spike trains in real-time.
*   **Event Filtering:** For DVS sensors, the PL can perform spatial or temporal filtering of events before they reach the ARM.

## 4. DMA Pipeline

Data flows from the sensor to the network via a Direct Memory Access (DMA) pipeline:
1.  **Sensor:** Generates raw data or events.
2.  **PL Spike Encoder (IP Core):** Processes the data into spikes or filtered events.
3.  **AXI DMA:** Transfers the processed data streams from the PL directly into allocated contiguous memory buffers in the ARM space using the `pynq.lib.dma` or `pynq.allocate` modules.
4.  **ARM Service:** Reads the buffers and pushes the data over the network stream.

## 5. Network Transport and Reception

The encoded data will be streamed from the PYNQ board to the main Neurosense backend.
*   **Transport Mechanism:** **WebSocket** is selected. It offers native integration with FastAPI (used on both ends), supports two-way real-time communication for control signals and data, and fits well within the existing `neurosense` architecture (which already uses WebSockets for streaming).
*   **Encoding Pipeline:** Neurosense will receive the streamed data via the `pynq_stream_client`. The `PYNQSensorSource` class will ingest the data and feed it into the existing Neurosense encoding/recording pipelines.

## 6. PYNQSensorSource Class

A new `PYNQSensorSource` class will act as the integration point within the Neurosense backend. It will:
*   Manage the network connection (via `PynqStreamClient`) to the remote PYNQ node.
*   Present a standard interface to the rest of the Neurosense backend for retrieving data.
*   Include a simulation mode for offline testing.

## 7. Simulated/Offline Test Path

To support development without physical PYNQ hardware:
*   The `PYNQSensorSource` class will detect a "simulation mode" configuration.
*   In simulation mode, it will yield synthetic spike data instead of attempting to connect to a real PYNQ node.
*   Unit tests can assert the behavior of the source and router using this simulated data path without requiring `pynq` to be installed on the host testing machine.
