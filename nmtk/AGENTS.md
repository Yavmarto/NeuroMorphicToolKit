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
- `docs/ADR-claude/0009-single-workspace-launcher-navigation.md`
- `docs/ADR-claude/0004-webview-module-embedding.md`
- `docs/ADR-claude/0005-separate-deployment-providers.md`

Constraints:
- `neuro_toolkit/assets/modules.json` is the launcher's module registry. Keep it synchronized with `neuro_toolkit/lib/models/module.dart`, provider logic, root compose wiring, and any root helper scripts that consume module ids, ports, or entrypoints.
- The launcher uses Riverpod, a single `MaterialApp.home` workspace host, and typed navigation intents. Do not introduce a second state-management stack or URL router inside the launcher without updating the ADR trail.
- Module UIs are embedded web frontends. Keep module-specific product UI in the owning module or in `nmtk_ui_core`, not in bespoke launcher-only copies.
- Any change to install paths, start strategies, ports, health checks, or tool routing requires updating launcher tests in the same change. New install or startup strategies also require doctor or preflight coverage.
- For launcher and module-lifecycle changes, run `bash ../scripts/run_launcher_guardrails.sh`. Use `bash ../scripts/run_launcher_guardrails.sh --with-integration` when the change alters manifest contracts or suite-visible startup behavior.
- Treat launcher doctor `fatalCount > 0` as a blocker unless the task is to diagnose or fix that failure, and report `preflight failed` separately from `degraded optional capability`.
- Launcher work is not complete until launcher doctor and launcher unit coverage pass. The canonical wrapper also runs `cd neuro_toolkit && flutter test`.
- Backend Setup must keep the connected backend version visible. Its source is `GET /api/suite/health`; release images stamp `NMTK_VERSION` from the root release tag, while `scripts/release.sh` keeps `suite_api/pyproject.toml` aligned with the launcher release number.
- Changes to backend version reporting, parsing, or display must update Suite API health tests, `ControlApiService` tests, Backend Setup widget tests, and the release/version documentation in the same change.

Do NOT:
- Add manifest fields in Dart without adding them to `assets/modules.json`.
- Change `modules.json` without updating launcher Dart models, launcher tests, and any consuming helper scripts in the same change.
- Introduce a new install or startup strategy without adding doctor or preflight coverage.
- Treat optional hardware or framework dependencies as fatal unless the manifest explicitly declares them required.
- Duplicate `nmtk_ui_core` widgets inside the launcher.
- Point launcher code at machine-local absolute paths or one-off developer ports.

## Shell mode

The launcher uses `NmtkShellMode.command`. Pass `mode: NmtkShellMode.command` to `NmtkDesktopScaffold`. This is the default, but always pass it explicitly for clarity.

The sidebar `navItems` list is dynamic — it is built from the installed module manifest at runtime. Module-specific product UI must not live in the launcher; it belongs in `nmtk_ui_core` or the owning module's frontend.

