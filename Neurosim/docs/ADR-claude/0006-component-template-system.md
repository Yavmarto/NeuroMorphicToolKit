# ADR 0006: Component Template System

## Status
Accepted

## Context
Users building SNN models on the canvas need starter templates for common network patterns (e.g., winner-take-all, lateral inhibition, feedforward classification) rather than constructing every model from scratch.

## Decision
Implement a template system that loads starter templates from JSON files on disk via the `templates.py` router. Templates are defined as `StarterTemplate` schemas containing pre-configured `CanvasGraph` structures with labeled nodes, edges, and default parameters. A `TemplateSummary` schema provides lightweight metadata for template browsing.

## Consequences
- **Positive:** Templates accelerate onboarding and reduce errors in common network patterns; JSON-based storage enables templates to be version-controlled and contributed by the community.
- **Negative:** No template versioning mechanism — template schema changes can break stored templates; templates are read-only at runtime with no user customization or parameterization before instantiation.

## Status Update (2026-07-16 audit)
The example template set cited in this ADR's Context (winner-take-all, lateral inhibition, feedforward classification) never actually shipped. `neurocnl/neurosim/templates/` contains only `reflex_arc.json` and `cpg_oscillator.json` (plus `__init__.py`), confirmed via directory listing. The similarly-named files under `neurocnl/neurosim/components/patterns/` — `winner_take_all.json`, `lateral_inhibition.json`, plus copies of `cpg_oscillator.json` and `reflex_arc.json` — are all confirmed 0-byte stub files (`wc -c` on all four returns 0), and a grep of `neurocnl/neurosim/app/` for `winner_take_all` and `lateral_inhibition` returns zero matches, confirming they are not referenced anywhere in application code. The template-loading mechanism (`templates.py` router, `StarterTemplate`/`TemplateSummary` schemas) described in the Decision is otherwise still in place; only the roster of shipped example templates differs from what this ADR implies.
