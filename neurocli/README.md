# neurocli

`neurocli` appears intended to be the command-line companion to the NMTK suite.

## What It Should Do

Based on the only tracked issue in this folder and the rest of the workspace, the most likely purpose of `neurocli` is:

- bootstrap new neuromorphic projects from the terminal
- generate starter layouts for common frameworks and targets
- provide a lightweight alternative to the desktop launcher for automation-heavy users
- expose repeatable commands that can later be called from CI, shell scripts, or other modules

The clearest intended workflow is documented in
[`issues-archive/22mar1_project_scaffolder.md`](./issues-archive/22mar1_project_scaffolder.md):

```bash
neuro new --framework lava --target loihi2 --task kws
```

That points to a scaffolding-first CLI rather than a simulation or orchestration service.

## Why This Fits The Rest Of NMTK

The repository already has:

- a desktop launcher in `nmtk/neuro_toolkit`
- module-specific CLIs inside some submodules such as `neurocnl` and `Neuro-Dream-Hand`
- GitHub workflows for scaffolding and agent-driven module creation

What is still missing is a single user-facing CLI that can sit above those pieces and help a terminal-first developer:

- create a new project
- choose a framework
- choose a hardware target
- get a boilerplate directory with dependencies, scripts, and docs

So `neurocli` most likely belongs in the "developer tooling / project bootstrap" layer of the suite.

## Current State

`neurocli` is implemented as a Typer-based Python package (`neuro` entry point). Shipped commands:

- `neuro new` — scaffold a project from a framework + target template bundle
- `neuro status` / `neuro install` / `neuro run` — headless module lifecycle helpers
- `neuro hub login` / `push` / `pull` / `search` — talk to the Neurohub Global Registry
  over its `/api/v1` API using `neurohub://` URIs

`neuro hub` resolves the registry URL from `nmtk/neuro_toolkit/assets/modules.json`
(the Neurohub port), an `--registry` flag, the `NEUROHUB_REGISTRY` env var, or the stored
credentials file, and verifies SHA-256 checksums on every `pull`. The shared
`neurocli/uri_parser.py` is kept byte-for-byte equivalent with the backend copy at
`Neurohub/neurohub/app/utils/uri_parser.py`.

## Verification

```bash
cd neurocli && make verify   # ruff + mypy + pytest (incl. tests/properties/)
```

If the desktop launcher is the GUI front door to NMTK, `neurocli` is the scriptable front door.
