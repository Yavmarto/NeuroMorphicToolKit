# NeuroMorphicToolKit

**The unified desktop suite for neuromorphic computing.**

NMTK brings together everything you need to design, simulate, deploy, and benchmark spiking neural networks — from a plain-English specification all the way to running on neuromorphic hardware — in a single native application. No terminal, no `pip install`, no `.env` files.

---

## Who is this for?

<div class="grid cards" markdown>

- **Researchers & Neuroscientists**

    Design SNNs using natural language (Controlled Natural Language), validate biological constraints, run simulations, and inspect spike timing — all from a visual workbench.

    [Get started with NeuroStudio →](modules/neurostudio.md)

- **Hardware Engineers**

    Flash and execute validated SNN models on Loihi, SpiNNaker, PYNQ-Z2, Akida, and Teensy targets. Diagnose hardware state and benchmark across platforms from one interface.

    [Get started with Neurochip →](modules/neurochip.md)

</div>

---

## The six modules

| Module | What it does | Status |
|--------|-------------|--------|
| **NeuroStudio** | English-to-SNN authoring, visual canvas, simulation preview | 99% |
| **Neurosense** | Sensory encoding — vision, audio, EMG → spike trains | 97% |
| **Neurobench** | Standardized benchmarking: latency, throughput, pJ/SOP | 95% |
| **Neurohub** | Community registry — share and discover models, datasets, specs | 85% |
| **Neurochip** | Hardware deployment and diagnostics | 60% |
| **Neuro-Dream-Hand** | Applied robotics — Teensy edge integration | 95% |

All six modules are managed and launched through the **NMTK Launcher**, a native desktop app for macOS, Windows, and Linux.

---

## How it works

```
 ┌─────────────────────────────────────────────────────┐
 │                  NMTK Launcher (Flutter)             │
 │  Module Hub · Dashboard · Health · Settings          │
 └────────────────────┬────────────────────────────────┘
                      │ local HTTP
          ┌───────────▼──────────────┐
          │   suite_api  (port 9000)  │
          │   FastAPI · OpenAPI docs  │
          └──┬──────┬──────┬──────┬──┘
             │      │      │      │
         neurocnl  neuro  neuro  neuro
          :9000   sense  bench   hub
                  worker worker worker
                 (opt.)  (opt.) (opt.)
```

The Launcher orchestrates Docker containers or isolated Python venvs for each module. Users never see the plumbing.

---

## Quick links

- [Install NMTK](getting-started/installation.md) — system requirements and setup steps
- [5-minute Quick Start](getting-started/quickstart.md) — write your first SNN and open it on the canvas
- [API Reference](api-reference/index.md) — full OpenAPI docs for `suite_api`
- [Hardware Support Matrix](hardware/support-matrix.md) — which targets are validated
- [Troubleshooting](troubleshooting.md) — common startup problems and fixes
