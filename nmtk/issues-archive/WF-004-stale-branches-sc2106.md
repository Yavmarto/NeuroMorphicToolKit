# WF-004: Fix SC2106 Shellcheck Error in stale-branches.yml

## Description
The `exit` command inside a command substitution (subshell) will only exit that subshell, not the entire script. The `.github/workflows/stale-branches.yml` (Line 23) has this issue.

## File
- `.github/workflows/stale-branches.yml` (Line 23)

## Error
```
SC2106: Exit only exits subshell
```

## Fix
Check the return status of the subshell and exit accordingly:

**Before:**
```shell
result=$(cmd && exit 1)
```

**After:**
```shell
result=$(cmd)
if [ $? -ne 0 ]; then exit 1; fi
```

## Difficulty
Medium (4/10)

## Category
Shellcheck Issues
