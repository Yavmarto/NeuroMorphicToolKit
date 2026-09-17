# Launcher integration tests (integration_test/)

This folder is the **successor** to the deleted `test/launcher_e2e_test.dart`
(commit `30276bdf`, [CEL-328](/CEL/issues/CEL-328)). That file exercised the
removed `ProcessManager` (local subprocess install/start/recovery). The shipping
launcher path is now connect → remote launcher-control API → workspace; these
tests cover that app-level flow. Remote module lifecycle is covered by
`tests/launcher_control/` and `scripts/run_launcher_guardrails.sh` (see
`docs/ci-runners.md`).

Integration tests boot the real `neuro_toolkit` macOS/iOS app (the `integration_test`
binding compiles and launches the actual app binary, not a headless widget harness) and
drive the shipping `ServerAccessGate` / launcher surfaces. They live next to the widget
tests in `test/`, but they are **not** `flutter test`-of-`test/` tests.

## From where

Always from the Flutter package root — `cd` there first:

```bash
cd nmtk/neuro_toolkit
```

The repo root and the sibling package folders (`nmtk/packages/*`) are the wrong place:
`flutter test integration_test …` resolves the package from the current `pubspec.yaml`.

## Prerequisites

- Flutter stable (CI uses `subosito/flutter-action`, channel `stable`).
- A real device/desktop target. `flutter devices` must list `macos` (this repo's CI runs
  macOS and an iOS simulator). macOS is the supported local path; `-d macos` below.
- First run builds the macOS app (a minute or two). The Swift-Package-Manager warnings for
  `desktop_webview_window` / `flutter_inappwebview_macos` are harmless today.
- Some tests talk to a real backend (see per-test notes) — they are **not** mocked.

## Run everything (same as CI)

```bash
cd nmtk/neuro_toolkit
flutter test integration_test -d macos
```

Run a single file:

```bash
flutter test integration_test/example_test.dart -d macos
```

## What is in here

| File | What it does | Needs a live server? |
| --- | --- | --- |
| `example_test.dart` | Smoke test that a native adapter surface (NeuroCNL shell) mounts inside the launcher without nesting a second `MaterialApp`, with localization wired. | No |
| `cel91_back_nav_desktop_test.dart` | Real macOS embedder: drives setup-wizard Back/cancel from the initial form and from a real failed-provision panel; captures screenshots to `build/cel91_shots/`. | No (uses `127.0.0.1` + bogus credentials for the failure path) |
| `cel108_server_connect_e2e_test.dart` | Real server-connect e2e: cold boot → sign-in form → real login against the live dev backend → asserts the connect session reaches `connected`/home; screenshots to `build/cel108_shots/`. | **Yes** — dev backend at `<dev-host>` and app-account credentials |
| `cel261_studio_golden_paths_e2e_test.dart` | Live Studio golden path (`nir+snntorch` trains to completion through the Run step UI). Skipped unless `NMTK_GOLDEN_PATHS_LIVE=1`. Fast widget coverage lives in `test/features/neurocnl/golden_paths/`. | **Optional** — live Suite API at `NMTK_E2E_SERVER_HOST` (default `<dev-host>`) |
| `cel232_profile_mobile_connect_e2e_test.dart` | Profile/debug mobile connect: cold-start auto-probe, manual host-only connect, unreachable-host error. Skipped on release builds. | **Yes** — live dev backend (default `<dev-host>`) |
| `cel134_neurohub_commit_e2e_test.dart` | Neurohub connect → list → create → commit (mocked device-flow launcher). | No |
| `app_robot.dart` | Shared tap/type/assert helper for the widget-driver style used above. | — |

Screenshots land in `nmtk/neuro_toolkit/build/<name>_shots/` after a run.

## cel91 — run-order dependency (read before running)

`cel91` cold-starts `ServerAccessGate` and assumes **no saved connect target**, because a
saved target makes the gate auto-reconnect and the "new server" form never appears. It
passes on a clean profile or **before** any real connect has saved a target (e.g. before a
`cel108` run on the same machine). After a successful live connect has saved `<dev-host>`,
`cel91` times out waiting for `server-connect-new-server`. It does not clear targets itself
(`cel108` does). To rerun `cel91` after a live connect, clear the saved target first or run on
a machine/profile with none.

## cel108 — live e2e against the real dev server

Host + app-account credentials are **not** committed; supply them at run time. The host must
be healthy first:

```bash
bash scripts/check_dev_server.sh <dev-host> --check-only
```

Then, from `nmtk/neuro_toolkit`:

```bash
NMTK_E2E_SERVER_HOST=<dev-host> \
NMTK_E2E_SERVER_USERNAME=testuser \
NMTK_E2E_SERVER_PASSWORD='<password>' \
flutter test integration_test/cel108_server_connect_e2e_test.dart -d macos
```

Environment:

- `NMTK_E2E_SERVER_HOST` — dev server host (default `<dev-host>`; must be non-loopback)
- `NMTK_E2E_SERVER_USERNAME` / `NMTK_E2E_SERVER_PASSWORD` — app account on that host
- `NMTK_E2E_CONNECT_TIMEOUT_SECONDS` — optional, default 120

The test asserts host is not loopback and fails fast with a clear message if the login does
not reach `connected`; a failure screenshot is still captured. The `testuser` app-account
password is minted on the dev host (see `current tasks/2026-09-09/CEL-110-e2e-live-run.md`).
CEL-110 validated this test twice back-to-back against the live host (~11 s, no flakiness).

## cel261 — Studio UI golden paths (CEL-261)

Fast path (CI-friendly, mocked HTTP, real Studio Run UI):

```bash
cd nmtk/neuro_toolkit
flutter test test/features/neurocnl/golden_paths/
```

Or from the repo root:

```bash
bash scripts/run_studio_golden_paths.sh
```

Live path (optional, hits the real dev backend for `nir+snntorch`):

```bash
NMTK_GOLDEN_PATHS_LIVE=1 \
NMTK_E2E_SERVER_HOST=<dev-host> \
flutter test integration_test/cel261_studio_golden_paths_e2e_test.dart -d macos
```

## Known state on `dev` (2026-09-09)

- `example_test.dart` currently **fails** the `assertTextExists('NeuroChip')` assertion: the
  test predates the CEL-101 single-surface launcher change (commit `ba3704fe`), which removed
  the module picker/tab bar that rendered that text. Needs updating to assert the CEL-101
  single-surface reality.
- `cel91_back_nav_desktop_test.dart` currently **fails** with a timeout on a machine that has
  a saved connect target (see the run-order note above); it passes on a clean profile.

CI (`nmtk-ci.yml`, `integration-test-apple` job) runs the whole folder on macOS and an iOS
simulator.
