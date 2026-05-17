# Governance — NeuroMorphicToolKit
# Inferred by crag analyze — review and adjust as needed

## Identity
- Project: NeuroMorphicToolKit
- Stack: python, docker
- Workspace: git-submodules

## Gates (run in order, stop on failure)
### Test
- pytest
- make ci

### CI (inferred from workflow)
- python -m pip --version
- where pytest || true
- poetry run ruff check .
- poetry run ruff format --check .
- poetry run mypy .
- poetry run pytest --tb=short --hypothesis-show-statistics
- python -m ruff check .
- python -m ruff format --check .

### Contributor docs (ADVISORY — confirm before enforcing)
- mypy --strict  # from CONTRIBUTING.md

## Advisories (informational, not enforced)
- hadolint Dockerfile  # [ADVISORY]
- actionlint  # [ADVISORY]

## Branch Strategy
- Feature branches (feat/, fix/, docs/)
- Free-form commits
- Do not commit, stage, push, or open pull requests unless the user explicitly asks for that git action.

## Security
- No hardcoded secrets — grep for sk_live, AKIA, password= before commit

## Autonomy
- Follow `AGENTS.md`, the nearest module `AGENTS.md`, and `CODING_STYLE_GUIDE.md` before editing.
- Preserve user changes in the working tree; never revert unrelated edits.
- Prefer narrow, module-owned changes and run the owning checks for the touched module.

## GitHub Actions CI/CD
- Treat `.github/workflows/*.yml` and `.github/workflows/*.yaml` as security-sensitive control-plane files.
- Require explicit least-privilege `permissions:` for workflows and jobs.
- Avoid `pull_request_target` unless the workflow never checks out or runs attacker-controlled code.
- Pin third-party actions to immutable commit SHAs where practical; document any version-tag exception.
- Do not interpolate user-controlled GitHub contexts directly into shell `run:` blocks. Map values through `env:` and quote them.
- Keep deployment jobs dependent on successful build, test, and scan jobs.

## Deployment
- Target: docker-compose
- CI: github-actions

## Architecture
- Type: microservices
- Services: neurobench_runner, neurochip_hw, neurocnl_physics, neurosense_hw

## Key Directories
- `.github/` — CI/CD
- `docs/` — documentation
- `scripts/` — tooling
- `tests/` — tests
- `tools/` — tooling

## Testing
- Framework: pytest
- Layout: structured
- Naming: test_*.py
- Snapshot testing: yes

## Anti-Patterns

Do not:
- Do not write absolute local paths in governance (e.g. `D:/project/src/`) — use relative paths only (e.g. `src/`). Governance files are checked into the repo and must remain portable across machines.
- Do not catch bare `Exception` — catch specific exceptions
- Do not use mutable default arguments (e.g., `def f(x=[])`)
- Do not use `import *` — use explicit imports
- Do not use `latest` tag in FROM — pin to a specific version
- Do not run containers as root — use a non-root USER
