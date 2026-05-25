# Product

## Register

product

## Users

Two interlocking personas, both first-class:

**The researcher** (PhD student, neuroscientist, ML engineer): defines network architectures in natural English via the CNL, runs simulation pipelines, reviews results, iterates on biological constraints. Sessions are long, exploratory, and context-heavy. They may not know hardware; they need the system to bridge the gap.

**The hardware engineer**: selects and deploys to neuromorphic targets (Loihi, SpiNNaker, PYNQ, edge chips), compares benchmark results, investigates power/latency tradeoffs, validates quantized models. Sessions are focused and action-oriented. They need instrumentation, not onboarding.

Both users share one expectation: the tool should not require a terminal, a .env file, or a pip install. The complexity of local orchestration, Docker, Python environments, and inter-module communication is invisible by design.

## Product Purpose

NeuroMorphicToolKit (NMTK) is a professional desktop suite that unifies the full neuromorphic computing workflow: SNN authoring, visual simulation, sensory encoding, hardware deployment, benchmarking, and community artifact sharing. It exists because the field is inherently multidisciplinary and currently fragmented across incompatible tools, formats, and skill domains.

Success looks like: a neuroscientist describes a network in English, validates it, simulates it, and hands it to a hardware engineer who deploys it to a physical chip, benchmarks it, and publishes the result, all within one application, without either person needing the other's domain expertise.

## Brand Personality

**Transparent, Fluent, Precise.**

The suite should feel magically easy without hiding what is actually happening. Users should always be able to go one level deeper and see the real state: what the pipeline is doing, what the hardware is reporting, where the model is in compilation. Complexity is accessible, not abstracted away.

Tone: professional without being cold. Expert without being elitist. Precise without being intimidating. The interface treats the user as a capable professional and gets out of the way.

The suite should not explain itself; it should show itself.

## Anti-references

Do not let NMTK feel like any of the following:

- **Consumer SaaS** (Canva, Wix): no marketing chrome, no growth funnels, no freemium onboarding wizards, no pastel "delight"
- **Arduino IDE**: no clunky, outdated developer-tool aesthetic; not cramped, not 2010
- **Dark hacker terminal**: not elitist all-black CLI cosplay; not neon-on-black; not intimidating by aesthetic choice
- **Legacy enterprise tools** (SAP, Salesforce, Altova Mapforce): no grey form overload, no bureaucratic nav chrome, no 90s enterprise UI
- **Project management chrome** (Jira, Atlassian): not ticket-driven, not cluttered filter bars, not sprint-board framing
- **3D artist tool overload** (ZBrush, Blender): not every control visible at once, not segmented panel chaos, not toolbar-heavy
- **Text editor** (VS Code): not IDE chrome; NMTK is a workstation, not an editor with extensions

## Design Principles

1. **Show, don't hide.** The system makes complex state legible at every moment. Pipeline steps, backend readiness, hardware status, and running processes are visible in-place. Users can always go one level deeper without leaving context.

2. **Workflow over screens.** Navigation follows what users are trying to accomplish (design → validate → deploy → benchmark), not what features exist. The suite is organized around the shape of work, not around a feature catalog.

3. **One suite, distinct workbenches.** The shell is mission control; each module has its own specialized interaction character. A consistent family identity does not mean identical chrome. Researchers get studio surfaces; engineers get instrument panels.

4. **Expertise scales, character stays.** The interface works for a researcher who has never touched hardware and for an engineer who lives in chip specs. Neither persona should feel like a secondary citizen. Depth is always available; it is never forced.

5. **Invisible orchestration.** The complexity of local service management, environment isolation, and inter-module communication must never surface as the user's problem. The product's ambition is to make sophisticated infrastructure feel like nothing.

## Accessibility & Inclusion

WCAG AA as the baseline for all surfaces. Both user personas may include people with reduced motion sensitivity or color vision differences; state communication should never rely on color alone. Dense technical surfaces (instrument mode, benchmark comparisons) must remain readable at the compact sizes they require without sacrificing contrast.

## Design System Foundation

NMTK Flutter uses **Zeta** (Zebra's design system, `zeta_flutter ^1.4.5`) as its foundation layer. Zeta provides the primitive color swatches, semantic color tokens, spacing primitives, radius primitives, and ready-made components (ZetaButton, ZetaTextInput, ZetaAvatar, ZetaStatusLabel, etc.).

NMTK extends Zeta with its own identity layer: Command Blue (`#1337EC`) replaces Zeta's default primary; the three workbench-mode accents (command blue, studio violet, instrument cyan) and the six semantic status colors are NMTK-specific overrides applied on top of Zeta's semantic token structure.

**What Zeta owns:** primitives (blue, green, red, teal, purple, orange, yellow, cool, warm swatches); semantic structure (mainPrimary, mainPositive, mainNegative, mainWarning, mainInfo, surface*, border*, state*); base component styling (ZetaButton, etc.); IBM Plex Sans as the Zeta-spec typeface reference.

**What NMTK overrides:** primary color seed to Command Blue; UI font to Space Grotesk (retains IBM Plex as fallback); module-mode accents; shell surface stack (dark navy / light silver-blue); status color palette (healthy, running, degraded, warning, error, live); workbench chrome tokens (NmtkShellTokens).

**Usage pattern:** every module MaterialApp is wrapped in `NmtkZetaTheme.wrap(...)`, which injects a ZetaProvider pre-configured with the NMTK custom theme. Module widgets may call `Zeta.of(context).colors` for semantic tokens or `NmtkShellTokens.of(context)` for shell-specific tokens.
