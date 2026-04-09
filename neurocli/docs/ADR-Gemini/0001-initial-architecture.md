# ADR 0001: Initial Architecture of neurocli

## Status
Accepted

## Context
While NMTK provides a graphical launcher interface, power users, continuous integration pipelines, and headless systems require a command-line interface to interact with NMTK modules.

## Decision
We will implement `neurocli` as the command-line counterpart to the main NMTK graphical tools. It will allow scripting, automation, and headless operation of features within the NMTK platform.

## Consequences
- **Positive:** Facilitates CI/CD integrations and batch operations.
- **Negative:** Must maintain feature parity with the GUI interface, increasing maintenance overhead.
