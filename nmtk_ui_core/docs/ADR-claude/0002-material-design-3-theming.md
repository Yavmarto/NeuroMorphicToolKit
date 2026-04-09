# ADR 0002: Material Design 3 Theming

## Status
Accepted

## Context
All NMTK frontends must share a consistent visual identity while supporting the toolkit's neuromorphic computing domain, which has unique visualization needs (energy charts, spike plots, deployment status indicators) beyond standard Material components.

## Decision
Define `NmtkDesignTokens` for brand constants (primarySeed color, background colors, border radii, spacing) and per-module token classes (e.g., `NmtkNeurocnlTokens` with syntax highlighting and node/edge colors). Use Material 3's `ColorScheme.fromSeed` for dynamic theme generation, supplemented by Google Fonts for consistent typography across platforms.

## Consequences
- **Positive:** Material 3 seed-based theming ensures consistent color harmonies across light/dark modes; per-module tokens allow domain-specific customization within the shared design language.
- **Negative:** Custom design tokens alongside Material 3 create two sources of truth for styling; per-module token classes grow linearly with the number of modules.
