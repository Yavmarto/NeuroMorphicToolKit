# WF-005: Fix Untrusted Context Variable in pr-labeler.yml

## Description
Directly using `github.head_ref` in inline scripts is a security risk for script injection. The `.github/workflows/pr-labeler.yml` (Line 24) references this potentially untrusted context variable in a script.

## File
- `.github/workflows/pr-labeler.yml` (Line 24)

## Error
```
Expression/Context Error: github.head_ref is potentially untrusted
```

## Fix
Pass untrusted context variables through environment variables:

**Before:**
```yaml
- name: Use head ref
  run: echo ${{ github.head_ref }}
```

**After:**
```yaml
- name: Use head ref
  env:
    HEAD_REF: ${{ github.head_ref }}
  run: echo "$HEAD_REF"
```

## Security Impact
High - Prevents potential script injection attacks

## Difficulty
Medium (4/10)

## Category
Expression and Context Errors
