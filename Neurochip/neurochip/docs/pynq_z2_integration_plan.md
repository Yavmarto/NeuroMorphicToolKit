# PYNQ-Z2 FPGA Overlay Deployment Plan

## 1. Overlay Definition and Loading
The SNN overlay is a `.bit` bitstream file and an accompanying `.hwh` hardware handoff file. These files are loaded onto the Zynq-7000's programmable logic (PL) using the `pynq` Python library. We will create a `PYNQBackend` class that wraps `pynq.Overlay`.

```python
from pynq import Overlay


class PYNQBackend:
    def __init__(self, bitstream_path: str):
        self.overlay = Overlay(bitstream_path)
```

## 2. ARM-PL Interface (DMA and MMIO)
- **MMIO (Memory-Mapped I/O):** Used for configuring the SNN parameters (e.g., loading weight matrices, setting neuron thresholds, triggering resets, and querying status registers). The `pynq.MMIO` library or direct IP core access via `self.overlay.ip_name` provides this.
- **DMA (Direct Memory Access):** Used for high-bandwidth streaming of input spikes (stimulus) from the ARM processing system to the PL, and reading back the generated output spikes from the PL to the ARM. The `pynq.lib.dma` class handles `sendchannel` and `recvchannel` operations using Xilinx AXI DMA. Contiguous memory buffers will be allocated using `pynq.allocate`.

## 3. High-Level Synthesis (HLS) Pipeline Entry Point
While full HLS is out of scope, the workflow is:
1. Neurochip's SNN representation (from `NetworkInput`) is converted to an intermediate representation (IR) or directly into a set of C/C++ arrays/parameters.
2. An HLS template (C/C++) representing the generic SNN engine is specialized with these parameters.
3. Vivado HLS synthesizes this into an IP block (RTL).
4. Vivado Block Design stitches the SNN IP with Zynq Processing System (PS) and AXI DMA/Interconnect IPs.
5. Bitstream (`.bit`) and hardware handoff (`.hwh`) are generated and placed in `neurochip/overlays/`.

## 4. Deployment Flow
1. **Load:** `backend.load_overlay("snn_model.bit")`
2. **Configure:** Use MMIO to write network weights and biases into the PL BRAM/registers.
3. **Stimulus Input:** Allocate contiguous memory, populate with input spike data (e.g., timestamps and indices), and initiate DMA transfer: `dma.sendchannel.transfer(input_buffer)`.
4. **Execution:** Wait for DMA transfer to complete or MMIO status register to indicate completion.
5. **Readback:** Initiate DMA read into output buffer: `dma.recvchannel.transfer(output_buffer)`, wait, and process the results back into standard Python types.

## 5. Remote Execution Model
The Neurochip backend runs as a FastAPI service directly on the ARM Cortex-A9 cores of the PYNQ-Z2 board.
- The board runs a Linux environment (e.g., PYNQ Linux image).
- FastAPI serves requests on port 8000.
- A remote client sends the deployment payload (including weights/config or even a compiled `.bit` file) via HTTP POST.
- The ARM service receives the payload, loads the overlay using `pynq`, configures the hardware, runs the inference, and returns the spike output via the HTTP response.

## 6. API Endpoints
New endpoints added in `neurochip/app/routers/pynq.py`:
- `POST /hardware/pynq/deploy`: Uploads configuration (and optionally bitstream) to configure the overlay.
- `POST /hardware/pynq/run`: Sends input spike streams, runs inference, and returns output spikes.

## 7. Dependencies
The `pynq` library will be added as an optional dependency in `pyproject.toml` under a `[tool.poetry.extras]` section for `pynq` deployment to prevent compilation issues on non-ARM environments.
