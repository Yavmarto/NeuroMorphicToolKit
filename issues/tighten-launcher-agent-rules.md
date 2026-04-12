---
title: "Tighten Root and NMTK Agent Rules for Launcher Work"
labels: ["launcher", "agents", "policy", "nmtk"]
---

# Goal
Define launcher-specific process requirements in root `AGENTS.md` and `nmtk/AGENTS.md` so agent-driven launcher work follows the same stop conditions and required checks.

# Scope
- require `modules.json` changes to update launcher Dart models, launcher tests, and consuming helper scripts in the same change
- require doctor or preflight coverage for any new install or startup strategy
- preserve optional dependency semantics so optional hardware or framework dependencies do not become fatal unless the manifest marks them required
- require launcher doctor and launcher unit coverage before launcher work can be marked complete

# Deliverables
- aligned launcher rules in root `AGENTS.md`
- aligned launcher rules in `nmtk/AGENTS.md`
- explicit non-conflicting stop conditions for launcher work

# Acceptance Criteria
- [ ] Root and `nmtk` agent instructions define compatible launcher workflow requirements.
- [ ] `modules.json` synchronization requirements are explicit across manifest, launcher models, helper scripts, and tests.
- [ ] New install or startup strategies cannot be introduced without doctor or preflight coverage requirements.
- [ ] Launcher completion criteria require launcher doctor and launcher unit coverage.

# Depends On
- [launcher-doctor-required-gate.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/launcher-doctor-required-gate.md)
