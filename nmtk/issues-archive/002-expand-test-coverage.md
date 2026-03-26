# Expand Test Coverage

**Priority:** P2-Medium
**Effort:** 1-2 days
**Labels:** testing

## Problem
Only 2 test files exist for ~3-4K LOC. ProcessManager (with abstract ProcessRunner base class) and ModuleProvider are untested. These are critical components — if the launcher crashes, the entire POC fails.

## Acceptance Criteria
- [ ] Unit tests for ProcessManager (mock process spawning)
- [ ] Unit tests for ModuleProvider (state transitions)
- [ ] Unit tests for BundleManager
- [ ] Widget tests for Catalog and Dashboard screens
- [ ] At least 10 new tests
- [ ] `flutter test` passes

## Notes
Maps to POC-100-TASKS.md T3-4.
