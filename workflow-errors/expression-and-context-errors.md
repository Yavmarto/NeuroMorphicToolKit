# Expression and Context Errors

These errors involve GitHub Actions expression syntax (`${{ ... }}`) and referencing context variables (like `github.head_ref` or `issue_number`) incorrectly.

## Errors Found

### 1. `github.head_ref` is potentially untrusted
- **File**: `.github/workflows/pr-labeler.yml` (Line 24)
- **Details**: Directly using `github.head_ref` in inline scripts is a security risk for script injection.
- **Ease of Fix (Mac)**: **Medium (4/10)**. Pass it through an environment variable.

### 2. Undefined properties in object type
- **File**: `.github/workflows/reusable-feature-builder.yml` (`issue_number`)
- **File**: `.github/workflows/unblocked-issues.yml` (`issue_title`, `issue_body`, `issue_author`)
- **Details**: Referencing a property like `${{ needs.implement.outputs.issue_number }}` where it's not defined in the outputs of that job.
- **Ease of Fix (Mac)**: **Medium (5/10)**. Ensure the property is explicitly defined as an output in the previous job.

## Suggestions

### Mac/Windows/Linux
- **Fix (Untrusted Ref)**:
    - PASS the context to an environment variable and use that in the shell script.
```yaml
      - name: Use head ref
        env:
          HEAD_REF: ${{ github.head_ref }}
        run: echo "$HEAD_REF"
```
- **Fix (Undefined Property)**:
    - Ensure that the previous job (`implement`) specifies the outputs.
```yaml
jobs:
  implement:
    outputs:
      issue_number: ${{ steps.step_id.outputs.issue_number }}
    steps:
      - id: step_id
        run: echo "issue_number=123" >> $GITHUB_OUTPUT
```

### Cross-Platform Notes
- **Status**: **Will also occur on Windows and Linux**. Expression evaluation happens on the GitHub runner's server-side, not the local OS.
- **Fix**: Identical logic on all platforms.

## Difficulty Rating
- **Mac**: Medium
- **Windows**: Medium
- **Linux**: Medium
