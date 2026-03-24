# T1-6: End-to-end launcher flow test

- **Problem:** The neuro_toolkit launcher has real process management but the full flow (install module → launch backend → WebView loads UI) has not been tested on a real machine.
- **Fix:** Test on macOS:
  1. `cd nmtk/neuro_toolkit && flutter run -d macos`
  2. Browse catalog → Install neurocnl → Launch → Verify WebView loads
  3. Test stop/restart cycle
  4. Test multiple modules running simultaneously
- **Effort:** 1 day
- **Verify:** Can complete the full demo walkthrough from DEMO_WALKTHROUGH.md using the launcher
