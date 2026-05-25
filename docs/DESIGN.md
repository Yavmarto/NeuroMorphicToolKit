---
name: NeuroMorphicToolKit
description: Professional desktop suite for neuromorphic computing, where every layer of complexity is accessible on demand.

# ── ZETA PRIMITIVES ──────────────────────────────────────────────────────────
# Source: zeta_flutter_theme 1.3.0 / ZetaPrimitivesDark + ZetaPrimitivesLight
# shade60 = dark-theme primary; shade60 in light = lighter, shade-60 light is
# the authoritative light primary per Zeta convention.
# All values are directly from the generated primitives.g.dart.

zeta_primitives:
  blue:
    dark_primary:  "#599fe5"   # shade60 dark
    light_primary: "#0073e6"   # shade60 light
    shades_dark:   ["#101b25","#002c58","#004d99","#0061c2","#0073e6","#599fe5","#7ebeff","#b7dbff","#e2f1ff","#f1f8ff"]
    shades_light:  ["#f1f8ff","#e2f1ff","#b7dbff","#7ebeff","#599fe5","#0073e6","#0061c2","#004d99","#002c58","#101b25"]
  green:
    dark_primary:  "#67b796"
    light_primary: "#00864f"
    shades_dark:   ["#081711","#00331e","#005f38","#006d3f","#00864f","#67b796","#84dab6","#beefdb","#d8ffef","#ecfff7"]
    shades_light:  ["#ecfff7","#d8ffef","#beefdb","#84dab6","#67b796","#00864f","#006d3f","#005f38","#00331e","#081711"]
  red:
    dark_primary:  "#f36170"
    light_primary: "#d70015"
    shades_dark:   ["#220f11","#520008","#8f000e","#b50012","#d70015","#f36170","#f98c97","#ffb3bb","#ffe1e4","#fff0f1"]
    shades_light:  ["#fff0f1","#ffe1e4","#ffb3bb","#f98c97","#f36170","#d70015","#b50012","#8f000e","#520008","#220f11"]
  teal:
    dark_primary:  "#65c4c4"
    light_primary: "#1a8080"
    shades_dark:   ["#0a1616","#003535","#005b5b","#017474","#1a8080","#65c4c4","#91e1e1","#bcfbfb","#d9ffff","#ecffff"]
    shades_light:  ["#ecffff","#d9ffff","#bcfbfb","#91e1e1","#65c4c4","#1a8080","#017474","#005b5b","#003535","#0a1616"]
  purple:
    dark_primary:  "#9b71df"
    light_primary: "#7e0cff"
    shades_dark:   ["#180f22","#260052","#43008f","#6400d6","#7e0cff","#9b71df","#cea4ff","#dcc1fb","#efe1ff","#f7f0ff"]
    shades_light:  ["#f7f0ff","#efe1ff","#dcc1fb","#cea4ff","#9b71df","#7e0cff","#6400d6","#43008f","#260052","#180f22"]
  orange:
    dark_primary:  "#d78d26"
    light_primary: "#ae6500"
    shades_dark:   ["#1e1100","#402600","#764502","#965802","#ae6500","#d78d26","#ffb348","#ffd292","#ffe7c6","#fef2e2"]
    shades_light:  ["#fef2e2","#ffe7c6","#ffd292","#ffb348","#d78d26","#ae6500","#965802","#764502","#402600","#1e1100"]
  yellow:
    dark_primary:  "#c2a728"
    light_primary: "#8d7400"
    shades_dark:   ["#181400","#352b00","#564908","#766200","#8d7400","#c2a728","#dbb91c","#f3d961","#ffea89","#fff7d4"]
    shades_light:  ["#fff7d4","#ffea89","#f3d961","#dbb91c","#c2a728","#8d7400","#766200","#564908","#352b00","#181400"]
  cool:
    dark_primary:  "#8d95a3"
    light_primary: "#7a8190"
    shades_dark:   ["#0c0d0e","#1d1e23","#2c2f36","#545963","#7a8190","#8d95a3","#bbc1cb","#e0e3e9","#f3f6fa","#f8fbff"]
    shades_light:  ["#f8fbff","#f3f6fa","#e0e3e9","#ced2db","#8d95a3","#7a8190","#545963","#2c2f36","#1d1e23","#0c0d0e"]
  warm:
    dark_primary:  "#b9b9b9"
    light_primary: "#858585"
    shades_dark:   ["#151519","#1d1e23","#313131","#585858","#858585","#b9b9b9","#dedede","#ececec","#f6f6f6","#fafafa"]
    shades_light:  ["#fafafa","#f6f6f6","#ececec","#dedede","#b9b9b9","#858585","#585858","#313131","#1d1e23","#151519"]
  pink:
    dark_primary:  "#ee78c3"
    light_primary: "#d30589"

