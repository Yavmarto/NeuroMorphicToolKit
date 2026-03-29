# WF-011: Fix Undefined Output Properties in unblocked-issues.yml

## Description
The workflow references output properties (`issue_title`, `issue_body`, `issue_author`) from the `implement` job that are never explicitly defined in that job's `outputs` map. This causes expression/context errors at runtime.

## File
- `.github/workflows/unblocked-issues.yml`

## Error
```
Undefined properties: issue_title, issue_body, issue_author in object type
```

References like `${{ needs.implement.outputs.issue_title }}` will resolve to empty strings unless the `implement` job explicitly declares these as outputs.

## Fix
Ensure the `implement` job declares all referenced outputs and that the corresponding steps set them via `$GITHUB_OUTPUT`:

```yaml
jobs:
  implement:
    outputs:
      issue_title: ${{ steps.<step_id>.outputs.issue_title }}
      issue_body: ${{ steps.<step_id>.outputs.issue_body }}
      issue_author: ${{ steps.<step_id>.outputs.issue_author }}
    steps:
      - id: <step_id>
        run: |
          echo "issue_title=..." >> $GITHUB_OUTPUT
          echo "issue_body=..." >> $GITHUB_OUTPUT
          echo "issue_author=..." >> $GITHUB_OUTPUT
```

## Difficulty
Medium (5/10)

## Category
Expression and Context Errors

## Related
- WF-006: Covers the same class of error for `reusable-feature-builder.yml` (`issue_number`)
- WF-007: Covers a different error (matrix JSON evaluation) in the same file
