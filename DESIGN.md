---
name: NeuroMorphicToolKit
description: Professional desktop suite for neuromorphic computing, where every layer of complexity is accessible on demand.
colors:
  # Brand primaries
  command-blue: "#1337EC"
  studio-violet: "#8B5CF6"
  studio-violet-light: "#7C3AED"
  instrument-cyan: "#06B6D4"
  instrument-teal: "#0F766E"
  # Semantic status (theme-invariant)
  state-healthy: "#22C55E"
  state-running: "#38BDF8"
  state-degraded: "#F59E0B"
  state-warning: "#F97316"
  state-error: "#EF4444"
  state-live: "#E11D48"
  # Dark surfaces
  shell-bg-dark: "#0B1020"
  top-bar-dark: "#101728"
  workspace-bar-dark: "#0D1424"
  utility-panel-dark: "#111A2C"
  canvas-dark: "#0A0F1D"
  chrome-border-dark: "#243044"
  subtle-border-dark: "#1A2436"
  metadata-dark: "#9BA8BC"
  # Light surfaces
  shell-bg-light: "#F3F5FA"
  top-bar-light: "#FFFFFF"
  workspace-bar-light: "#F7F9FC"
  utility-panel-light: "#FAFBFD"
  canvas-light: "#FFFFFF"
  chrome-border-light: "#D9E0EA"
  subtle-border-light: "#E7ECF3"
  metadata-light: "#5B677C"
typography:
  display:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.1
  headline:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.2
  title:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1.3
  body:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.4
    letterSpacing: "0.5px"
  mono:
    fontFamily: "JetBrains Mono, Menlo, Consolas, monospace"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.6
rounded:
  sm: "12px"
  md: "16px"
  lg: "22px"
  card: "24px"
  dialog: "28px"
  input: "12px"
  chip: "999px"
spacing:
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "24px"
  xl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.command-blue}"
    textColor: "#FFFFFF"
    rounded: "{rounded.md}"
    padding: "10px 20px"
  button-primary-hover:
    backgroundColor: "#0D2EC0"
    textColor: "#FFFFFF"
    rounded: "{rounded.md}"
    padding: "10px 20px"
  button-outlined:
    backgroundColor: "transparent"
    textColor: "{colors.command-blue}"
    rounded: "{rounded.md}"
    padding: "10px 20px"
  surface-card-dark:
    backgroundColor: "{colors.top-bar-dark}"
    rounded: "{rounded.card}"
    padding: "14px"
  surface-card-light:
    backgroundColor: "{colors.canvas-light}"
    rounded: "{rounded.card}"
    padding: "14px"
  workspace-chip-active:
    backgroundColor: "{colors.command-blue}"
    textColor: "#FFFFFF"
    rounded: "{rounded.chip}"
    padding: "5px 12px"
  workspace-chip-idle:
    backgroundColor: "{colors.workspace-bar-dark}"
    textColor: "{colors.metadata-dark}"
    rounded: "{rounded.chip}"
    padding: "5px 12px"
---

# Design System: NeuroMorphicToolKit

## 1. Overview

**Creative North Star: "The Transparent Machine"**

NMTK is a suite where complexity is accessible on demand at every level, not necessarily always visible. The user sees a calm, controlled workspace. Behind that surface, pipeline state, hardware diagnostics, and process telemetry are always one interaction away. The interface holds information in readiness; it does not broadcast it. State is a depth to be explored, not a layer to be negotiated.

The suite occupies a precise space between scientific instrument and modern professional tool. It has the visual discipline of precision equipment (readability at density, consistent status semantics, unambiguous state communication) without the aesthetic of a developer IDE, an enterprise console, or a consumer application. It is technically honest and visually composed. The surface is calm. The machine is capable.

NMTK presents two symmetrical themes: dark navy and light silver-blue. Neither is the default; both are fully specified. The dark theme runs on deep blue-navy grounds; the light theme runs on cool silver-white. Brand identity is identical across both. Three workbench modes (command, studio, instrument) share one family identity but carry distinct palette accents so the user always knows which surface they are on.