# ── ZETA SPACING SEMANTICS ───────────────────────────────────────────────────
# Source: Zeta spacing docs + primitives.g.dart
zeta_spacing:
  none:    0    # Zeta.of(context).spacing.none
  minimum: 4    # Zeta.of(context).spacing.minimum
  small:   8    # Zeta.of(context).spacing.small
  medium:  12   # Zeta.of(context).spacing.medium
  large:   16   # Zeta.of(context).spacing.large
  xl:      20   # Zeta.of(context).spacing.xl
  2xl:     24
  3xl:     28
  4xl:     32
  5xl:     36
  6xl:     40
  7xl:     44
  8xl:     48
  9xl:     64
  10xl:    80
  11xl:    96

# ── ZETA RADIUS SEMANTICS ────────────────────────────────────────────────────
# Source: Zeta radius docs + primitives.g.dart
zeta_radius:
  none:    0    # Zeta.of(context).radius.none
  minimal: 4    # Zeta.of(context).radius.minimal
  rounded: 8    # Zeta.of(context).radius.rounded
  large:   16   # Zeta.of(context).radius.large
  xl:      24   # Zeta.of(context).radius.xl
  full:    360  # Zeta.of(context).radius.full

# ── NMTK BRAND OVERRIDES (applied on top of Zeta) ───────────────────────────
colors:
  # Primary identity — Command Blue replaces Zeta's default blue primary
  command-blue: "#1337EC"          # ZetaCustomTheme(id:'nmtk', primary: Color(0xFF1337EC))
  command-blue-hover: "#0D2EC0"
  command-blue-press: "#0B28A8"

  # Module-mode accents (no Zeta primitive maps to these directly)
  studio-violet: "#8B5CF6"         # dark mode
  studio-violet-light: "#7C3AED"   # light mode
  instrument-cyan: "#06B6D4"       # dark mode
  instrument-teal: "#0F766E"       # light mode

  # Operational status — semantic, fixed, never decorative
  state-healthy:  "#22C55E"
  state-running:  "#38BDF8"
  state-degraded: "#F59E0B"
  state-warning:  "#F97316"
  state-error:    "#EF4444"
  state-live:     "#E11D48"

  # Dark surface stack (deep blue-navy family)
  shell-bg-dark:          "#0B1020"
  top-bar-dark:           "#101728"
  workspace-bar-dark:     "#0D1424"
  utility-panel-dark:     "#111A2C"
  canvas-dark:            "#0A0F1D"
  chrome-border-dark:     "#243044"
  subtle-border-dark:     "#1A2436"
  metadata-dark:          "#9BA8BC"

  # Light surface stack (cool silver-blue family)
  shell-bg-light:         "#F3F5FA"
  top-bar-light:          "#FFFFFF"
  workspace-bar-light:    "#F7F9FC"
  utility-panel-light:    "#FAFBFD"
  canvas-light:           "#FFFFFF"
  chrome-border-light:    "#D9E0EA"
  subtle-border-light:    "#E7ECF3"
  metadata-light:         "#5B677C"

