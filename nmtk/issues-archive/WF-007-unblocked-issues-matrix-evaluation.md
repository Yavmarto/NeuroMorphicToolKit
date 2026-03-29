# WF-007: Fix Matrix Evaluation Failure in unblocked-issues.yml

## Description
The `fromJSON()` function receives invalid JSON when the input is empty or malformed. This happens in `.github/workflows/unblocked-issues.yml` when `${{ needs.implement.outputs.matrix }}` doesn't contain valid JSON.

## Files
- `.github/workflows/unblocked-issues.yml`
- `neurocnl/.github/workflows/unblocked-issues.yml`

## Error
```
ERRO[0000] Error while evaluating matrix: Invalid JSON
```

## Fix
Provide a default empty array fallback for JSON parsing:

**Before:**
```yaml
matrix: ${{ fromJSON(needs.implement.outputs.matrix) }}
```

**After:**
```yaml
matrix: ${{ fromJSON(needs.implement.outputs.matrix || '[]') }}
```

Or ensure the source script always outputs valid JSON:
```shell
if [ -z "$output" ]; then
  echo "matrix=[]" >> $GITHUB_OUTPUT
else
  echo "matrix=$output" >> $GITHUB_OUTPUT
fi
```

## Difficulty
Medium (5/10)

## Category
Runtime (act) Errors