**Key Characteristics:**
- State accessible on demand, not broadcast: depth one interaction away, calm at surface
- Three workbench modes with distinct palette accents within one shared shape and type language
- Dense without cramped: hierarchy is clear, surfaces breathe, labels are readable at 12px
- Operationally honest: every status color has exactly one meaning, never used decoratively
- No ornamentation: every element earns its place or is removed

## 2. Colors: The Two-State Palette

The suite is defined by two parallel neutral families (dark navy and light silver-blue) and three mode accents. Status colors are a fourth layer, semantic and fixed. Every color in this system has a role; none is decorative.

### Primary

- **Command Blue** (`#1337EC`): The suite's identity color. Applied to primary actions, active navigation states, and command-mode chrome tinting. Used on the shell and Neurohub surfaces. Saturated and authoritative; it appears at no more than 15% of any given surface except in active selection states.

### Secondary

- **Studio Violet** (`#8B5CF6` dark / `#7C3AED` light): Accent for neurocnl and Neurosim surfaces. Applied to studio-mode top bar tint, active inspector headers, and running pipeline step indicators within those modules. Signals creative, authoring context.

- **Instrument Cyan / Teal** (`#06B6D4` dark / `#0F766E` light): Accent for Neurosense, Neurochip, and Neurobench surfaces. Applied to live data indicators, hardware status, and instrument-mode chrome. Signals observation and measurement context.

### Tertiary: Status Palette

The status palette is semantic and fixed. These six colors have one job each.

- **Healthy** (`#22C55E`): The system or module is operating normally.
- **Running** (`#38BDF8`): Actively executing; process in progress.
- **Degraded** (`#F59E0B`): Reduced capability or partial failure; the workflow can continue.
- **Warning** (`#F97316`): A threshold is approaching or a non-fatal issue requires attention.
- **Error** (`#EF4444`): The current workflow cannot continue without intervention.
- **Live** (`#E11D48`): Hardware is actively connected, recording, or streaming.

### Neutral: Dark Theme

- **Deep Void** (`#0A0F1D`): Module canvas background. The deepest surface layer.
- **Night Shell** (`#0B1020`): Primary shell background.
- **Command Midnight** (`#101728`): Top app bar background; one tonal step above the shell.
- **Module Frame** (`#0D1424`): Workspace bar background.
- **Panel Shadow** (`#111A2C`): Utility panel background.
- **Frame Seam** (`#243044`): Primary chrome border; separates surface layers.
- **Inner Seam** (`#1A2436`): Subtle border; used for internal divisions within a surface.
- **Instrument Text** (`#9BA8BC`): Metadata, labels, secondary content, chip text at rest.

### Neutral: Light Theme

- **Silver Field** (`#F3F5FA`): Primary shell background.
- **White Surface** (`#FFFFFF`): Top app bar background; module canvas.
- **Cool Fog** (`#F7F9FC`): Workspace bar background.
- **Whisper Panel** (`#FAFBFD`): Utility panel background.
- **Silver Seam** (`#D9E0EA`): Primary chrome border.
- **Light Seam** (`#E7ECF3`): Subtle internal border.
- **Slate Text** (`#5B677C`): Metadata, labels, secondary content in light theme.

### Named Rules

**The Semantic Purity Rule.** Status colors have one job each: communicating operational state. They are never used for decoration, emphasis, or branding. A green dot means the system is healthy. It does not mean "positive" in any other context. If you need to indicate success outside of operational state, use a weight-emphasized label, not the healthy green.

**The Mode Palette Rule.** Command blue, studio violet, and instrument cyan are applied only to their assigned modules. Chrome tinting follows mode assignment strictly. These assignments never cross. A studio surface never has command-blue chrome.

## 3. Typography

**UI Font:** Space Grotesk (system-ui, sans-serif fallback)
**Mono Font:** JetBrains Mono (Menlo, Consolas, monospace fallback)

**Character:** Space Grotesk brings geometric precision with just enough warmth to avoid coldness. Its slightly rounded terminals and compact proportions read cleanly at 12px, which is the operational density of this suite. A single typeface across all chrome creates coherence; the only typographic contrast is weight and size. JetBrains Mono handles all code, CNL specifications, terminal output, and numeric telemetry requiring column alignment. It never appears in navigation or status chrome.

### Hierarchy

