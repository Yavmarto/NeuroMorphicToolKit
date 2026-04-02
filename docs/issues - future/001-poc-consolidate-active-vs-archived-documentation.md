# [POC-01] Consolidate Active vs Archived Documentation Sources

**Module**: docs
**Phase**: POC
**Priority**: P0
**Effort**: Medium (2 days)
**Labels**: `docs`, `phase:poc`, `priority:critical`, `documentation`, `governance`
**Source**: 02-Apr-2026 folder review

## Problem

The `docs/` tree mixes active guidance, historical audit reports, and multiple generations of pipeline material (`unified-dev-pipeline`, `Opus-dev-pipeline`, `Gemini-dev-pipeline`, and archived variants). Contributors can currently land in superseded material without a clear signal about what is authoritative.

## Acceptance Criteria

- [ ] Define which top-level documentation areas are active, archived, or deprecated
- [ ] Add explicit status banners or notes to superseded pipeline directories
- [ ] Cross-link active docs to the correct canonical replacements
- [ ] Ensure the root `docs/README.md` points only to active documentation as the default path
- [ ] Identify any duplicated files that should be archived or removed later
- [ ] Document the rule for when a doc belongs in `archive/` versus an active folder
