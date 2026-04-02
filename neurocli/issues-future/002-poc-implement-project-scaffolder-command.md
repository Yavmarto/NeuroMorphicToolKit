# [POC-02] Implement `neuro new` Project Scaffolder

**Module**: neurocli
**Phase**: POC
**Priority**: P0
**Effort**: Medium (2-3 days)
**Labels**: `neurocli`, `phase:poc`, `priority:critical`, `scaffolding`, `cli`
**Source**: `neurocli/issues-archive/22mar1_project_scaffolder.md`

## Problem

The clearest intended purpose of `neurocli` is project bootstrapping. The archived plan explicitly describes a command like:

```bash
neuro new --framework lava --target loihi2 --task kws
```

Without this command, `neurocli` does not yet provide unique value relative to the desktop launcher or the existing module-local CLIs.

## Acceptance Criteria

- [ ] Implement `neuro new` as the first real end-user command
- [ ] Support at least `--framework`, `--target`, and `--task` options
- [ ] Generate a project directory with a predictable structure
- [ ] Include starter metadata such as `README.md` and dependency configuration
- [ ] Include at least one runnable starter script or annotated example file
- [ ] Validate unsupported framework/target combinations with clear error messages
- [ ] Return non-zero exit codes on invalid input or failed generation
