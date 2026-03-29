# WF-003: Fix SC2129 Shellcheck Style Issue in reusable-status-audit.yml

## Description
Style suggestion to group redirects more cleanly. The `.github/workflows/reusable-status-audit.yml` and `.github/workflows/sdd-context-bridge.yml` have unoptimized redirection statements.

## Files
- `.github/workflows/reusable-status-audit.yml`
- `.github/workflows/sdd-context-bridge.yml`

## Error
```
SC2129: Consider using { cmd1; cmd2; } >> file
```

## Fix
Refactor redirects to group commands:

**Before:**
```shell
echo "line1" >> file
echo "line2" >> file
```

**After:**
```shell
{ echo "line1"; echo "line2"; } >> file
```

## Difficulty
Easy (1/10)

## Category
Shellcheck Issues