# ── TYPOGRAPHY ───────────────────────────────────────────────────────────────
# Zeta spec: IBM Plex Sans. NMTK override: Space Grotesk for all UI chrome.
# JetBrains Mono for all code / CNL / numeric telemetry.
typography:
  display:
    fontFamily: "Space Grotesk, IBM Plex Sans, system-ui, sans-serif"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.1
  headline:
    fontFamily: "Space Grotesk, IBM Plex Sans, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.2
  title:
    fontFamily: "Space Grotesk, IBM Plex Sans, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1.3
  body:
    fontFamily: "Space Grotesk, IBM Plex Sans, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Space Grotesk, IBM Plex Sans, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.4
    letterSpacing: "0.5px"
  mono:
    fontFamily: "JetBrains Mono, Menlo, Consolas, monospace"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.6

# ── RADIUS (NMTK semantic names → Zeta semantic values) ──────────────────────
# NMTK name  → Zeta semantic → dp value
rounded:
  sm:     "12px"   # between Zeta rounded(8) and large(16); used for inputs, nav chips
  md:     "16px"   # Zeta large — buttons, nav destinations
  lg:     "22px"   # between Zeta xl(24) and large; utility panels
  card:   "24px"   # Zeta xl — cards, dialogs
  dialog: "28px"
  input:  "8px"    # Zeta rounded
  chip:   "360px"  # Zeta full — workspace chips, full pills

# ── SPACING (NMTK semantic → Zeta semantic) ──────────────────────────────────
spacing:
  xs:   "8px"    # Zeta small
  sm:   "12px"   # Zeta medium
  md:   "16px"   # Zeta large
  lg:   "24px"   # Zeta 2xl
  xl:   "32px"   # Zeta 4xl

# ── COMPONENTS ───────────────────────────────────────────────────────────────
components:
  button-primary:
    backgroundColor: "{colors.command-blue}"
    textColor: "#FFFFFF"
    rounded: "{rounded.md}"
    padding: "10px 20px"
    zetaComponent: "ZetaButton"
  button-primary-hover:
    backgroundColor: "{colors.command-blue-hover}"
    textColor: "#FFFFFF"
  button-outlined:
    backgroundColor: "transparent"
    textColor: "{colors.command-blue}"
    rounded: "{rounded.md}"
    padding: "10px 20px"
    zetaComponent: "ZetaButton(type: ZetaButtonType.outline)"
  surface-card-dark:
    backgroundColor: "{colors.top-bar-dark}"
    rounded: "{rounded.card}"
    padding: "14px"
    border: "1px solid rgba(36,48,68,0.65)"
    zetaComponent: "ZetaCardContainer / SurfaceCard"
  surface-card-light:
    backgroundColor: "{colors.canvas-light}"
    rounded: "{rounded.card}"
    padding: "14px"
    border: "1px solid rgba(217,224,234,0.65)"
  workspace-chip-active:
    backgroundColor: "{colors.command-blue}"
    textColor: "#FFFFFF"
    rounded: "{rounded.chip}"
    padding: "5px 12px"
  workspace-chip-idle:
    backgroundColor: "rgba(155,168,188,0.10)"
    textColor: "{colors.metadata-dark}"
    rounded: "{rounded.chip}"
    padding: "5px 12px"
---

# Design System: NeuroMorphicToolKit

## 1. Overview

**Creative North Star: "The Transparent Machine"**

NMTK is a suite where complexity is accessible on demand at every level. The user sees a calm, controlled workspace. Behind that surface, pipeline state, hardware diagnostics, and process telemetry are always one interaction away. The interface holds information in readiness; it does not broadcast it.

The suite occupies a precise space between scientific instrument and modern professional tool: the visual discipline of precision equipment without the aesthetic of a developer IDE, an enterprise console, or a consumer application.

**Foundation:** Zeta (`zeta_flutter ^1.4.5`) — Zebra's design system — provides the primitive color swatches, semantic color tokens, spacing and radius primitives, and ready-made components. NMTK extends Zeta with a custom theme (`id: 'nmtk'`, primary: Command Blue `#1337EC`) and its own shell token layer (`NmtkShellTokens`).

**Key Characteristics:**
- State accessible on demand, not broadcast
- Three workbench modes with distinct palette accents (command, studio, instrument)
- Dense without cramped: hierarchy is clear, labels readable at 12px
- Operationally honest: every status color has exactly one meaning
- No ornamentation: every element earns its place

