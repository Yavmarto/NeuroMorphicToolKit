# End-to-End Launcher Test

**Priority:** Tier 1 — Blocks Demo Quality
**Estimated Effort:** 1 day
**Source:** v4 Audit Report (2026-03-20)

## Problem

The full launcher flow — install a module, launch its backend, display its UI in WebView — has not been tested on a real device. The ProcessManager (venv creation, pip install, uvicorn startup) and WebView integration need real-device validation.

## Acceptance Criteria

- [ ] Install neurocnl from the module catalog
- [ ] Verify venv is created and `pip install -e .` succeeds
- [ ] Verify uvicorn subprocess starts and health polling detects it
- [ ] Verify WebView loads the module's frontend UI
- [ ] Verify tab management works (open multiple modules, switch tabs, close tabs)
- [ ] Verify fallback to system browser works when WebView fails
- [ ] Test on macOS (primary target)
- [ ] Document any platform-specific issues encountered
