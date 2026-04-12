---
title: "Extend Coding Style Guide with Launcher and Runtime Safety Requirements"
labels: ["launcher", "style-guide", "runtime", "root"]
---

# Goal
Make launcher and runtime safety an explicit cross-repo quality bar in `CODING_STYLE_GUIDE.md` without changing the authority order defined by the nearest `AGENTS.md`.

# Scope
- require startup paths to fail early and actionably instead of surfacing late crashes
- require launcher state, manifests, models, helper scripts, and tests to stay synchronized
- require optional runtimes to remain optional at import and startup time unless explicitly marked required
- require structured, machine-readable launcher diagnostics instead of ad hoc shell output for supported operator-facing paths
- require launcher verification for launcher and control-plane changes, with root integration tests for suite-visible contract changes

# Deliverables
- launcher/runtime integrity section in `CODING_STYLE_GUIDE.md`
- explicit statement of how the style guide complements rather than replaces `AGENTS.md`
- verification expectations for launcher-only versus suite-visible changes

# Acceptance Criteria
- [ ] The style guide states concrete launcher/runtime safety expectations rather than general guidance.
- [ ] The document preserves the existing authority order and does not conflict with `AGENTS.md`.
- [ ] Optional runtime handling and structured diagnostics requirements are explicit.
- [ ] Verification guidance distinguishes launcher-local checks from suite-visible integration requirements.

# Depends On
- [launcher-doctor-required-gate.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/launcher-doctor-required-gate.md)