- **Display** (700, 28px, 1.1): Module-level headers and major surface titles. Used sparingly.
- **Headline** (600, 20px, 1.2): Section headers within module surfaces and panel titles.
- **Title** (700, 16px, 1.3): Card headers, workspace labels, group headers. The primary within-surface heading level.
- **Body** (400, 14px, 1.5): All readable content: descriptions, documentation, form field text, pipeline step descriptions.
- **Label** (500, 12px, 1.4, 0.5px tracking): Status labels, metadata, chip text, navigation items. The workhorse at density.
- **Mono** (400, 13px, 1.6): Code, CNL spec text, terminal output, numeric telemetry requiring alignment.

### Named Rules

**The No-Oversize Rule.** Hierarchy comes from weight contrast before scale. Space Grotesk at w700 vs w400 is a sharp, clear visual jump. 28px is the ceiling. This is a professional workstation; it earns authority through precision, not scale.

**The Mono Boundary Rule.** JetBrains Mono is reserved for machine-generated content, user-authored code, and numerically significant data. Navigation labels, descriptions, and status text always use Space Grotesk.

## 4. Elevation

NMTK is flat by default. There are no box shadows. Depth is communicated entirely through surface tinting: in the dark theme, surfaces step from `#0A0F1D` (canvas, deepest) through `#0B1020` (shell) to `#101728` (top bar). In the light theme, the same logic applies through cool silver steps from `#F3F5FA` to `#FFFFFF`.

Cards and containers define their boundary with a 1px border at chrome-border opacity. They are placed on their surface with a seam, not lifted above it with a shadow.

### Surface Stacking (both themes)

- **Canvas**: Deepest layer. Module content lives here.
- **Shell frame**: One tonal step above canvas.
- **Bars**: Top app bar and workspace bar; one step above the frame.
- **Utility panel**: Adjacent to canvas; one step above the shell frame.
- **Cards and containers**: Placed on canvas. Border, not shadow, defines boundary.
- **Dialogs**: One tonal step above the top bar. Still no shadow.

### Named Rules

**The Flat-By-Default Rule.** Surfaces are flat at rest. State changes (hover, active, focus) produce tint shifts or border accents, not shadow introduction.

**The Border-Not-Shadow Rule.** Cards use a 1px border at `chrome-border` opacity to define their bounds. If an element needs to feel elevated, lighten its background by one tonal step. Do not add a shadow.

## 5. Components

Technical but accessible and simple. Components are precise and unobtrusive. They do not demand attention; they respond to it clearly.

### Buttons

- **Shape:** Gently rounded (16px radius). Substantial without being pill-shaped.
- **Primary:** Command-blue fill (`#1337EC`), white label, 10px/20px padding. Used for the definitive action in a workflow step.
- **Hover:** Background darkens to `#0D2EC0`; transition at 120ms ease-out.
- **Active / Press:** Scale to 0.96 at 120ms. Tactile without exaggeration.
- **Focus visible:** 2px offset outline in command-blue at 40% opacity.
- **Outlined:** Transparent background, command-blue border at 35% opacity, command-blue label. 18% tint on hover.
- **Toned variants:** The tone system (info, success, warning, danger, neutral) applies semantic color without changing shape. Character stays constant; only the color role changes.
- **Disabled:** 38% opacity on fill and label. No interaction feedback.

### Workspace Chips

Signature component. The primary navigation element inside the workspace bar.

