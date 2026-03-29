# Shellcheck Issues

These errors and warnings are reported by `shellcheck` (integrated with `actionlint`) for shell scripts within your YAML `run` blocks.

## Errors Found

### 1. SC2016: Expressions don't expand in single quotes
- **File**: `.github/workflows/release-promote.yml` (Line 38)
- **Details**: Shell variables like `$FAILED` inside single quotes will not be expanded.
- **Ease of Fix (Mac)**: **Easy (2/10)**. Replace single quotes with double quotes.

### 2. SC2086: Double quote to prevent globbing and word splitting
- **File**: `.github/workflows/reusable-status-audit.yml` (Line 53)
- **Details**: `Double quote to prevent globbing and word splitting`. For example, `echo $var` should be `echo "$var"`.
- **Ease of Fix (Mac)**: **Easy (1/10)**. Always double quote shell variables.

### 3. SC2254: Quote expansions in case patterns
- **File**: `docs/Opus-dev-pipeline/.github/workflows/auto-merge-agents.yml` (Line 31)
- **Details**: Variables in `case` patterns should be quoted to match literally.
- **Ease of Fix (Mac)**: **Easy (1/10)**. Replace `case $var in` with `case "$var" in`.

### 4. SC2129: Style Suggestion - Redirection Grouping
- **File**: `.github/workflows/reusable-status-audit.yml`, `.github/workflows/sdd-context-bridge.yml`
- **Details**: `Consider using { cmd1; cmd2; } >> file`. This is a style suggestion for cleaner code.
- **Ease of Fix (Mac)**: **Easy (1/10)**. Refactor redirects.

### 5. SC2106: Exit only exits subshell
- **File**: `.github/workflows/stale-branches.yml` (Line 23)
- **Details**: `exit 1` inside a `$(...)` subshell will only terminate that subshell, not the entire script.
- **Ease of Fix (Mac)**: **Medium (4/10)**. You need to check the return status of the subshell and then exit.

## Suggestions

### Mac/Windows/Linux
- **Fix**: Apply the standard shell scripting fixes suggested above.
- **Action**:
    - Use `"$VAR"` instead of `$VAR`.
    - Use `"{ cmd1; cmd2; } >> file"`.
    - Catch subshell failures: `result=$(cmd); if [ $? -ne 0 ]; then exit 1; fi`.

### Cross-Platform Notes
- **Status**: **Will also occur on Windows and Linux**. These are bash/sh syntax issues. While Windows might use PowerShell (not shell), GitHub Actions hosted runners usually run shell commands in a bash-like environment (unless specified otherwise).
- **Fix**: Identical on all platforms.

## Difficulty Rating
- **Mac**: Easy to Medium
- **Windows**: Easy to Medium
- **Linux**: Easy to Medium