---

## 2. Color System

### 2.1 Zeta Primitive Swatches

Zeta provides ten color families on a 10-swatch scale (10–100), inverted between light and dark. In dark mode shade 60 is the primary; in light mode it is also shade 60, but the ramp is reversed so shade 60 is a saturated mid-tone.

**NMTK never uses Zeta primitive swatches directly in production UI.** They are used only to construct semantic tokens and NMTK's own NmtkShellTokens.

| Swatch | Dark primary (shade60) | Light primary (shade60) |
|--------|------------------------|------------------------|
| Blue   | `#599fe5` | `#0073e6` |
| Green  | `#67b796` | `#00864f` |
| Red    | `#f36170` | `#d70015` |
| Teal   | `#65c4c4` | `#1a8080` |
| Purple | `#9b71df` | `#7e0cff` |
| Orange | `#d78d26` | `#ae6500` |
| Yellow | `#c2a728` | `#8d7400` |
| Cool   | `#8d95a3` | `#7a8190` |
| Warm   | `#b9b9b9` | `#858585` |
| Pink   | `#ee78c3` | `#d30589` |

### 2.2 Zeta Semantic Tokens

Accessed at runtime via `Zeta.of(context).colors`. The semantic layer maps automatically to light/dark primitives. Key tokens:

- `mainPrimary` → Command Blue `#1337EC` (NMTK override via `ZetaCustomTheme`)
- `mainPositive` → maps to Zeta green
- `mainNegative` → maps to Zeta red
- `mainWarning` → maps to Zeta yellow
- `mainInfo` → maps to Zeta blue
- `surfaceDefault`, `surfacePrimary`, `surfacePositive`, etc. → Zeta-managed surface layers
- `borderDefault`, `borderPrimary`, `borderSubtle` → Zeta-managed border tokens

### 2.3 NMTK Brand Layer

Applied on top of Zeta semantics via `NmtkShellTokens` (a Flutter `ThemeExtension`).

#### Primary

**Command Blue** (`#1337EC`): Suite identity. Primary actions, active navigation, command-mode chrome. Applied via `ZetaCustomTheme(id: 'nmtk', primary: Color(0xFF1337EC))`.

#### Mode Accents

| Mode | Surface | Dark accent | Light accent |
|------|---------|-------------|--------------|
| Command | Shell, Neurohub | `#1337EC` | `#1337EC` |
| Studio | neurocnl, Neurosim | `#8B5CF6` | `#7C3AED` |
| Instrument | Neurosense, Neurochip, Neurobench | `#06B6D4` | `#0F766E` |

**Mode Palette Rule:** mode accents never cross surfaces. Studio violet only on Studio surfaces. Instrument cyan only on Instrument surfaces.

#### Status Palette (semantic, fixed)

| State | Color | Meaning |
|-------|-------|---------|
| Healthy | `#22C55E` | System operating normally |
| Running | `#38BDF8` | Active execution in progress |
| Degraded | `#F59E0B` | Reduced capability, workflow can continue |
| Warning | `#F97316` | Threshold approaching, non-fatal |
| Error | `#EF4444` | Workflow cannot continue without intervention |
| Live | `#E11D48` | Hardware actively connected / streaming |

**Semantic Purity Rule:** these six colors communicate operational state only. Never used decoratively. `#22C55E` means healthy. It means nothing else.

#### Dark Surface Stack

| Token | Value | Role |
|-------|-------|------|
| `canvas-dark` | `#0A0F1D` | Module canvas — deepest layer |
| `shell-bg-dark` | `#0B1020` | Primary shell background |
| `top-bar-dark` | `#101728` | Top app bar |
| `workspace-bar-dark` | `#0D1424` | Workspace switcher bar |
| `utility-panel-dark` | `#111A2C` | Utility panel |
| `chrome-border-dark` | `#243044` | Primary chrome border (1px) |
| `subtle-border-dark` | `#1A2436` | Internal section dividers |
| `metadata-dark` | `#9BA8BC` | Labels, metadata, chip text at rest |

#### Light Surface Stack

