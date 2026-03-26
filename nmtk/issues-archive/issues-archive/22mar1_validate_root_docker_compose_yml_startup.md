# T1-5: Validate root docker-compose.yml startup (all 7 services)

- **Problem:** The root `docker-compose.yml` has never been tested end-to-end. Build contexts, healthchecks, profiles, and inter-service dependencies are unvalidated.
- **Fix:** Run `docker-compose up --build` and fix all issues. Test each profile:
  - Default profile (neurocnl, neurosim, neurochip)
  - `--profile full` (all 7 services)
  - `--profile physics` (neurocnl-physics variant)
- **Effort:** 2-4 hours (expect iterative fixes)
- **Verify:** All 7 services pass healthchecks, `scripts/validate_docker_compose.sh` passes, `scripts/demo_smoke_test.sh` passes
