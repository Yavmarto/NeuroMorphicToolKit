# Create POC Demo Walkthrough Script

**Priority:** High — POC Enhancement  
**Type:** Documentation  
**Tier:** 2 (Should Do)  
**Estimated Effort:** 1 day  

## Description

Create a guided demo script that walks through the full POC scenario. This should be both a human-readable walkthrough document AND an executable shell script that verifies each step programmatically.

## Requirements

### 1. Demo Walkthrough Document (`DEMO_WALKTHROUGH.md`)

Write a step-by-step guided demo covering:

1. **Start the suite:** `docker compose up` (or individual `uvicorn` commands)
2. **Open the launcher:** `flutter run -d macos` in `nmtk/neuro_toolkit/`
3. **Browse the catalog:** Show all 7 modules available
4. **Install neurocnl:** Click Install, watch real venv creation + dependency install
5. **Launch neurocnl:** Click Launch, see the Studio frontend open in WebView
6. **Write a CNL spec:** Type a simple reflex arc spec in the editor
7. **Validate:** See Layer 1 invariant validation results
8. **Simulate:** Run a simulation, view spike raster plot
9. **Export:** Export to C header format for hardware
10. **Show Neurosim:** Launch Neurosim, show the canvas with placed populations
11. **Show Neurochip:** Launch Neurochip, show constraint analysis for Teensy 4.1

### 2. Smoke Test Script (`scripts/demo_smoke_test.sh`)

An executable script that validates the POC works:
```bash
#!/bin/bash
# 1. Start backends
# 2. Wait for health checks
# 3. POST a CNL spec to /api/parse
# 4. POST to /api/validate
# 5. POST to /api/simulate
# 6. Verify all return 200
# 7. Cleanup
```

## Acceptance Criteria

- `DEMO_WALKTHROUGH.md` is clear enough for a non-developer to follow
- `scripts/demo_smoke_test.sh` exits 0 when all backends are healthy
- Smoke test runs in < 60 seconds
- Screenshots/placeholders marked for where to add UI screenshots

## Files Affected

```
DEMO_WALKTHROUGH.md                          ← new (root level)
scripts/demo_smoke_test.sh                   ← new
```
