# T4-3: Fix Windows installer scope

- **Problem:** `nmtk/installer/windows/setup.iss` only builds the neurocnl frontend, not the full neuro_toolkit launcher.
- **Fix:** Update Inno Setup script to build from `nmtk/neuro_toolkit/build/windows/` and include all module assets.
- **Effort:** 1 day
