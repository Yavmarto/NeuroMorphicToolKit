# nmtk

Read first:
- `../CODING_STYLE_GUIDE.md`
- `neuro_toolkit/pubspec.yaml`
- `neuro_toolkit/analysis_options.yaml`
- `neuro_toolkit/SPEC.md`
- `neuro_toolkit/assets/modules.json`
- `docs/ADR-Gemini/`
- `docs/ADR-claude/0001-module-manifest-system.md`
- `docs/ADR-claude/0002-provider-state-management.md`
- `docs/ADR-claude/0003-gorouter-shell-routes.md`
- `docs/ADR-claude/0004-webview-module-embedding.md`
- `docs/ADR-claude/0005-separate-deployment-providers.md`

Constraints:
- `neuro_toolkit/assets/modules.json` is the launcher's module registry. Keep it synchronized with `neuro_toolkit/lib/models/module.dart`, provider logic, root compose wiring, and any root helper scripts that consume module ids, ports, or entrypoints.
- The launcher uses Provider, GoRouter shell routes, and separate deployment providers by ADR. Do not introduce a second state-management stack or ad-hoc routing system inside the launcher without updating the ADR trail.
- Module UIs are embedded web frontends. Keep module-specific product UI in the owning module or in `nmtk_ui_core`, not in bespoke launcher-only copies.
- Any change to install paths, start strategies, ports, health checks, or tool routing requires updating launcher tests in the same change. New install or startup strategies also require doctor or preflight coverage.
- For launcher and module-lifecycle changes, run `bash ../scripts/run_launcher_guardrails.sh`. Use `bash ../scripts/run_launcher_guardrails.sh --with-integration` when the change alters manifest contracts or suite-visible startup behavior.
- Treat launcher doctor `fatalCount > 0` as a blocker unless the task is to diagnose or fix that failure, and report `preflight failed` separately from `degraded optional capability`.
- Launcher work is not complete until launcher doctor and launcher unit coverage pass. The canonical wrapper also runs `cd neuro_toolkit && flutter test`.

Do NOT:
- Add manifest fields in Dart without adding them to `assets/modules.json`.
- Change `modules.json` without updating launcher Dart models, launcher tests, and any consuming helper scripts in the same change.
- Introduce a new install or startup strategy without adding doctor or preflight coverage.
- Treat optional hardware or framework dependencies as fatal unless the manifest explicitly declares them required.
- Duplicate `nmtk_ui_core` widgets inside the launcher.
- Point launcher code at machine-local absolute paths or one-off developer ports.