| Token | Value | Role |
|-------|-------|------|
| `canvas-light` | `#FFFFFF` | Module canvas |
| `shell-bg-light` | `#F3F5FA` | Primary shell background |
| `top-bar-light` | `#FFFFFF` | Top app bar |
| `workspace-bar-light` | `#F7F9FC` | Workspace switcher bar |
| `utility-panel-light` | `#FAFBFD` | Utility panel |
| `chrome-border-light` | `#D9E0EA` | Primary chrome border |
| `subtle-border-light` | `#E7ECF3` | Internal dividers |
| `metadata-light` | `#5B677C` | Labels, metadata, secondary text |

---

## 3. Typography

**Zeta spec font:** IBM Plex Sans. **NMTK override:** Space Grotesk for all UI chrome.

`nmtk_ui_core` ships both fonts as assets. `FontFamily: 'Space Grotesk', package: 'nmtk_ui_core'` is applied via `AppTheme._buildTextTheme()`.

| Scale | Weight | Size | Line-height | Use |
|-------|--------|------|-------------|-----|
| Display | 700 | 28px | 1.1 | Module-level headers. Used sparingly. |
| Headline | 600 | 20px | 1.2 | Section headers, panel titles. |
| Title | 700 | 16px | 1.3 | Card headers, group headers. |
| Body | 400 | 14px | 1.5 | Descriptions, docs, pipeline step text. |
| Label | 500 | 12px | 1.4 | Status labels, metadata, chip text, nav items. |
| Mono | 400 | 13px | 1.6 | Code, CNL spec, terminal output, numeric telemetry. |

**Mono font:** JetBrains Mono (`fontFamily: 'JetBrains Mono', package: 'nmtk_ui_core'`). Used exclusively for machine-generated content. Never for chrome.

**Rules:**
- Hierarchy through weight contrast before scale. w700 vs w400 is the primary jump.
- 28px display is the ceiling; no larger.
- JetBrains Mono boundary: code, CNL, column-aligned numbers only.

---

## 4. Spacing (Zeta Semantics)

All spacing from `Zeta.of(context).spacing.*` or directly from `NmtkShellTokens`. The 4px grid is Zeta's base.

| Zeta name | dp | NMTK usage |
|-----------|----|------------|
| `none` | 0 | Gaps disabled |
| `minimum` | 4 | Icon-to-label gaps, tight chip internals |
| `small` | 8 | `compactGap` in shell |
| `medium` | 12 | Compact padding |
| `large` | 16 | `sectionGap`, standard padding |
| `xl` | 20 | Button padding |
| `2xl` | 24 | Card internal padding |
| `4xl` | 32 | Section-level breathing room |

---

## 5. Radius (Zeta Semantics)

All radius from `Zeta.of(context).radius.*`.

| Zeta name | dp | NMTK surface |
|-----------|----|-------------|
| `none` | 0 | Square crops, full-bleed panels |
| `minimal` | 4 | Small badges, inline tags |
| `rounded` | 8 | Inputs (`inputShape`), small chips |
| `large` | 16 | Buttons (`buttonShape`), nav destinations |
| `xl` | 24 | Cards (`cardShape`), dialogs |
| `full` | 360 | Workspace chips (full pill) |

---

## 6. Elevation

NMTK is **flat by default**. No box shadows. Depth is communicated through surface tinting: surfaces step from `canvas` (deepest) through `shell-bg` to `top-bar`.

- Cards use a 1px border at chrome-border opacity to define their boundary.
- State changes produce background tint shifts, not shadow introduction.
- Dialogs are one tonal step above the top bar. Still no shadow.

**The Border-Not-Shadow Rule:** if an element needs to feel elevated, lighten its background by one tonal step. Never add a shadow.

---

## 7. Components

Zeta provides base components (ZetaButton, ZetaTextInput, ZetaAvatar, ZetaStatusLabel, ZetaBadge, etc.). NMTK uses these where the component fits, then adds NMTK-specific widgets for suite-specific patterns.

### Buttons

