# ADR 0006: Riverpod Launcher State Management

## Status
Accepted

## Supersedes
- ADR 0002: Provider State Management
- The state-management portion of ADR 0005: Separate Deployment Providers

## Context
The launcher and embedded product frontends had diverged onto two different
state-management stacks: `provider` in `nmtk/neuro_toolkit` and Riverpod in the
module UIs. That split increased onboarding cost, duplicated test harness
patterns, and made cross-app UI work harder in the monorepo. We want one
first-party state-management approach across the Flutter surfaces without
rewriting existing launcher `ChangeNotifier` state objects all at once.

## Decision
Use Riverpod 2.x as the exclusive first-party state-management entrypoint for
the launcher and Neurohub frontend.

- Bootstrap app state through `ProviderScope` and Riverpod overrides.
- Keep existing launcher and Neurohub `ChangeNotifier` classes during this
  migration, but expose them through Riverpod `ChangeNotifierProvider` and
  `Provider` declarations.
- Replace direct `package:provider` widget access with
  `ConsumerWidget`/`ConsumerStatefulWidget` and `ref.watch`/`ref.read`.
- Construct the launcher router from a Riverpod provider so routing refresh
  depends on Riverpod-owned state rather than singleton lookups.

## Consequences
- **Positive:** The repo now has one Flutter state-management model across the
  launcher and module UIs, with better override/test ergonomics and no direct
  `provider` dependency in first-party code.
- **Positive:** The migration is low risk because existing `ChangeNotifier`
  implementations, services, and state shapes remain intact.
- **Negative:** The launcher still carries `ChangeNotifier`-style mutable state
  internally until a future migration to `Notifier`/`AsyncNotifier`.
- **Negative:** Riverpod and `go_router` bootstrap wiring is more explicit than
  the old `MultiProvider` setup and must be kept in sync in tests.
