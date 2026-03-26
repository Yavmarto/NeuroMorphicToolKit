# Auto Agentic Workflows (Jules)

This directory is a **Jules-powered duplicate** of the [`Auto agentic workflows`](../Auto%20agentic%20workflows/) folder. All workflows use the **Jules** AI coding agent (`google-labs-code/jules-invoke@v1`) instead of Claude Code.

## Overview

These workflows act as autonomous team members that can fix bugs, implement new features, build scaffolds, perform codebase cleanup, and profile/optimize performance — all through GitHub mechanisms (Labels, Workflow Runs, Scheduled Cron Actions).

Jules branches are prefixed with `jules/` instead of `claude/`.

### Available Workflows

#### Core Agent Workflows
1. **Auto-Merge PRs (`auto-merge-jules-prs.yml`)**: Automatically merges Pull Requests created by Jules (branches prefixed `jules/`) once all required CI status checks pass.
2. **Auto-Fix Bugs (`bug-fixer.yml`)**: Triggers when the `bug` label is applied to an issue. Jules analyzes the bug, implements a fix, adds regression tests, and opens a Pull Request.
3. **Build Feature (`feature-builder.yml`)**: Triggers when the `feature` or `agent` label is added to an issue. Jules reads the requirements, implements the new feature, tests it, and opens a PR.
4. **Auto-Fix CI Failures (`ci-failure-fix.yml`)**: Monitors CI runs. If the build fails, Jules reads the CI logs, finds the root cause, and opens a PR to fix it.
5. **Work on Unblocked Issues (`unblocked-issues.yml`)**: Detects when a blocking issue is closed and immediately kicks off Jules to implement the newly unblocked issue.
6. **Scaffold Module (`scaffold-module.yml`)**: Triggered manually to generate the initial project structure and boilerplate for a new application module.
7. **Performance Improver (`performance-improver.yml`)**: Runs daily to hunt for measurable speed and memory improvements, opening a PR if one is found.
8. **Weekly Codebase Cleanup (`weekly-cleanup.yml`)**: Runs weekly to perform code maintenance (DRY, complexity reduction, formatting).
9. **Unused Code Remover (`unused-code-remover.yml`)**: Runs weekly to find and remove completely unused code via static analysis.
10. **Merge Conflict Resolver (`merge-conflict-resolver.yml`)**: Fires when a maintainer adds the `merge-conflict` label to any PR, or on pushes to main to scan all open `jules/*` PRs for new conflicts.

#### Visibility & Reporting
11. **Morning Agent Standup (`morning-standup.yml`)**: Runs weekdays at 8 AM UTC and posts a structured briefing to a pinned `standup-log` issue — listing queued issues, open Jules PRs awaiting review, and any running workflows.
12. **EOD Agent Report (`eod-report.yml`)**: Runs weekdays at 5 PM UTC and posts an end-of-day summary to the same `standup-log` issue.

#### Autonomous Pipeline Intelligence
13. **Idle Capacity Triage (`idle-capacity-triage.yml`)**: Runs hourly. When no agent workflow is running and the daily run budget hasn't been reached, Jules classifies unlabeled issues as `bug` or `feature` with priority labels.
14. **Guardrails Updater (`guardrails-updater.yml`)**: When a `jules/*` PR is rejected and closed without merging, Jules reads the review comments, distils the failure into a new "Sign" in `GUARDRAILS.md`, and opens a PR for human approval.

#### Infrastructure
15. **SDD Context Bridge (`sdd-context-bridge.yml`)**: A reusable workflow that reads `SPEC.md`, `AGENTS.md`, `GUARDRAILS.md`, and `RULES.md` and exposes them as a combined context string for injection into Jules prompts.

---

## Setup Instructions

### Prerequisites
1. **Repository Settings (`Auto-Merge`)**:
   - Go to **Settings** → **General** and enable "Allow auto-merge".
   - Add a branch protection rule for your default branch requiring at least one status check to pass.

2. **Secrets Configuration**:
   - Add `JULES_API_KEY` to your repository action secrets (**Settings** → **Secrets and variables** → **Actions**).
   - The workflows use the built-in `GITHUB_TOKEN` for checkouts and PR creation.
   - Ensure workflow permissions allow read/write access (**Settings** → **Actions** → **General** → **Workflow permissions**).

3. **Optional secrets**:
   - `STANDUP_WEBHOOK_URL` — Slack or Discord incoming webhook URL for morning standup and EOD reports.

4. **Optional repository variables**:
   - `AGENT_DAILY_RUN_LIMIT` — max agent workflow completions per day before idle triage stops. Default: `20`. Set to `0` to disable.

5. **Trusted maintainers**:
   - Update the `"your-github-username"` placeholder in the `.yml` files with your actual GitHub username(s).

---

## How Jules Works

The Jules mechanism differs from Claude Code:

1. **No manual checkout needed** — `google-labs-code/jules-invoke@v1` handles repository access internally.
2. **No Git configuration needed** — Jules creates its own `jules/` prefixed branches and opens PRs automatically.
3. **Simpler YAML** — you only pass `jules_api_key` and `prompt` to the action; all Git plumbing is hidden.

```yaml
- uses: google-labs-code/jules-invoke@v1
  with:
    jules_api_key: ${{ secrets.JULES_API_KEY }}
    prompt: |
      [Your task prompt here]
```

---

## Technical Differences vs. Claude Version

| Aspect | Claude Code Version | Jules Version |
|--------|--------------------|----|
| Invocation | `npx -y @anthropic-ai/claude-code@latest -p "$PROMPT"` | `uses: google-labs-code/jules-invoke@v1` |
| Secret | `CLAUDE_CODE_OAUTH_TOKEN` | `JULES_API_KEY` |
| Branch prefix | `claude/` | `jules/` |
| Checkout required | Yes (`actions/checkout@v4`) | No (handled by action) |
| Git config required | Yes (user.name, user.email) | No (handled by action) |
| PR creation | Via `gh` CLI in the prompt | Automatic |