- **Primary (ZetaButton):** Command Blue fill `#1337EC`, white label, 10px/20px padding, 16dp radius.
- **Hover:** darkens to `#0D2EC0` at 120ms ease-out.
- **Active:** scale 0.96 at 120ms.
- **Focus visible:** 2px offset outline, command-blue 40% opacity.
- **Outlined:** transparent bg, command-blue border 35% opacity, command-blue label.
- **Disabled:** 38% opacity on fill and label.

### Workspace Chips

NMTK-specific. Primary navigation in the workspace switcher bar.

- **Active:** mode-accent background (command/studio/instrument per module), white label, 360dp radius.
- **Idle:** neutral tint, metadata-color label, 360dp radius.
- **Contents:** module icon (14px) + label (12px w500) + status dot (6px) + close icon (12px).
- **Status dot:** maps to six semantic states. Degraded and error states pulse (0.5x–1.2x scale, 900ms ease-in-out). This is the **only** unsolicited animation in the suite.
- **Spacing:** 5px top/bottom, 12px left/right.

### Cards / Surface Containers

- **Corner:** 24dp radius (`card` semantic).
- **Background:** dark: `top-bar-dark` `#101728`; light: `#FFFFFF`.
- **Elevation:** flat. 1px border at chrome-border (65% opacity).
- **Padding:** 14px. Header separation: 10px.
- **Tone variants:** cards accept info/success/warning/danger tones for contextual containers (ZetaCardContainer tone system where applicable).

### Inputs

- `ZetaTextInput` / Flutter `TextField` at `rounded` radius (8dp).
- Focus: border shifts to command-blue full opacity.
- Error: border and helper text shift to `state-error`.
- Disabled: 38% opacity.

### Shell Status Badge

- 7px status dot + 12px w500 label, tonal background, 12dp radius.
- States map to all six semantic state colors.
- Degraded/Error: dot pulses.

---

## 8. Chrome Sizing

| Element | Height | Notes |
|---------|--------|-------|
| Top app bar | 52px | Fixed. Canvas dominates. |
| Workspace bar | 48px | Module chips + status. |
| Utility panel | 320px wide | Adjacent to canvas. |

---

## 9. Motion

| Token | Value | Use |
|-------|-------|-----|
| `fastMotion` | 120ms ease-out | Hover states, micro-feedback |
| `standardMotion` | 180ms ease-in-out | Standard expand/collapse, chip open |
| `emphasizedMotion` | 240ms ease-in-out | Panel transitions, loading entrance |
| `status-pulse` | 900ms ease-in-out infinite | Degraded/error dot oscillation only |
| `tap-scale` | 0.96 | Button press-down |

**Rules:** animate opacity and transform only. Never animate layout properties (width, height, padding, margin). No bounce, no elastic. Exponential ease-out curves for dismissal.

---

## 10. Rules (Quick Reference)

**Do:**
- Apply mode palettes strictly: command blue → shell + Neurohub; studio violet → neurocnl + Neurosim; instrument cyan/teal → Neurosense + Neurochip + Neurobench.
- Use tonal depth (background steps) not shadows for hierarchy.
- Achieve typographic hierarchy through weight contrast before size.
- Map every status indicator to exactly one of the six semantic states.
- Keep the top app bar at 52px and workspace bar at 48px.
- Use JetBrains Mono for code, CNL text, and column-aligned numeric telemetry.
- Use ZetaButton, ZetaTextInput, ZetaAvatar, ZetaStatusLabel where the Zeta component fits.
- Access color semantics via `Zeta.of(context).colors` and spacing/radius via `Zeta.of(context).spacing` / `.radius`.

**Don't:**
- Use Zeta primitive swatches directly in production UI.
- Use status colors decoratively.
- Use shadow for elevation. Use tonal surface steps instead.
- Nest cards. Use tonal sections or `subtle-border` dividers.
- Use side-stripe borders (`border-left`/`border-right` > 1px as colored accents).
- Use gradient text (`background-clip: text` with a gradient fill).
- Reach for a modal first. Utility panel and inline expansion handle most cases.
- Let NMTK feel like consumer SaaS, Arduino IDE, dark hacker terminal, SAP/Jira, ZBrush/Blender, or VS Code.
