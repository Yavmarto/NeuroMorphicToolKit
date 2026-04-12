# neurocli

Read first:
- `../CODING_STYLE_GUIDE.md`
- `README.md`
- `docs/ADR-Gemini/0001-initial-architecture.md`
- `docs/ADR-claude/0001-scaffolding-first-cli.md`
- `docs/ADR-claude/0002-template-bundle-architecture.md`
- `docs/ADR-claude/0003-module-lifecycle-commands.md`
- `docs/ADR-claude/0004-headless-ci-integration.md`
- `../nmtk/neuro_toolkit/assets/modules.json`

Constraints:
- `neurocli` is still a planning-only directory. If implementation starts, the first real change must create a proper package, entrypoint, tests, and template fixture layout together.
- The CLI must mirror launcher lifecycle semantics and module ids from `../nmtk/neuro_toolkit/assets/modules.json`; do not invent a second manifest or alternate module registry.
- Template bundles should live as package data, not as large inline strings inside command handlers.
- Generated scaffolds must track upstream NMTK contracts; if a template depends on another module's payload or config shape, read that module before changing the template.

Do NOT:
- Add docs that imply a shipped CLI exists when there is still no package or test surface.
- Introduce command behavior that diverges from the launcher's module naming or lifecycle model.
- Scatter template files across arbitrary directories or build them with ad-hoc string concatenation.