- **Active:** Mode-tinted accent background (command-blue, studio-violet, or instrument-cyan per the module's assigned mode), white label, full pill radius (999px).
- **Idle:** Neutral tint background, metadata-color label, full pill radius.
- **Contents:** Module icon (14px) + label (12px, w500) + status dot (6px) + close affordance (12px icon).
- **Status dot:** Color maps directly to the six semantic states. Degraded and error states cause the dot to pulse (0.5x to 1.2x scale, 900ms, ease-in-out repeat). This is the only unsolicited animation in the suite.
- **Spacing:** 5px top/bottom, 12px left/right.

### Cards / Surface Containers

Cards delineate a bounded set of information or controls. They are not decorative.

- **Corner style:** Generously rounded (24px radius).
- **Background:** Dark theme: `top-bar-dark` (`#101728`). Light theme: `canvas-light` (`#FFFFFF`). Nested contexts use one step deeper.
- **Elevation:** Flat, zero elevation. 1px border at `chrome-border` (65% opacity) defines the boundary.
- **Internal padding:** 14px uniform. When a header is present, 10px separates it from body content.
- **Tone variants:** Cards accept the tone system (info, success, warning, danger) for contextual containers: diagnostic outputs, preflight result panels, deployment reports.

### Inputs / Fields

- **Style:** Filled or outlined Material 3 inputs at 12px radius.
- **Focus:** Border shifts to command-blue at full opacity. No glow.
- **Error:** Border and helper text shift to `state-error`. Error message appears inline below the field.
- **Disabled:** 38% opacity throughout.

### Navigation Destinations (Top App Bar)

- **Active:** Mode-accent background tint (20% opacity), mode-accent label and icon.
- **Inactive:** Transparent background, metadata-text label and icon.
- **Shape:** 16px radius chip inside the bar; not full pill, which distinguishes nav from workspace chips.
- **Hover:** 10% opacity neutral tint.
- **Typography:** Label scale (12–13px, w500).

### Shell Status Badge

Compact suite-level health indicator in the top app bar.

- **Structure:** 7px status dot + label text (12px, w500), tonal background, 12px radius.
- **States:** Maps to all six semantic state colors.
- **Degraded / Error:** Status dot pulses to draw attention without being disruptive.

### Named Rules

**The No-Nested-Cards Rule.** A card inside a card is always wrong. Use tonal sections, inline rows, or `subtle-border` dividers for internal hierarchy.

**The Inline-Over-Modal Rule.** Modals are for blocking decisions where the user cannot proceed without making a choice. Diagnostic detail, log output, configuration panels, and progressive disclosure use the utility panel or inline expansion. Exhaust those options before reaching for a modal.

## 6. Do's and Don'ts

### Do:

- **Do** apply mode palettes strictly: command blue for shell and Neurohub, studio violet for neurocnl and Neurosim, instrument cyan/teal for Neurosense, Neurochip, and Neurobench.
- **Do** use tonal depth (background tint steps) rather than shadows to communicate surface hierarchy.
- **Do** achieve typographic hierarchy through Space Grotesk weight contrast (w400 vs w700) before reaching for size differences.
- **Do** map every status indicator to one of the six semantic states: healthy, running, degraded, warning, error, live.
- **Do** make state accessible on demand: summary at surface, detail one interaction away.
- **Do** keep the top app bar at 52px and the workspace bar at 48px. Chrome is compact so the canvas dominates.
- **Do** use the pulsing status dot exclusively for degraded and error states.
- **Do** use JetBrains Mono for all code, CNL text, and column-aligned numeric telemetry; never for chrome.

### Don't:

- **Don't** let NMTK feel like a consumer SaaS (Canva, Wix): no marketing chrome, growth funnels, freemium onboarding wizards, or pastel animations.
- **Don't** let it feel like an Arduino IDE: no clunky, cramped, dated developer-tool aesthetic.
- **Don't** let it feel like a dark hacker terminal: no neon-on-black, no all-dark intimidation aesthetic.
- **Don't** let it feel like SAP, Salesforce, or Atlassian Jira: no grey form overload, no bureaucratic navigation chrome, no ticket-board framing.
- **Don't** let it feel like ZBrush or Blender: no toolbar overload, not every control visible at once.
- **Don't** let it feel like VS Code: NMTK is a workstation, not an editor with extensions.
- **Don't** use side-stripe borders: `border-left` or `border-right` greater than 1px as a colored accent on any card, list item, or callout.
- **Don't** animate layout properties (width, height, padding, margin). Animate opacity and transform only.
- **Don't** use status colors decoratively. `#22C55E` means healthy. `#EF4444` means error. Using them outside operational context corrupts the semantic.
- **Don't** flood the surface with detail state. Surface status is a summary. The user drills in for detail. The principle is "accessible on demand," not "always visible."
- **Don't** nest cards. Use tonal sections, `subtle-border` dividers, or inline rows instead.
- **Don't** reach for a modal first. The utility panel, inline expansion, and progressive disclosure resolve most cases.
- **Don't** use gradient text (`background-clip: text` with a gradient). Use solid color and weight for emphasis.
