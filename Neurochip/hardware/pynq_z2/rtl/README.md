# RTL Notes

The first milestone keeps the programmable-logic design simple:

- `snn_overlay_engine` is generated from the HLS sources under `../hls/`
- Vivado instantiates PS7, AXI DMA, the HLS IP, and the AXI interconnect
- Any future AXI-Lite address-window adapter or BRAM bridge logic that is
  needed to refine the manifest-defined MMIO layout should live here

This directory intentionally starts as documentation-only scaffolding because
the current repo did not previously contain a PYNQ hardware project at all.
