---
title: "Align Human and Agent Launcher Workflow Instructions Across Docs"
labels: ["launcher", "docs", "contributors", "root"]
---

# Goal
Ensure human onboarding and agent bootstrap docs give the same launcher workflow instructions and required checks for root control-plane work.

# Scope
- update `docs/jules/JULES_WORKSPACE_GUIDE.md`
- update `scripts/jules_bootstrap_workspace.sh`
- update `CONTRIBUTING.md`
- require each surface to direct launcher contributors to read `AGENTS.md`, `CODING_STYLE_GUIDE.md`, and `nmtk/AGENTS.md`
- require each surface to reference launcher doctor, launcher unit tests, and root integration tests when suite-visible launcher behavior changes

# Deliverables
- synchronized launcher workflow guidance in all three contributor surfaces
- a shared command set for launcher readiness and verification
- clear decision boundary for when root integration tests are required

# Acceptance Criteria
- [ ] All three docs reference the same prerequisite reads for launcher work.
- [ ] All three docs reference the same launcher verification commands.
- [ ] The decision boundary for running root integration tests is consistent across the docs.
- [ ] Human and agent instructions no longer diverge on launcher readiness expectations.

# Depends On
- [launcher-doctor-required-gate.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues-archive/launcher-doctor-required-gate.md)
- [launcher-quality-bar-in-coding-style-guide.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues-archive/launcher-quality-bar-in-coding-style-guide.md)
