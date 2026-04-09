# ADR 0003: GoRouter Shell Routes

## Status
Accepted

## Context
The desktop app needs declarative routing with a persistent shell layout (navigation rail + content area) that survives route changes, and a first-run onboarding gate that redirects new users before they can access the main application.

## Decision
Use GoRouter with a `ShellRoute` wrapping the main content routes (dashboard, catalog, tool/:moduleId, settings, deploy screens). A redirect guard in the router configuration checks `AppProvider.hasSeenOnboarding` and diverts new users to the onboarding flow. The `tool/:moduleId` dynamic segment resolves which module to display.

## Consequences
- **Positive:** ShellRoute pattern maintains navigation rail state across page transitions without rebuild; declarative redirect guards are testable and predictable.
- **Negative:** GoRouter's redirect mechanism runs on every navigation event, adding overhead; deep linking to specific module views requires careful path parameter handling.
