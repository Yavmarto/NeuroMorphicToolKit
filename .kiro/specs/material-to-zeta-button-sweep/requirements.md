# Requirements Document

## Introduction

Tasks 1–4 of the T-DEBT tech debt cleanup removed the stale worktree, the legacy Nengo surface, and wired `NmtkZetaTheme.wrap()` into all 5 app roots. The remaining gap is 104 direct `ElevatedButton`/`TextButton`/`OutlinedButton` usages across 5 Flutter frontends. These render via Zeta's theme already (since app roots are wrapped), but the widget types must be replaced to complete the full Zeta migration and remove any remaining Material Design component coupling.

## Scope

Five packages, 45 files, 104 hits:

| Package | Files | Hits |
|---|---|---|
| `neurocnl/frontend` | 18 | 52 |
| `Neurohub/frontend` | 11 | 20 |
| `Neurobench/frontend` | 4 | 14 |
| `nmtk/neuro_toolkit` | 8 | 13 |
| `Neurosense/frontend` | 4 | 5 |

## Requirements

### REQ-1: Button type replacement

1.1 Every `ElevatedButton(onPressed: X, child: Text(Y))` MUST be replaced with `ZetaButton(onPressed: X, label: Y)`.

1.2 Every `ElevatedButton.icon(onPressed: X, icon: Icon(Z), label: Text(Y))` MUST be replaced with `ZetaButton(onPressed: X, label: Y, leadingIcon: Z)`, dropping `styleFrom`.

1.3 `ElevatedButton.styleFrom(backgroundColor: Colors.red)` pattern MUST use `ZetaButton.negative(...)`.

1.4 `ElevatedButton.styleFrom(backgroundColor: Colors.green)` pattern MUST use `ZetaButton.positive(...)`.

1.5 Every `TextButton(onPressed: X, child: Text(Y))` MUST be replaced with `ZetaButton.text(onPressed: X, label: Y)`.

1.6 Every `TextButton.icon(onPressed: X, icon: Icon(Z), label: Text(Y))` MUST be replaced with `ZetaButton.text(onPressed: X, label: Y, leadingIcon: Z)`.

1.7 Every `OutlinedButton(onPressed: X, child: Text(Y))` MUST be replaced with `ZetaButton.outline(onPressed: X, label: Y)`.

1.8 Every `OutlinedButton.icon(onPressed: X, icon: Icon(Z), label: Text(Y))` MUST be replaced with `ZetaButton.outline(onPressed: X, label: Y, leadingIcon: Z)`, dropping `styleFrom`.

### REQ-2: Loading state preservation

2.1 Buttons whose `icon:` is a conditional `CircularProgressIndicator` / `Icon` MUST preserve the loading indicator as `leadingIcon:` — Zeta accepts any widget there. Do NOT replace the `CircularProgressIndicator` itself.

### REQ-3: Import hygiene

3.1 Each modified file MUST import `zeta_flutter` either directly or via `nmtk_ui_core` — no undefined-name compile errors.

3.2 Unused `ElevatedButton`/`TextButton`/`OutlinedButton` style imports MUST be removed.

### REQ-4: No regressions

4.1 `dart analyze <file>` MUST pass (zero errors) after each file is modified.

4.2 `flutter test <package>` MUST pass at the pre-existing baseline failure count after each package is complete.

4.3 `NmtkOutlinedButton`, `NmtkPrimaryButton`, `ZetaButton` usages already present MUST NOT be touched.

### REQ-5: Out of scope

5.1 `NavigationBar`, `Scaffold`, `CircularProgressIndicator` (standalone), `TabBar`, `AlertDialog`, `TextField`, `ListTile`, `Card`, `Chip` — NOT replaced in this spec. These are either layout primitives, have no Zeta equivalent, or are tracked separately.

5.2 Test files are NOT modified (they use `MaterialApp` as test harness, not as product widgets).
