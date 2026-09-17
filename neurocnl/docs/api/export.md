# Exporters API

The `neurocnl.export` module provides exporters for converting Nengo networks into various neuromorphic and embedded hardware formats.

## Main Exporter Interface

::: neurocnl.export

## Fidelity Notes In Export Flows

Export responses remain backward-compatible file downloads, but now expose additive metadata where relevant:

- HTML reports can include backend support (`backend_support`) and generator fidelity sections when those payloads are provided in the response JSON.
- Hardware-oriented export responses include specific headers:
  - `X-NeuroCNL-Backend-Verdict`: The verdict (`faithful`, `approximate`, `unsupported`)
  - `X-NeuroCNL-Generator-Fidelity-Count`: Number of concepts needing specific heuristics
  - `X-Generator-Fidelity-*`: Additional fidelity annotations.

These notes are advisory. Exporter presence does not imply production-ready hardware support. They help interpret exporter output, assist in portability and evaluation, but do not replace real hardware validation.

## C Header Exporter

::: neurocnl.export.c_header_exporter

## NeuroML Exporter

::: neurocnl.export.neuroml_exporter

## Intel Loihi Exporter

::: neurocnl.export.loihi_exporter

## Intel Lava Exporter

::: neurocnl.export.lava_exporter

## SpiNNaker Exporter

::: neurocnl.export.spinnaker_exporter
