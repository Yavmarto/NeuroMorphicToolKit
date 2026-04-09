# Auto-Agent / AI Assistant Instructions

If you are an automated workflow agent (e.g., Jules, Gemini, Claude, Codex) attempting to resolve an issue or implement a new feature in the `NeuroMorphicToolKit`, you **MUST** review the architecture decision records (ADRs) and integration plans before heavily modifying logic or creating new architectural components.

## Submodule Routing Rules

Each submodule governs its own execution invariants and UI styles. Depending on which module your target issue explicitly belongs to, load the context from the associated directories:

1. **`neurocnl`**:
   Before modifying pipelines, IR, parsers, or the `hardware_provider` state management, read the files in:
   - `neurocnl/docs/ADR-Gemini/`
   - `neurocnl/docs/ADR-Codex/`
   - `neurocnl/docs/ADR-claude/`
   *(Pay close attention to `support_matrix.md` and `PRE_BETA_READINESS_REVIEW.md` in `neurocnl/docs/` as well.)*

2. **`Neurosim`**:
   Before modifying visual graph builders or simulation bridges, read:
   - `Neurosim/docs/ADR-Gemini/`
   - `Neurosim/docs/ADR-Codex/`
   - `Neurosim/docs/ADR-claude/`

3. **`Neurochip`**:
   Before touching deployment endpoints, flashing logic, or serial port wrappers, read:
   - `Neurochip/docs/ADR-Gemini/`
   - `Neurochip/docs/ADR-Codex/`
   - `Neurochip/docs/ADR-claude/`

4. **`Neurobench`**:
   Before updating benchmarking pipelines constraints, check:
   - `Neurobench/docs/ADR-Gemini/`
   - `Neurobench/docs/ADR-Codex/`
   - `Neurobench/docs/ADR-claude/`

5. **`Neuro-Dream-Hand`**:
   Before modifying the SNN controller execution or MuJoCo co-simulation loops, read:
   - `Neuro-Dream-Hand/docs/ADR-Gemini/`
   - `Neuro-Dream-Hand/docs/ADR-Codex/`
   - `Neuro-Dream-Hand/docs/ADR-claude/`

## Constraints
- **Design Alignment:** Strictly align newly generated code with the architectural plans and component structures laid out in these directories. 
- **Fidelity vs Approximation:** Respect the boundary logic defining "faithful" vs "approximate" integrations explicitly laid out in the ADRs.
- **Keep PRs tight:** If creating or migrating modules, build modular code according to the styles defined within the respective ADR.
