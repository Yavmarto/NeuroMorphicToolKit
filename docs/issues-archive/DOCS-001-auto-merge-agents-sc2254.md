# DOCS-001: Fix SC2254 Shellcheck Error in auto-merge-agents.yml

## Description
Variables in `case` statement patterns should be quoted to match literally instead of being interpreted as glob patterns.

## File
- `docs/Opus-dev-pipeline/.github/workflows/auto-merge-agents.yml` (Line 31)

## Error
```
SC2254: Quote expansions in case patterns
```

## Fix
Quote the variable in the case statement:

**Before:**
```shell
case $var in
  pattern) echo "match" ;;
esac
```

**After:**
```shell
case "$var" in
  pattern) echo "match" ;;
esac
```

## Difficulty
Easy (1/10)

## Category
Shellcheck Issues
