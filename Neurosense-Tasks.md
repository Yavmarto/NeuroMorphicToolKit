# Neurosense — Concrete Tasks to 100% POC Readiness

1. **Integration Test Frontend to Backend**
   - *Description:* The frontend has grown significantly (2,249 LOC). Write integration tests to verify the 4 new Riverpod providers correctly deserialize data from the FastAPI backend.
   - *Impact:* Ensures the live signal viewer doesn't crash on real data.

2. **Add Widget Tests**
   - *Description:* Write `flutter test` cases for `DeviceSelector`, `SignalViewer`, and `RecordingControls`. Currently, test coverage is 0%.
   - *Impact:* Enforces CI stability and prevents regressions as the UI evolves.

3. **Verify OpenBCI Hardware Bridge**
   - *Description:* If physical hardware is available, run a live end-to-end test from the OpenBCI headset -> Neurosense backend -> Spike Encoding -> UI Viewer.
   - *Impact:* Proves the sensory encoding pipeline works in the real world.
