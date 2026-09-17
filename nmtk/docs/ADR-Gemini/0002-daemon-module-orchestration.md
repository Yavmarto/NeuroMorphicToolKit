# ADR 0002: Daemon Module Orchestration

## Status
Accepted

## Context
The full NMTK ecosystem requires multi-gigabyte Python dependencies, varied Docker stacks, and SDKs. Compiling all of this into a single runnable executable for end users is impossible given neuromorphic compute requirements. Giving users a series of fragmented `pip install` bash scripts ruins the "app store" experience.

## Decision
The core Flutter NMTK desktop client (`neuro_toolkit`) acts as a Daemon/Manager. Selecting a module downloads the artifact internally and uses native Dart shell bridges (`Process.run`) to spool up Python virtual environments or Docker containers locally. The Flutter shell then talks directly to these newly backgrounded micro-services.

## Consequences
- **Positive:** Ultimate encapsulation of scientific library hell. The end-user never opens a terminal and interacts solely with a slick desktop app.
- **Negative:** Pathing issues across Windows, Linux, and macOS complicate local OS `Process.run()` calls; handling stray orphaned background zombie processes across submodules is difficult.
