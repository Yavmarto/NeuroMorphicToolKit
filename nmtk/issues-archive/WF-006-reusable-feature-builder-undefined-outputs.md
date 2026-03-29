# WF-006: Fix Undefined Output Properties in reusable-feature-builder.yml

## Description
The workflow references `needs.implement.outputs.issue_number` which is not explicitly defined as an output in the `implement` job. This causes runtime errors when the output is not available.

## File
- `.github/workflows/reusable-feature-builder.yml`

## Error
```
Expression/Context Error: Undefined properties in object type (issue_number)
```

## Fix
Ensure the previous job explicitly defines the outputs:

**In implement job:**
```yaml
jobs:
  implement:
    outputs:
      issue_number: ${{ steps.step_id.outputs.issue_number }}
    steps:
      - id: step_id
        run: echo "issue_number=123" >> $GITHUB_OUTPUT
```

**Then use in dependent jobs:**
```yaml
- run: echo ${{ needs.implement.outputs.issue_number }}
```

## Difficulty
Medium (5/10)

## Category
Expression and Context Errors
