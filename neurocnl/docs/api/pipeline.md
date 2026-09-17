# Core Pipeline API

The `neurocnl.pipeline` module provides the unified orchestration for the parse -> validate -> generate flow, with an internal legacy simulation stage that is no longer part of the supported public NeuroCNL product surface.

Key additive internal result fields now include:

- `ir`: The Neuromorphic Intermediate Representation (NIR) stage. This is a central pivot format used to orchestrate model conversion between frameworks like Nengo, Lava, PyNN, Brian2, and Rockpool before hardware-specific generation. Accessible via `PipelineResult.ir`.
- `planner`: advisory backend support verdict plus warnings, accessible via `PipelineResult.planner`. It provides a summary verdict (`faithful`, `approximate`, `unsupported`) based on the targeted backend's capabilities, along with specific implementation warnings.
- `generator_fidelity`: concept-level generator fidelity annotations for advanced features. This explicitly describes whether advanced generated concepts are direct mapping, approximate heuristics, or placeholder implementations.

The backend API surfaces these ideas through `/api/validate` and `/api/generate` on the supported surface. `/api/simulate` remains deprecated and returns `410` for the NIR-only public API.

::: neurocnl.pipeline
