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

Today this folder has not been started as an implementation module yet.

It currently contains:

- one archived planning issue
- no Python package
- no CLI entry point
- no templates
- no tests

## What Belongs Here Next

The first meaningful version of `neurocli` should probably include:

1. a small Python package, likely using `typer` or `click`
2. a `neuro new ...` command for project scaffolding
3. template bundles for a few supported combinations
4. generated files such as `pyproject.toml`, `requirements.txt`, example scripts, and README content
5. commands that can later grow into module install/run/status helpers

If the desktop launcher is the GUI front door to NMTK, `neurocli` should be the scriptable front door.
