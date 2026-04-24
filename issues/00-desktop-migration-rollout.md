# Desktop Migration Rollout

This backlog splits the desktop migration into a small foundation lane plus module lanes.

## Ordering

1. `issues/01-suite-design-contract-and-module-brief.md`
2. `issues/02-shell-adapter-contract-and-package-conventions.md`
3. `nmtk_ui_core/issues/01-shell-tokens-top-bars-and-status-primitives.md`
4. `issues/03-launcher-workspace-host-and-persistent-sessions.md`
5. `issues/04-launcher-modules-surface-and-install-start-semantics.md`

After those gates are stable enough, the module lanes can fan out.

## Parallel waves

### Phase A: foundation

- `F1` Full-workspace local agent: `issues/01-suite-design-contract-and-module-brief.md`
- `F4` Full-workspace local agent: `issues/02-shell-adapter-contract-and-package-conventions.md`
- `F2` Full-workspace local agent: `nmtk_ui_core/issues/01-shell-tokens-top-bars-and-status-primitives.md`
- `F3` Full-workspace local agent: `issues/03-launcher-workspace-host-and-persistent-sessions.md`
- `F3` Full-workspace local agent: `issues/04-launcher-modules-surface-and-install-start-semantics.md`
- `C1` Full-workspace local agent: `neurocli/issues/01-cli-contracts-for-shell-actions.md`

### Phase B: first safe fan-out

- `M1` `Neurohub`: all `Neurohub/issues/*.md`
- `M2` `neurocnl`: all `neurocnl/issues/10-*.md`
- `M3` `Neurobench`: all `Neurobench/issues/10-*.md`

These three lanes can run in parallel once Issues 01-04 and `nmtk_ui_core/issues/01-02` are ready enough.

### Phase C: interaction-heavy modules

- `M4` `Neurosim`: all `Neurosim/issues/*.md`
- `M5` `Neurosense`: all `Neurosense/issues/*.md`

These can run in parallel after the workspace host, restoration hooks, and shell panel patterns are proven in Phase B.

### Phase D: hardware-sensitive modules

- `M6` `Neurochip`: all `Neurochip/issues/10-*.md`
- `M7` `Neuro-Dream-Hand`: all `Neuro-Dream-Hand/issues/*.md`

These can overlap with each other, but they should start after capability reporting, degraded-state UX, and long-running job patterns are already working.

## Independent side lane

- Hardware and runtime validation can proceed in parallel with all UI work as long as it does not depend on unfinished shell widgets.
- Keep Akida, PYNQ Z2, service diagnostics, and capability reporting in a separate review lane.

## Rule of thumb

- Almost all module migrations can run in parallel.
- The shared shell contracts cannot.
- One owner each for design, adapter contracts, shared UI core, and launcher host is required to avoid drift.
