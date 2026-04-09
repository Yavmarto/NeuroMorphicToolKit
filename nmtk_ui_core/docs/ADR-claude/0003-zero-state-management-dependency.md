# ADR 0003: Zero State Management Dependency

## Status
Accepted

## Context
NMTK frontends use different state management solutions: Provider in the desktop launcher, Riverpod in module frontends. The shared widget library must work seamlessly with all consumers regardless of their state management choice.

## Decision
Enforce a zero state management dependency policy in nmtk_ui_core. The package depends only on Flutter core SDK and google_fonts at runtime. All widgets are pure stateless or stateful widgets with callback-based APIs (onTap, onChanged, onSubmit) rather than subscribing to external state stores.

## Consequences
- **Positive:** Framework-agnostic widgets work with Provider, Riverpod, Bloc, or any future state management solution; callback-based APIs make widgets easy to test without mock providers.
- **Negative:** Widgets cannot directly react to state changes, pushing more wiring responsibility onto consumers; complex interactive widgets may require verbose callback threading.
