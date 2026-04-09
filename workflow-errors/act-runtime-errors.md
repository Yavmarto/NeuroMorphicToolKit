# act Runtime and Dry-Run Errors

These errors were encountered during the `act -n` (dry-run) phase. They involve issues that linting might miss, such as matrix evaluation failures and local execution limitations.

## Errors Found

### 1. Matrix Evaluation Failure: Invalid JSON
- **Files**:
    - `unblocked-issues.yml`
    - `neurocnl/.github/workflows/unblocked-issues.yml`
- **Details**: `ERRO[0000] Error while evaluating matrix: Invalid JSON`. This happens when `${{ fromJSON(...) }}` receives a string that isn't a valid JSON array/object, often due to an empty output or a malformed input from a previous step (e.g., `${{ fromJSON(needs.implement.outputs.matrix) }}`).
- **Ease of Fix (Mac)**: **Medium (5/10)**. Requires ensuring the source of the JSON (e.g., a script output) is always valid, even when empty.

### 2. "Could not find any stages to run"
- **Files**:
    - `stale-branches.yml`
    - `submodule-sync.yml`
    - `performance-improver.yml`
- **Details**: `act` defaults to triggering on the `push` event. If a workflow only has `schedule` or `workflow_dispatch` triggers, `act` won't find anything to run unless explicitly told which event to simulate.
- **Ease of Fix (Mac)**: **Very Easy (1/10)**. This is a local testing configuration issue, not necessarily a bug in the code.

### 3. Unsupported Platform Warnings
- **Files**: Multiple (e.g., `owasp-dependency-check`, `python-audit`)
- **Details**: `Skipping unsupported platform -- Try running with -P self-hosted=...`. `act` needs a mapping for non-standard runner labels.
- **Ease of Fix (Mac)**: **Easy (1/10)**. Update `.actrc` with the correct mappings.

## Suggestions

### Mac/Windows/Linux
- **Fix (Matrix)**: Wrap the JSON generation in a check or provide a default empty fallback: `${{ fromJSON(needs.job.outputs.json || '[]') }}`.
- **Fix (Stages)**: Manually trigger `act` with the event name: `act workflow_dispatch`.

### Cross-Platform Notes
- **Status**: **Will also occur on Windows and Linux**. Matrix logic is handled by the GitHub Actions engine.
- **Fix**: Identical logic across platforms.

## Difficulty Rating
- **Mac**: Medium
- **Windows**: Medium
- **Linux**: Medium
