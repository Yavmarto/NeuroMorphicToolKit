---
title: Replace mocked update checks with real version sources
priority: 2
module: nmtk
status: Open
---

# Objective
Make launcher and module update status reflect real release metadata instead of fixed demo values.

# Description
`nmtk/neuro_toolkit/lib/services/update_service.dart` still uses simulated delays and hard-coded remote versions such as `1.1.0`, `1.0.1`, and synthetic beta or nightly strings. That means the launcher can report update availability without consulting any real manifest or release source, which makes module-management state untrustworthy and can generate false positives or miss real updates entirely.

# Acceptance Criteria
- [ ] Fetch launcher and module version metadata from a real source of truth such as the module manifest or release API.
- [ ] Remove the hard-coded demo versions and simulated remote checks from production update flows.
- [ ] Handle offline failures, version-pinned modules, and prerelease channels with deterministic tests.
