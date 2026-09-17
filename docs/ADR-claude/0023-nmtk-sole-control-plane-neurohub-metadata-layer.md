# 0023: `nmtk` Owns the Sole Suite Control Plane

Date: 2026-04-29

## Status

Accepted

## Context

The suite still had mixed ownership language around launcher behavior. `nmtk` already owns the manifest, install state, startup semantics, runtime health, workspace hosting, and launcher doctor flow, but some NeuroHub docs and shell affordances still implied a parallel launcher or orchestration role.

That ambiguity is expensive because it causes duplicate ownership questions around:

- where suite startup begins
- which module owns runtime health and repair actions
- whether project selection inside NeuroHub is a suite workspace concept or local metadata navigation

## Decision

`nmtk` is the only suite control plane.

`NeuroHub` remains a registry and metadata module. It owns:

- project metadata
- workflow metadata and history
- bundle inspection payloads
- cross-module references
- community registry content

`NeuroHub` does not own:

- install or update flows
- backend start and stop semantics
- runtime health polling as a launcher responsibility
- suite workspace hosting or switching
- launcher-visible preflight or repair actions

Legacy NeuroHub routes or restoration payloads that previously referenced orchestration screens may be restored into the nearest surviving metadata view, but no new launcher-parallel runtime-control surface should be added there.

## Consequences

- Launcher manifests, launcher copy, and suite docs must describe `nmtk` as the control plane and NeuroHub as registry and metadata.
- NeuroHub UI should frame project selection as local project focus, not suite workspace control.
- Runtime-control UX belongs in `nmtk`; NeuroHub may deep link back into launcher-owned flows when needed.
