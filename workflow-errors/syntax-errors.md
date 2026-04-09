# Workflow Syntax Errors

These errors involve fundamental structural issues in the GitHub Actions YAML files, such as missing required sections or using keys in the wrong context.

## Errors Found

### 1. Missing `runs-on` and `steps` / Misplaced `run`
- **File**: `Neuro-Dream-Hand/.github/workflows/auto-merge-jules-prs.yml`
- **Details**:
    - Job `auto-merge` is missing the required `runs-on` and `steps` sections.
    - The `run` key is used at the job level (line 15), but it should be inside a step.
- **Ease of Fix (Mac)**: **Easy (1/10)**. This is a copy-paste or structural oversight.

### 2. General Schema Validation
- **File**: `neurocnl/.github/workflows/auto-merge-jules-prs.yml` (and potentially others)
- **Details**: Similar structure issues as above, often caused by trying to run a shell command directly under a job name.

## Suggestions

### Mac
- **Fix**: Wrap the `run` command inside a `steps` block and add `runs-on: ubuntu-latest`.
- **Action**:
```yaml
jobs:
  auto-merge:
    runs-on: ubuntu-latest
    steps:
      - name: Skip broken auto-merge
        run: echo "Skipping broken auto-merge"
```

### Windows/Linux (Cross-Platform)
- **Status**: **Will also occur on Windows and Linux**. Syntax errors are platform-independent as GitHub Actions logic is validated before execution.
- **Fix**: Identical to Mac suggestions. Use `actionlint` locally on those platforms to verify structure.

## Difficulty Rating
- **Mac**: Easy
- **Windows**: Easy
- **Linux**: Easy
