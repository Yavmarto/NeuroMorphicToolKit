---
name: nmtk-git-workflow
description: Git workflow for the NeuroMorphicToolKit monorepo. Use this skill whenever you need to pull, push, create a branch, open a pull request, or merge — across the root repo and its 7 submodules. Never run git commands manually across repos. Always use scripts/git/ which enforces the correct submodule-first order.
compatibility: Requires bash and git. For create-pr.sh, also requires the GitHub CLI (gh) authenticated via gh auth login.
allowed-tools: Bash Read
---

# NeuroMorphicToolKit Git Workflow

This is a monorepo with 7 git submodules: `neurocnl`, `Neuro-Dream-Hand`, `Neurobench`, `Neurosim`, `Neurosense`, `Neurochip`, `Neurohub`.

All cross-repo git operations use the scripts in `scripts/git/`. Every script processes **submodules first, then the root repo** — the order that keeps submodule pointers consistent in the root.

Run all scripts from the monorepo root.

---

## Pull latest changes

```bash
bash scripts/git/pull-all.sh [branch]
```

- `branch` defaults to `dev`
- Auto-stashes dirty state, pulls with `--ff-only`, restores the stash
- Skips repos where the branch doesn't exist

---

## Stage, commit, and push

```bash
bash scripts/git/push-all.sh "feat(scope): message" [branch]
```

- Omit arguments to be prompted interactively
- `branch` defaults to the current branch in the root repo
- Stages everything (`git add -A`), commits, and pushes in each repo that has changes

Commit message format: `feat(scope)`, `fix(scope)`, `refactor(scope)`, `docs`, `test(scope)`, `chore(scope)`

---

## Create a branch

```bash
bash scripts/git/create-branch.sh <new-branch> [base-branch]
```

- Creates the branch in every submodule and the root, pushes with upstream tracking
- If `base-branch` is given, checks it out first in each repo before branching
- Skips repos where `base-branch` doesn't exist
- If the branch already exists in a repo, just checks it out

---

## Open pull requests

```bash
bash scripts/git/create-pr.sh "PR title" [base-branch]
```

- `base-branch` defaults to `main`
- Pushes each branch to origin first
- Skips repos with no commits ahead of base, and repos where a PR already exists
- Auto-generates the PR body from `git log`
- Requires `gh auth login` — check with `gh auth status`

---

## Merge a branch

```bash
bash scripts/git/merge.sh <source-branch> [strategy]
```

| Strategy | Behaviour |
|----------|-----------|
| *(none)* | Merge cleanly; on conflict, print instructions and continue to the next repo |
| `--ours` | Auto-resolve all conflicts keeping the current branch's version |
| `--theirs` | Auto-resolve all conflicts keeping the source branch's version |
| `--no-ff` | Force a merge commit even when fast-forward is possible |
| `--abort` | Abort any in-progress merge across all repos |

After `--ours` or `--theirs`, review the merge commit before running `push-all.sh`.

For manual conflicts: resolve the files, then inside the affected repo run `git add <files> && git merge --continue`. Then run `merge.sh` again for remaining repos, or push once all are resolved.

---

## Rules

- **Never** run `git add`, `git commit`, `git push`, `git pull`, or `git checkout` manually across multiple repos — always go through the scripts.
- **Never** push directly to `main`. Create a branch with `create-branch.sh`, push changes with `push-all.sh`, then open PRs with `create-pr.sh`.
- The default working branch is `dev`.
- After a merge, run `push-all.sh` to commit the updated submodule pointers in the root repo.
