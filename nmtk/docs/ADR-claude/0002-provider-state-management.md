# ADR 0002: Provider State Management

## Status
Accepted

## Context
The launcher has complex interdependencies between settings, module state, analytics, and three separate hardware deployment providers. The state management solution must handle cascading updates (e.g., settings changes affecting module behavior) without excessive boilerplate.

## Decision
Use Flutter's Provider package with `ChangeNotifierProvider` for independent state (SettingsProvider, AppProvider, AnalyticsService), `ChangeNotifierProxyProvider` for dependent state (ModuleProvider receives SettingsProvider updates), and `Provider.value` for injecting services. Three deployment providers (Teensy, PYNQ, Akida) maintain independent state trees.

## Consequences
- **Positive:** Provider's simplicity reduces boilerplate compared to Bloc/Redux; ProxyProvider elegantly handles the settings-to-module dependency without manual wiring.
- **Negative:** Provider was chosen over Riverpod (used in module frontends), creating two state management patterns in the ecosystem; ChangeNotifier lacks built-in immutability guarantees.

## Status Update (2026-07-16 audit)

Superseded by ADR-0006 (Riverpod is now the sole state-management approach). Confirmed by grep: no `package:provider` dependency remains in `nmtk/neuro_toolkit/pubspec.yaml`, and no `ChangeNotifierProxyProvider` usage or `ModuleProvider` class exists anywhere under `nmtk/neuro_toolkit/lib/`. ADR 0006 already states it supersedes this ADR; this note is the reciprocal pointer that was never added here.
