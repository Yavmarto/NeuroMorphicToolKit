# WF-001: Fix SC2016 Shellcheck Error in release-promote.yml

## Description
Single quotes prevent variable expansion in shell scripts. The variable `$FAILED` in `.github/workflows/release-promote.yml` (Line 38) is wrapped in single quotes and will not be expanded.

## File
- `.github/workflows/release-promote.yml` (Line 38)

## Error
```
SC2016: Expressions don't expand in single quotes
```

## Fix
Replace single quotes with double quotes to allow variable expansion:

**Before:**
```shell
echo '$FAILED'
```

**After:**
```shell
echo "$FAILED"
```

## Difficulty
Easy (1/10)

## Category
Shellcheck Issues
