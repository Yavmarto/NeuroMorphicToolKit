# WF-008: Document Stage Trigger Issue in stale-branches.yml

## Description
The `.github/workflows/stale-branches.yml` only has `schedule` or `workflow_dispatch` triggers. When running with `act` (local testing), it defaults to the `push` event and finds no stages to run.

## File
- `.github/workflows/stale-branches.yml`

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
