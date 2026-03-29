# WF-010: Document Stage Trigger Issue in performance-improver.yml

## Description
The `.github/workflows/performance-improver.yml` only has `schedule` or `workflow_dispatch` triggers. When running with `act` (local testing), it defaults to the `push` event and finds no stages to run.

## File
- `.github/workflows/performance-improver.yml`

## Error
```
Could not find any stages to run
```

## Note
This is primarily a local testing configuration issue. The workflow will work fine on GitHub Actions.

## Local Testing Workaround
Run `act` with the correct event:
```bash
act workflow_dispatch
act schedule
```

## Difficulty
Very Easy (1/10) - Local testing only

## Category
Runtime (act) Errors
