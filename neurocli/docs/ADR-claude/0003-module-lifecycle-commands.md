# ADR 0003: Module Lifecycle Commands

## Status
Accepted

## Context
Developers currently manage NMTK module installation, startup, and health checking manually through shell commands or through the desktop launcher's GUI. Terminal-based and CI workflows need programmatic equivalents of these operations.

## Decision
Plan `neuro install <module>`, `neuro run <module>`, and `neuro status` commands that mirror the desktop launcher's module management. Commands resolve module configurations from the same manifest system used by the launcher, target uvicorn for backend startup, and use HTTP health checks to report module status.

## Consequences
- **Positive:** Terminal-native module management enables headless deployment and scripted orchestration; shared manifest system ensures CLI and GUI stay in sync.
- **Negative:** Module lifecycle depends on correct virtual environment and Docker setup, which is harder to diagnose in a terminal-only environment; must track the launcher's manifest format as it evolves.