<directory_structure>
├── AGENTS.md
├── CODE_REVIEW.md
├── LICENSE
├── Merge_maintain.md
├── NEUROCNL_EXPLORATION_SUMMARY.txt
├── QUICK_START_GUIDE.md
├── README_EXPLORATION_RESULTS.md
├── ROADMAP.md
├── START_HERE.md
├── cliff.toml
├── codecov.yml
├── docs
│   ├── ADR-Gemini
│   │   ├── 0001-initial-architecture.md
│   │   └── 0002-daemon-module-orchestration.md
│   ├── ADR-claude
│   │   ├── 0001-module-manifest-system.md
│   │   ├── 0002-provider-state-management.md
│   │   ├── 0003-gorouter-shell-routes.md
│   │   ├── 0004-webview-module-embedding.md
│   │   ├── 0005-separate-deployment-providers.md
│   │   ├── 0006-riverpod-launcher-state-management.md
│   │   ├── 0007-deploy-ui-moved-to-neurochip.md
│   │   └── 0008-inappwebview-for-embedded-surfaces.md
│   ├── api
│   │   ├── index.rst
│   │   └── neurocnl.rst
│   ├── conf.py
│   ├── index.rst
│   ├── quickstart.rst
│   └── requirements.txt
├── installer
│   ├── linux
│   │   ├── AppRun
│   │   ├── appimage.sh
│   │   └── nmtk.desktop
│   ├── macos
│   │   ├── CODE_SIGNING.md
│   │   ├── build-standalone.sh
│   │   ├── create-dmg.sh
│   │   ├── import-signing-cert.sh
│   │   └── sign-and-notarize.sh
│   └── windows
│       ├── CODE_SIGNING.md
│       ├── build-standalone.ps1
│       ├── setup.iss
│       └── sign-installer.ps1
├── issues-archive
│   ├── 001-end-to-end-launcher-test.md
│   ├── 001-poc-add-launcher-ci-workflow.md
│   ├── 001-poc-validate-root-docker-compose-yml.md
│   ├── 001-replace-mocked-update-checks-with-real-version-sources.md
│   ├── 002-expand-test-coverage.md
│   ├── 002-poc-cleanup-deprecated-ci-workflows.md
│   ├── 002-poc-fix-nmtk-ui-core-placeholder-test.md
│   ├── 003-poc-fix-unified-dev-pipeline-state.md
│   ├── 003-poc-verify-processmanager-health-checks.md
│   ├── 003-validate-macos-dmg-installer.md
│   ├── 004-poc-repository-documentation-consolidation.md
│   ├── 004-poc-validate-bundlemanager.md
│   ├── 004-validate-linux-appimage.md
│   ├── 005-beta-macos-dmg-installer-validation-ref-issue-003.md
│   ├── 005-beta-root-security-md.md
│   ├── 005-fix-windows-installer-scope.md
│   ├── 006-beta-linux-appimage-validation-ref-issue-004.md
│   ├── 006-beta-root-changelog-md.md
│   ├── 007-beta-contributing-md.md
│   ├── 007-beta-windows-installer-ref-issue-005.md
│   ├── 008-beta-cross-module-integration-tests.md
│   ├── 008-beta-module-update-mechanism.md
│   ├── 009-beta-environment-configuration.md
│   ├── 009-beta-settings-and-preferences.md
│   ├── 010-prod-end-to-end-integration-tests-ref-issue-001.md
│   ├── 010-prod-release-automation.md
│   ├── 011-prod-auto-update-system.md
│   ├── 011-prod-monitoring-and-observability.md
│   ├── 012-prod-crash-reporting-and-analytics.md
│   ├── 012-prod-deployment-playbook.md
│   ├── 013-prod-accessibility.md
│   ├── 013-prod-security-hardening.md
│   ├── 014-prod-comprehensive-test-suite.md
│   ├── 014-prod-user-documentation.md
│   ├── WF-001-release-promote-sc2016.md
│   ├── WF-002-reusable-status-audit-sc2086.md
│   ├── WF-003-reusable-status-audit-sc2129.md
│   ├── WF-004-stale-branches-sc2106.md
│   ├── WF-005-pr-labeler-untrusted-head-ref.md
│   ├── WF-006-reusable-feature-builder-undefined-outputs.md
│   ├── WF-007-unblocked-issues-matrix-evaluation.md
│   ├── WF-008-stale-branches-no-stages.md
│   ├── WF-009-submodule-sync-no-stages.md
│   ├── WF-010-performance-improver-no-stages.md
│   └── WF-011-unblocked-issues-undefined-outputs.md
├── launcher_control
│   ├── __init__.py
│   ├── config.py
│   ├── deployment_contracts.py
│   ├── deployment_executors.py
│   ├── deployment_k8s_renderer.py
│   ├── deployment_preflight.py
│   ├── deployment_service.py
│   ├── deployment_store.py
│   ├── provisioning_helpers.py
│   └── server.py
├── maintenance-improvement.md
├── neuro_toolkit
│   ├── LICENSE
│   ├── README.md
│   ├── SPEC.md
│   ├── analysis_options.yaml
│   ├── android
│   │   ├── app
│   │   │   ├── build.gradle.kts
│   │   │   └── src
│   │   │       ├── debug
│   │   │       │   └── AndroidManifest.xml
│   │   │       ├── main
│   │   │       │   ├── AndroidManifest.xml
│   │   │       │   ├── java
│   │   │       │   │   └── io
│   │   │       │   │       └── flutter
│   │   │       │   │           └── plugins
│   │   │       │   │               └── GeneratedPluginRegistrant.java
│   │   │       │   ├── kotlin
│   │   │       │   │   └── com
│   │   │       │   │       └── example
│   │   │       │   │           └── neuro_toolkit
│   │   │       │   │               └── MainActivity.kt
│   │   │       │   └── res
│   │   │       │       ├── drawable
│   │   │       │       │   └── launch_background.xml
│   │   │       │       ├── drawable-v21
│   │   │       │       │   └── launch_background.xml
│   │   │       │       ├── mipmap-hdpi
│   │   │       │       │   └── ic_launcher.png
│   │   │       │       ├── mipmap-mdpi
│   │   │       │       │   └── ic_launcher.png
│   │   │       │       ├── mipmap-xhdpi
│   │   │       │       │   └── ic_launcher.png
│   │   │       │       ├── mipmap-xxhdpi
│   │   │       │       │   └── ic_launcher.png
│   │   │       │       ├── mipmap-xxxhdpi
│   │   │       │       │   └── ic_launcher.png
│   │   │       │       ├── values
│   │   │       │       │   └── styles.xml
│   │   │       │       └── values-night
│   │   │       │           └── styles.xml
│   │   │       └── profile
│   │   │           └── AndroidManifest.xml
│   │   ├── build.gradle.kts
│   │   ├── gradle
│   │   │   └── wrapper
│   │   │       ├── gradle-wrapper.jar
│   │   │       └── gradle-wrapper.properties
│   │   ├── gradle.properties
│   │   ├── gradlew
│   │   ├── gradlew.bat
│   │   ├── local.properties
│   │   └── settings.gradle.kts
│   ├── assets
│   │   ├── custom_node_editor.html
│   │   └── modules.json
│   ├── dart_test.yaml
│   ├── deployment_state.json
│   ├── devtools_options.yaml
│   ├── integration_test
│   │   ├── app_robot.dart
│   │   └── example_test.dart
│   ├── ios
│   │   ├── Flutter
│   │   │   ├── AppFrameworkInfo.plist
│   │   │   ├── Debug.xcconfig
│   │   │   ├── Generated.xcconfig
│   │   │   ├── Release.xcconfig
│   │   │   ├── ephemeral
│   │   │   │   ├── flutter_lldb_helper.py
│   │   │   │   └── flutter_lldbinit
│   │   │   └── flutter_export_environment.sh
│   │   ├── Podfile
│   │   ├── Podfile.lock
│   │   ├── Runner
│   │   │   ├── AppDelegate.swift
│   │   │   ├── Assets.xcassets
│   │   │   │   ├── AppIcon.appiconset
│   │   │   │   │   ├── Contents.json
│   │   │   │   │   ├── Icon-App-1024x1024@1x.png
│   │   │   │   │   ├── Icon-App-20x20@1x.png
│   │   │   │   │   ├── Icon-App-20x20@2x.png
│   │   │   │   │   ├── Icon-App-20x20@3x.png
│   │   │   │   │   ├── Icon-App-29x29@1x.png
│   │   │   │   │   ├── Icon-App-29x29@2x.png
│   │   │   │   │   ├── Icon-App-29x29@3x.png
│   │   │   │   │   ├── Icon-App-40x40@1x.png
│   │   │   │   │   ├── Icon-App-40x40@2x.png
│   │   │   │   │   ├── Icon-App-40x40@3x.png
│   │   │   │   │   ├── Icon-App-60x60@2x.png
│   │   │   │   │   ├── Icon-App-60x60@3x.png
│   │   │   │   │   ├── Icon-App-76x76@1x.png
│   │   │   │   │   ├── Icon-App-76x76@2x.png
│   │   │   │   │   └── Icon-App-83.5x83.5@2x.png
│   │   │   │   └── LaunchImage.imageset
│   │   │   │       ├── Contents.json
│   │   │   │       ├── LaunchImage.png
│   │   │   │       ├── LaunchImage@2x.png
│   │   │   │       ├── LaunchImage@3x.png
│   │   │   │       └── README.md
│   │   │   ├── Base.lproj
│   │   │   │   ├── LaunchScreen.storyboard
│   │   │   │   └── Main.storyboard
│   │   │   ├── GeneratedPluginRegistrant.h
│   │   │   ├── GeneratedPluginRegistrant.m
│   │   │   ├── Info.plist
│   │   │   ├── Runner-Bridging-Header.h
│   │   │   └── SceneDelegate.swift
│   │   ├── Runner.xcodeproj
│   │   │   ├── project.pbxproj
│   │   │   ├── project.xcworkspace
│   │   │   │   ├── contents.xcworkspacedata
│   │   │   │   └── xcshareddata
│   │   │   │       ├── IDEWorkspaceChecks.plist
│   │   │   │       ├── WorkspaceSettings.xcsettings
│   │   │   │       └── swiftpm
│   │   │   │           └── configuration
│   │   │   └── xcshareddata
│   │   │       └── xcschemes
│   │   │           └── Runner.xcscheme
│   │   ├── Runner.xcworkspace
│   │   │   ├── contents.xcworkspacedata
│   │   │   └── xcshareddata
│   │   │       ├── IDEWorkspaceChecks.plist
│   │   │       ├── WorkspaceSettings.xcsettings
│   │   │       └── swiftpm
│   │   │           └── configuration
│   │   └── RunnerTests
│   │       └── RunnerTests.swift
│   ├── issues-archive
│   │   ├── 001-end-to-end-launcher-test.md
│   │   ├── 001-poc-add-launcher-ci-workflow.md
│   │   ├── 001-poc-validate-root-docker-compose-yml.md
│   │   ├── 002-expand-test-coverage.md
│   │   ├── 002-poc-cleanup-deprecated-ci-workflows.md
│   │   ├── 002-poc-fix-nmtk-ui-core-placeholder-test.md
│   │   ├── 003-poc-fix-unified-dev-pipeline-state.md
│   │   ├── 003-poc-verify-processmanager-health-checks.md
│   │   ├── 003-validate-macos-dmg-installer.md
│   │   ├── 004-poc-repository-documentation-consolidation.md
│   │   ├── 004-poc-validate-bundlemanager.md
│   │   ├── 004-validate-linux-appimage.md
│   │   ├── 005-beta-macos-dmg-installer-validation-ref-issue-003.md
│   │   ├── 005-beta-root-security-md.md
│   │   ├── 005-fix-windows-installer-scope.md
│   │   ├── 006-beta-linux-appimage-validation-ref-issue-004.md
│   │   ├── 006-beta-root-changelog-md.md
│   │   ├── 007-beta-contributing-md.md
│   │   ├── 007-beta-windows-installer-ref-issue-005.md
│   │   ├── 008-beta-cross-module-integration-tests.md
│   │   ├── 008-beta-module-update-mechanism.md
│   │   ├── 009-beta-environment-configuration.md
│   │   ├── 009-beta-settings-and-preferences.md
│   │   ├── 010-prod-end-to-end-integration-tests-ref-issue-001.md
│   │   ├── 010-prod-release-automation.md
│   │   ├── 011-prod-auto-update-system.md
│   │   ├── 011-prod-monitoring-and-observability.md
│   │   ├── 012-prod-crash-reporting-and-analytics.md
│   │   ├── 012-prod-deployment-playbook.md
│   │   ├── 013-prod-accessibility.md
│   │   ├── 013-prod-security-hardening.md
│   │   ├── 014-prod-comprehensive-test-suite.md
│   │   └── 014-prod-user-documentation.md
│   ├── lib
│   │   ├── features
│   │   │   └── custom_nodes
│   │   │       ├── custom_node_editor_panel.dart
│   │   │       └── custom_node_repository.dart
│   │   ├── main.dart
│   │   ├── models
│   │   │   ├── backend_deployment.dart
│   │   │   ├── module.dart
│   │   │   ├── pynq_launcher_action_result.dart
│   │   │   └── workspace_session.dart
│   │   ├── providers
│   │   │   └── riverpod_providers.dart
│   │   ├── routing
│   │   │   └── router.dart
│   │   ├── screens
│   │   │   ├── backend_setup.dart
│   │   │   ├── environment_editor.dart
│   │   │   ├── first_run_setup_screen.dart
│   │   │   ├── python_setup.dart
│   │   │   ├── server_setup.dart
│   │   │   ├── settings.dart
│   │   │   └── tool_view.dart
│   │   ├── services
│   │   │   ├── analytics_service.dart
│   │   │   ├── bundle_manager.dart
│   │   │   ├── control_api_service.dart
│   │   │   ├── cross_module_navigation.dart
│   │   │   ├── environment_api_service.dart
│   │   │   ├── launcher_control_bootstrap_service.dart
│   │   │   ├── process_manager.dart
│   │   │   └── update_service.dart
│   │   ├── src
│   │   │   └── features
│   │   │       ├── app
│   │   │       │   ├── domain
│   │   │       │   │   ├── app_state.dart
│   │   │       │   │   └── app_state.freezed.dart
│   │   │       │   └── presentation
│   │   │       │       ├── app_notifier.dart
│   │   │       │       ├── app_notifier.g.dart
│   │   │       │       └── command_provider.dart
│   │   │       ├── deployment
│   │   │       │   ├── domain
│   │   │       │   │   ├── deployment_state.dart
│   │   │       │   │   └── deployment_state.freezed.dart
│   │   │       │   └── presentation
│   │   │       │       ├── deployment_notifier.dart
│   │   │       │       └── deployment_notifier.g.dart
│   │   │       ├── environment
│   │   │       │   ├── domain
│   │   │       │   │   ├── environment_state.dart
│   │   │       │   │   └── environment_state.freezed.dart
│   │   │       │   └── presentation
│   │   │       │       ├── environment_notifier.dart
│   │   │       │       └── environment_notifier.g.dart
│   │   │       ├── module
│   │   │       │   ├── domain
│   │   │       │   │   ├── module_state.dart
│   │   │       │   │   └── module_state.freezed.dart
│   │   │       │   └── presentation
│   │   │       │       ├── module_notifier.dart
│   │   │       │       └── module_notifier.g.dart
│   │   │       ├── settings
│   │   │       │   ├── domain
│   │   │       │   │   ├── settings_state.dart
│   │   │       │   │   └── settings_state.freezed.dart
│   │   │       │   └── presentation
│   │   │       │       ├── settings_notifier.dart
│   │   │       │       └── settings_notifier.g.dart
│   │   │       └── workspace
│   │   │           ├── domain
│   │   │           │   ├── workspace_state.dart
│   │   │           │   └── workspace_state.freezed.dart
│   │   │           └── presentation
│   │   │               ├── workspace_notifier.dart
│   │   │               └── workspace_notifier.g.dart
│   │   ├── widgets
│   │   │   ├── module_error_view.dart
│   │   │   ├── module_icon.dart
│   │   │   ├── module_loading_view.dart
│   │   │   ├── module_picker_panel.dart
│   │   │   ├── module_tab_bar.dart
│   │   │   └── tool_view_header_actions.dart
│   │   └── workspace
│   │       └── native_surface_registry.dart
│   ├── linux
│   │   ├── CMakeLists.txt
│   │   ├── flutter
│   │   │   ├── CMakeLists.txt
│   │   │   ├── generated_plugin_registrant.cc
│   │   │   ├── generated_plugin_registrant.h
│   │   │   └── generated_plugins.cmake
│   │   └── runner
│   │       ├── CMakeLists.txt
│   │       ├── main.cc
│   │       ├── my_application.cc
│   │       └── my_application.h
│   ├── macos
│   │   ├── Flutter
│   │   │   ├── Flutter-Debug.xcconfig
│   │   │   ├── Flutter-Release.xcconfig
│   │   │   ├── GeneratedPluginRegistrant.swift
│   │   │   └── ephemeral
│   │   │       ├── Flutter-Generated.xcconfig
│   │   │       ├── FlutterInputs.xcfilelist
│   │   │       ├── FlutterMacOS.podspec
│   │   │       ├── FlutterOutputs.xcfilelist
│   │   │       ├── flutter_export_environment.sh
│   │   │       └── tripwire
│   │   ├── Podfile
│   │   ├── Podfile.lock
│   │   ├── Pods
│   │   │   ├── Headers
│   │   │   ├── Local Podspecs
│   │   │   │   ├── FlutterMacOS.podspec.json
│   │   │   │   ├── app_links.podspec.json
│   │   │   │   ├── audioplayers_darwin.podspec.json
│   │   │   │   ├── desktop_webview_window.podspec.json
│   │   │   │   ├── file_picker.podspec.json
│   │   │   │   ├── flutter_inappwebview_macos.podspec.json
│   │   │   │   ├── package_info_plus.podspec.json
│   │   │   │   ├── record_macos.podspec.json
│   │   │   │   ├── shared_preferences_foundation.podspec.json
│   │   │   │   ├── url_launcher_macos.podspec.json
│   │   │   │   └── webview_flutter_wkwebview.podspec.json
│   │   │   ├── Manifest.lock
│   │   │   ├── OrderedSet
│   │   │   │   ├── Framework
│   │   │   │   │   └── PrivacyInfo.xcprivacy
│   │   │   │   ├── LICENSE
│   │   │   │   ├── README.md
│   │   │   │   └── Sources
│   │   │   │       └── OrderedSet.swift
│   │   │   ├── Pods.xcodeproj
│   │   │   │   ├── project.pbxproj
│   │   │   │   └── xcuserdata
│   │   │   │       └── yoshimartodihardjo.xcuserdatad
│   │   │   │           └── xcschemes
│   │   │   │               ├── FlutterMacOS.xcscheme
│   │   │   │               ├── OrderedSet-OrderedSet_privacy.xcscheme
│   │   │   │               ├── OrderedSet.xcscheme
│   │   │   │               ├── Pods-Runner.xcscheme
│   │   │   │               ├── Pods-RunnerTests.xcscheme
│   │   │   │               ├── app_links-app_links_macos_privacy.xcscheme
│   │   │   │               ├── app_links.xcscheme
│   │   │   │               ├── audioplayers_darwin.xcscheme
│   │   │   │               ├── desktop_webview_window.xcscheme
│   │   │   │               ├── file_picker-file_picker_privacy.xcscheme
│   │   │   │               ├── file_picker.xcscheme
│   │   │   │               ├── flutter_inappwebview_macos-flutter_inappwebview_macos_privacy.xcscheme
│   │   │   │               ├── flutter_inappwebview_macos.xcscheme
│   │   │   │               ├── package_info_plus-package_info_plus_privacy.xcscheme
│   │   │   │               ├── package_info_plus.xcscheme
│   │   │   │               ├── record_macos-record_macos_privacy.xcscheme
│   │   │   │               ├── record_macos.xcscheme
│   │   │   │               ├── shared_preferences_foundation-shared_preferences_foundation_privacy.xcscheme
│   │   │   │               ├── shared_preferences_foundation.xcscheme
│   │   │   │               ├── url_launcher_macos-url_launcher_macos_privacy.xcscheme
│   │   │   │               ├── url_launcher_macos.xcscheme
│   │   │   │               ├── webview_flutter_wkwebview-webview_flutter_wkwebview_privacy.xcscheme
│   │   │   │               ├── webview_flutter_wkwebview.xcscheme
│   │   │   │               └── xcschememanagement.plist
│   │   │   └── Target Support Files
│   │   │       ├── FlutterMacOS
│   │   │       │   ├── FlutterMacOS.debug.xcconfig
│   │   │       │   └── FlutterMacOS.release.xcconfig
│   │   │       ├── OrderedSet
│   │   │       │   ├── OrderedSet-Info.plist
│   │   │       │   ├── OrderedSet-dummy.m
│   │   │       │   ├── OrderedSet-prefix.pch
│   │   │       │   ├── OrderedSet-umbrella.h
│   │   │       │   ├── OrderedSet.debug.xcconfig
│   │   │       │   ├── OrderedSet.modulemap
│   │   │       │   ├── OrderedSet.release.xcconfig
│   │   │       │   └── ResourceBundle-OrderedSet_privacy-OrderedSet-Info.plist
│   │   │       ├── Pods-Runner
│   │   │       │   ├── Pods-Runner-Info.plist
│   │   │       │   ├── Pods-Runner-acknowledgements.markdown
│   │   │       │   ├── Pods-Runner-acknowledgements.plist
│   │   │       │   ├── Pods-Runner-dummy.m
│   │   │       │   ├── Pods-Runner-frameworks-Debug-input-files.xcfilelist
│   │   │       │   ├── Pods-Runner-frameworks-Debug-output-files.xcfilelist
│   │   │       │   ├── Pods-Runner-frameworks-Profile-input-files.xcfilelist
│   │   │       │   ├── Pods-Runner-frameworks-Profile-output-files.xcfilelist
│   │   │       │   ├── Pods-Runner-frameworks-Release-input-files.xcfilelist
│   │   │       │   ├── Pods-Runner-frameworks-Release-output-files.xcfilelist
│   │   │       │   ├── Pods-Runner-frameworks.sh
│   │   │       │   ├── Pods-Runner-umbrella.h
│   │   │       │   ├── Pods-Runner.debug.xcconfig
│   │   │       │   ├── Pods-Runner.modulemap
│   │   │       │   ├── Pods-Runner.profile.xcconfig
│   │   │       │   └── Pods-Runner.release.xcconfig
│   │   │       ├── Pods-RunnerTests
│   │   │       │   ├── Pods-RunnerTests-Info.plist
│   │   │       │   ├── Pods-RunnerTests-acknowledgements.markdown
│   │   │       │   ├── Pods-RunnerTests-acknowledgements.plist
│   │   │       │   ├── Pods-RunnerTests-dummy.m
│   │   │       │   ├── Pods-RunnerTests-umbrella.h
│   │   │       │   ├── Pods-RunnerTests.debug.xcconfig
│   │   │       │   ├── Pods-RunnerTests.modulemap
│   │   │       │   ├── Pods-RunnerTests.profile.xcconfig
│   │   │       │   └── Pods-RunnerTests.release.xcconfig
│   │   │       ├── app_links
│   │   │       │   ├── ResourceBundle-app_links_macos_privacy-app_links-Info.plist
│   │   │       │   ├── app_links-Info.plist
│   │   │       │   ├── app_links-dummy.m
│   │   │       │   ├── app_links-prefix.pch
│   │   │       │   ├── app_links-umbrella.h
│   │   │       │   ├── app_links.debug.xcconfig
│   │   │       │   ├── app_links.modulemap
│   │   │       │   └── app_links.release.xcconfig
│   │   │       ├── audioplayers_darwin
│   │   │       │   ├── audioplayers_darwin-Info.plist
│   │   │       │   ├── audioplayers_darwin-dummy.m
│   │   │       │   ├── audioplayers_darwin-prefix.pch
│   │   │       │   ├── audioplayers_darwin-umbrella.h
│   │   │       │   ├── audioplayers_darwin.debug.xcconfig
│   │   │       │   ├── audioplayers_darwin.modulemap
│   │   │       │   └── audioplayers_darwin.release.xcconfig
│   │   │       ├── desktop_webview_window
│   │   │       │   ├── desktop_webview_window-Info.plist
│   │   │       │   ├── desktop_webview_window-dummy.m
│   │   │       │   ├── desktop_webview_window-prefix.pch
│   │   │       │   ├── desktop_webview_window-umbrella.h
│   │   │       │   ├── desktop_webview_window.debug.xcconfig
│   │   │       │   ├── desktop_webview_window.modulemap
│   │   │       │   └── desktop_webview_window.release.xcconfig
│   │   │       ├── file_picker
│   │   │       │   ├── ResourceBundle-file_picker_privacy-file_picker-Info.plist
│   │   │       │   ├── file_picker-Info.plist
│   │   │       │   ├── file_picker-dummy.m
│   │   │       │   ├── file_picker-prefix.pch
│   │   │       │   ├── file_picker-umbrella.h
│   │   │       │   ├── file_picker.debug.xcconfig
│   │   │       │   ├── file_picker.modulemap
│   │   │       │   └── file_picker.release.xcconfig
│   │   │       ├── flutter_inappwebview_macos
│   │   │       │   ├── ResourceBundle-flutter_inappwebview_macos_privacy-flutter_inappwebview_macos-Info.plist
│   │   │       │   ├── flutter_inappwebview_macos-Info.plist
│   │   │       │   ├── flutter_inappwebview_macos-dummy.m
│   │   │       │   ├── flutter_inappwebview_macos-prefix.pch
│   │   │       │   ├── flutter_inappwebview_macos-umbrella.h
│   │   │       │   ├── flutter_inappwebview_macos.debug.xcconfig
│   │   │       │   ├── flutter_inappwebview_macos.modulemap
│   │   │       │   └── flutter_inappwebview_macos.release.xcconfig
│   │   │       ├── package_info_plus
│   │   │       │   ├── ResourceBundle-package_info_plus_privacy-package_info_plus-Info.plist
│   │   │       │   ├── package_info_plus-Info.plist
│   │   │       │   ├── package_info_plus-dummy.m
│   │   │       │   ├── package_info_plus-prefix.pch
│   │   │       │   ├── package_info_plus-umbrella.h
│   │   │       │   ├── package_info_plus.debug.xcconfig
│   │   │       │   ├── package_info_plus.modulemap
│   │   │       │   └── package_info_plus.release.xcconfig
│   │   │       ├── record_macos
│   │   │       │   ├── ResourceBundle-record_macos_privacy-record_macos-Info.plist
│   │   │       │   ├── record_macos-Info.plist
│   │   │       │   ├── record_macos-dummy.m
│   │   │       │   ├── record_macos-prefix.pch
│   │   │       │   ├── record_macos-umbrella.h
│   │   │       │   ├── record_macos.debug.xcconfig
│   │   │       │   ├── record_macos.modulemap
│   │   │       │   └── record_macos.release.xcconfig
│   │   │       ├── shared_preferences_foundation
│   │   │       │   ├── ResourceBundle-shared_preferences_foundation_privacy-shared_preferences_foundation-Info.plist
│   │   │       │   ├── shared_preferences_foundation-Info.plist
│   │   │       │   ├── shared_preferences_foundation-dummy.m
│   │   │       │   ├── shared_preferences_foundation-prefix.pch
│   │   │       │   ├── shared_preferences_foundation-umbrella.h
│   │   │       │   ├── shared_preferences_foundation.debug.xcconfig
│   │   │       │   ├── shared_preferences_foundation.modulemap
│   │   │       │   └── shared_preferences_foundation.release.xcconfig
│   │   │       ├── url_launcher_macos
│   │   │       │   ├── ResourceBundle-url_launcher_macos_privacy-url_launcher_macos-Info.plist
│   │   │       │   ├── url_launcher_macos-Info.plist
│   │   │       │   ├── url_launcher_macos-dummy.m
│   │   │       │   ├── url_launcher_macos-prefix.pch
│   │   │       │   ├── url_launcher_macos-umbrella.h
│   │   │       │   ├── url_launcher_macos.debug.xcconfig
│   │   │       │   ├── url_launcher_macos.modulemap
│   │   │       │   └── url_launcher_macos.release.xcconfig
│   │   │       └── webview_flutter_wkwebview
│   │   │           ├── ResourceBundle-webview_flutter_wkwebview_privacy-webview_flutter_wkwebview-Info.plist
│   │   │           ├── webview_flutter_wkwebview-Info.plist
│   │   │           ├── webview_flutter_wkwebview-dummy.m
│   │   │           ├── webview_flutter_wkwebview-prefix.pch
│   │   │           ├── webview_flutter_wkwebview-umbrella.h
│   │   │           ├── webview_flutter_wkwebview.debug.xcconfig
│   │   │           ├── webview_flutter_wkwebview.modulemap
│   │   │           └── webview_flutter_wkwebview.release.xcconfig
│   │   ├── Runner
│   │   │   ├── AppDelegate.swift
│   │   │   ├── Assets.xcassets
│   │   │   │   └── AppIcon.appiconset
│   │   │   │       ├── Contents.json
│   │   │   │       ├── app_icon_1024.png
│   │   │   │       ├── app_icon_128.png
│   │   │   │       ├── app_icon_16.png
│   │   │   │       ├── app_icon_256.png
│   │   │   │       ├── app_icon_32.png
│   │   │   │       ├── app_icon_512.png
│   │   │   │       └── app_icon_64.png
│   │   │   ├── Base.lproj
│   │   │   │   └── MainMenu.xib
│   │   │   ├── Configs
│   │   │   │   ├── AppInfo.xcconfig
│   │   │   │   ├── Debug.xcconfig
│   │   │   │   ├── Release.xcconfig
│   │   │   │   └── Warnings.xcconfig
│   │   │   ├── DebugProfile.entitlements
│   │   │   ├── Info.plist
│   │   │   ├── MainFlutterWindow.swift
│   │   │   └── Release.entitlements
│   │   ├── Runner.xcodeproj
│   │   │   ├── project.pbxproj
│   │   │   ├── project.xcworkspace
│   │   │   │   └── xcshareddata
│   │   │   │       ├── IDEWorkspaceChecks.plist
│   │   │   │       └── swiftpm
│   │   │   │           └── configuration
│   │   │   └── xcshareddata
│   │   │       └── xcschemes
│   │   │           └── Runner.xcscheme
│   │   ├── Runner.xcworkspace
│   │   │   ├── contents.xcworkspacedata
│   │   │   └── xcshareddata
│   │   │       ├── IDEWorkspaceChecks.plist
│   │   │       └── swiftpm
│   │   │           └── configuration
│   │   └── RunnerTests
│   │       └── RunnerTests.swift
│   ├── module_states.json
│   ├── pubspec.lock
│   ├── pubspec.yaml
│   ├── test
│   │   ├── E2E_TEST_REPORT.md
│   │   ├── analytics_test.dart
│   │   ├── app_test.dart
│   │   ├── bundle_manager_test.dart
│   │   ├── cross_module_navigation_test.dart
│   │   ├── governance
│   │   │   └── material_icons_audit_test.dart
│   │   ├── launcher_control_bootstrap_service_test.dart
│   │   ├── launcher_e2e_test.dart
│   │   ├── module_provider_equality_test.dart
│   │   ├── process_manager_test.dart
│   │   ├── tool_view_shell_test.dart
│   │   └── update_service_test.dart
│   ├── web
│   │   ├── favicon.png
│   │   ├── icons
│   │   │   ├── Icon-192.png
│   │   │   ├── Icon-512.png
│   │   │   ├── Icon-maskable-192.png
│   │   │   └── Icon-maskable-512.png
│   │   ├── index.html
│   │   └── manifest.json
│   ├── windows
│   │   ├── CMakeLists.txt
│   │   ├── flutter
│   │   │   ├── CMakeLists.txt
│   │   │   ├── generated_plugin_registrant.cc
│   │   │   ├── generated_plugin_registrant.h
│   │   │   └── generated_plugins.cmake
│   │   └── runner
│   │       ├── CMakeLists.txt
│   │       ├── Runner.rc
│   │       ├── flutter_window.cpp
│   │       ├── flutter_window.h
│   │       ├── main.cpp
│   │       ├── resource.h
│   │       ├── resources
│   │       │   └── app_icon.ico
│   │       ├── runner.exe.manifest
│   │       ├── utils.cpp
│   │       ├── utils.h
│   │       ├── win32_window.cpp
│   │       └── win32_window.h
│   └── workspace_state.json
├── neurocnl_complete_reference.md
├── packages
│   ├── README.md
│   ├── neurobench_feature
│   │   ├── CHANGELOG.md
│   │   ├── LICENSE
│   │   ├── README.md
│   │   ├── analysis_options.yaml
│   │   ├── lib
│   │   │   ├── neurobench_feature.dart
│   │   │   └── src
│   │   │       └── neurobench_shell.dart
│   │   ├── neurobench_feature.iml
│   │   ├── pubspec.lock
│   │   ├── pubspec.yaml
│   │   └── test
│   │       └── neurobench_feature_test.dart
│   ├── neurochip_feature
│   │   ├── CHANGELOG.md
│   │   ├── LICENSE
│   │   ├── README.md
│   │   ├── analysis_options.yaml
│   │   ├── lib
│   │   │   ├── neurochip_feature.dart
│   │   │   └── src
│   │   │       ├── neurochip_shell.dart
│   │   │       └── neurochip_shell_adapter.dart
│   │   ├── neurochip_feature.iml
│   │   ├── pubspec.lock
│   │   ├── pubspec.yaml
│   │   └── test
│   │       └── neurochip_feature_test.dart
│   ├── neurocnl_feature
│   │   ├── CHANGELOG.md
│   │   ├── LICENSE
│   │   ├── README.md
│   │   ├── analysis_options.yaml
│   │   ├── lib
│   │   │   ├── neurocnl_feature.dart
│   │   │   └── src
│   │   │       └── neurocnl_shell.dart
│   │   ├── neurocnl_feature.iml
│   │   ├── pubspec.lock
│   │   ├── pubspec.yaml
│   │   └── test
│   │       └── neurocnl_feature_test.dart
│   ├── neurohub_feature
│   │   ├── CHANGELOG.md
│   │   ├── LICENSE
│   │   ├── README.md
│   │   ├── analysis_options.yaml
│   │   ├── lib
│   │   │   ├── neurohub_feature.dart
│   │   │   └── src
│   │   │       └── neurohub_shell.dart
│   │   ├── neurohub_feature.iml
│   │   ├── pubspec.lock
│   │   ├── pubspec.yaml
│   │   └── test
│   │       └── neurohub_feature_test.dart
│   ├── neurosense_feature
│   │   ├── CHANGELOG.md
│   │   ├── LICENSE
│   │   ├── README.md
│   │   ├── analysis_options.yaml
│   │   ├── lib
│   │   │   ├── neurosense_feature.dart
│   │   │   └── src
│   │   │       └── neurosense_shell.dart
│   │   ├── neurosense_feature.iml
│   │   ├── pubspec.lock
│   │   ├── pubspec.yaml
│   │   └── test
│   │       └── neurosense_feature_test.dart
│   └── neurosim_feature
│       ├── CHANGELOG.md
│       ├── LICENSE
│       ├── README.md
│       ├── analysis_options.yaml
│       ├── lib
│       │   ├── neurosim_feature.dart
│       │   └── src
│       │       └── neurosim_shell.dart
│       ├── neurosim_feature.iml
│       ├── pubspec.lock
│       ├── pubspec.yaml
│       └── test
│           └── neurosim_feature_test.dart
├── scripts
│   ├── setup.ps1
│   └── setup.sh
├── servo_control
│   └── servo_control.ino
└── user-install-improvement.md
</directory_structure>

## Widget State Sync Rules

- **Never mutate local `ConsumerStatefulWidget` state directly inside `build()`** without calling
  `setState()`. Use `ref.listen` with `setState` to react to provider changes. The canonical pattern
  in this codebase is in `studio_screen.dart` (ref.listen inside build, before any early returns).
  Specifically: `_activeModuleId` in `tool_view.dart` must be updated via `ref.listen` only.
- **`ref.listen` must be called unconditionally** on every `build()` invocation — before any
  `if (...) return` guard. Placing it after an early return violates Riverpod's hook-consistency
  contract and causes subscription mis-tracking when the guard condition changes.
- There is no in-app Settings screen or route (removed — see git history for the prior
  `/settings` route and `SettingsScreen`). `settingsProvider` / `SettingsNotifier` / `SettingsState`
  still exist and back app-wide theming and launcher bootstrap; do not resurrect a Settings UI
  around them without re-establishing this section's guidance.

## Remote Testing Configuration

For dev, `REMOTE_HOST=moosebun2@192.168.68.53` can be used. For example, when the agent wants to test run the app, you can use `192.168.68.53` as the server address.
