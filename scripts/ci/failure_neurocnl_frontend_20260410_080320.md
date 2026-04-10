# CI Failure Report: neurocnl_frontend

**Date:** 2026-04-10 08:03:20

## Failed Stages

### test

```
Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 93.0.0 (99.0.0 available)
  analyzer 10.0.1 (12.1.0 available)
  async 2.13.0 (2.13.1 available)
  built_value 8.12.4 (8.12.5 available)
  dart_style 3.1.7 (3.1.8 available)
  flutter_lints 3.0.2 (6.0.0 available)
  flutter_riverpod 2.6.1 (3.3.1 available)
  go_router 14.8.1 (17.2.0 available)
  google_fonts 6.3.3 (8.0.2 available)
  lints 3.0.0 (6.1.0 available)
  meta 1.17.0 (1.18.2 available)
  mockito 5.6.3 (5.6.4 available)
  path_provider_android 2.2.22 (2.3.1 available)
  path_provider_foundation 2.5.1 (2.6.0 available)
  riverpod 2.6.1 (3.2.1 available)
  riverpod_annotation 2.6.1 (4.0.2 available)
  shared_preferences 2.5.4 (2.5.5 available)
  shared_preferences_android 2.4.21 (2.4.23 available)
  shared_preferences_platform_interface 2.4.1 (2.4.2 available)
  test_api 0.7.10 (0.7.11 available)
  vector_math 2.2.0 (2.3.0 available)
Got dependencies!
21 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/models_serialization_test.dart
00:00 +0: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/models_serialization_test.dart: ParsedSpec Serialization ParsedSpec.fromJson correctly parses valid JSON
00:00 +1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/models_serialization_test.dart: ParsedSpec Serialization ParseSentence.fromJson correctly parses valid JSON
00:00 +2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/models_serialization_test.dart: ParsedSpec Serialization ParseSentence.fromJson parses structured error details
00:00 +3: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/models_serialization_test.dart: ParsedSpec Serialization ParseResult.fromJson correctly parses valid JSON
00:00 +4: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/models_serialization_test.dart: SimulationResult Serialization ProbeData.fromJson correctly parses spike_raster JSON
00:00 +5: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/models_serialization_test.dart: SimulationResult Serialization ProbeData.fromJson correctly parses continuous JSON
00:00 +6: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/models_serialization_test.dart: SimulationResult Serialization SimulationSummary.fromJson correctly parses valid JSON
00:00 +7: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/models_serialization_test.dart: SimulationResult Serialization SimulationResult.fromJson correctly parses valid JSON
00:00 +8: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/models_serialization_test.dart: ValidationResult Serialization Layer2 failures prefer normalized fields over legacy fallback
00:00 +9: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/models_serialization_test.dart: HealthStatus Serialization HealthStatus.fromJson tolerates missing disk payload
00:00 +10: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: (setUpAll)
00:00 +10: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: SpecTextNotifier initial state is empty string
00:00 +11: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: SpecTextNotifier set updates state immediately
00:00 +12: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: SpecTextNotifier update triggers callback after debounce delay
00:00 +13: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: PipelineNotifier initial state is idle
00:00 +14: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: PipelineNotifier runParseAndValidate updates state correctly on success
00:00 +15: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: PipelineNotifier initialization restores cached backend support payload
00:00 +16: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: PipelineNotifier runGenerateAndSimulate updates state correctly on success
00:00 +17: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: PipelineNotifier runGenerateAndSimulate sets error state if generate fails
00:00 +18: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: PipelineNotifier runGenerateAndSimulate sets error state if simulate fails
00:00 +19: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: PipelineNotifier reset clears state correctly
00:00 +20: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: PipelineNotifier runParseAndValidate sets error state if parse fails
00:00 +21: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/providers_test.dart: (tearDownAll)
00:01 +21: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widget_test.dart: App renders without crashing
00:01 +22: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widget_test.dart: App renders without crashing
00:01 +23: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widget_test.dart: App renders without crashing
00:01 +24: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widget_test.dart: App renders without crashing
00:01 +25: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widget_test.dart: App renders without crashing
00:01 +26: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widget_test.dart: App renders without crashing
00:02 +27: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widget_test.dart: App renders without crashing
00:02 +28: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/pipeline_integration_test.dart: Full pipeline flow: edit -> run -> results
00:02 +29: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/pipeline_integration_test.dart: Full pipeline flow: edit -> run -> results
00:02 +30: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/pipeline_integration_test.dart: Full pipeline flow: edit -> run -> results
00:02 +31: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/pipeline_integration_test.dart: Full pipeline flow: edit -> run -> results
00:03 +32: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/pipeline_integration_test.dart: Full pipeline flow: edit -> run -> results
00:03 +33: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/pipeline_integration_test.dart: Full pipeline flow: edit -> run -> results
00:03 +34: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/pipeline_integration_test.dart: Full pipeline flow: edit -> run -> results
00:03 +35: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/pipeline_integration_test.dart: Full pipeline flow: edit -> run -> results
00:03 +36: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/fault_injection_tab_test.dart: Fault Injection Tab Tests Empty State - Initial Render
00:04 +37: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/error_reporting_test.dart: ParseResultsTable shows structured parse hints and examples
00:04 +38: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/error_reporting_test.dart: ParseResultsTable shows structured parse hints and examples
00:04 +39: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/error_reporting_test.dart: ParseResultsTable shows structured parse hints and examples
00:04 +40: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/simulation_dashboard_test.dart: SimulationDashboard shows placeholder when no simulation result
══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════════════════════════════════════════════
The following _TypeError was thrown building SimulationDashboard(dirty, dependencies:
[UncontrolledProviderScope, _LocalizationsScope-[GlobalKey#322f5]], state: _ConsumerState#e4ad2):
Null check operator used on a null value

The relevant error-causing widget was:
  SimulationDashboard
  SimulationDashboard:file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/simulation_dashboard_test.dart:20:32

When the exception was thrown, this was the stack:
#0      SimulationDashboard.build (package:neurocnl_studio/widgets/simulation_dashboard.dart:20:46)
#1      _ConsumerState.build (package:flutter_riverpod/src/consumer.dart:476:19)
#2      StatefulElement.build (package:flutter/src/widgets/framework.dart:5931:27)
#3      ConsumerStatefulElement.build (package:flutter_riverpod/src/consumer.dart:539:20)
#4      ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5817:15)
#5      StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#6      Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#7      ComponentElement._firstBuild (package:flutter/src/widgets/framework.dart:5799:5)
#8      StatefulElement._firstBuild (package:flutter/src/widgets/framework.dart:5973:11)
#9      ComponentElement.mount (package:flutter/src/widgets/framework.dart:5793:5)
...     Normal element mounting (25 frames)
#34     Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#35     MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:7264:36)
#36     MultiChildRenderObjectElement.mount (package:flutter/src/widgets/framework.dart:7279:32)
...     Normal element mounting (364 frames)
#400    Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#401    MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:7264:36)
#402    MultiChildRenderObjectElement.mount (package:flutter/src/widgets/framework.dart:7279:32)
...     Normal element mounting (473 frames)
#875    _UncontrolledProviderScopeElement.mount (package:flutter_riverpod/src/framework.dart:315:11)
...     Normal element mounting (9 frames)
#884    Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#885    Element.updateChild (package:flutter/src/widgets/framework.dart:4053:20)
#886    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#887    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#888    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#889    _InheritedNotifierElement.update (package:flutter/src/widgets/inherited_notifier.dart:108:11)
#890    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#891    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#892    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#893    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#894    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#895    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#896    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#897    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#898    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#899    _InheritedNotifierElement.update (package:flutter/src/widgets/inherited_notifier.dart:108:11)
#900    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#901    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#902    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#903    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#904    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#905    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#906    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#907    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#908    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#909    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#910    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#911    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#912    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#913    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#914    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#915    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#916    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#917    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#918    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#919    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#920    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#921    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#922    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#923    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#924    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#925    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#926    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#927    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#928    _RawViewElement._updateChild (package:flutter/src/widgets/view.dart:481:16)
#929    _RawViewElement.update (package:flutter/src/widgets/view.dart:568:5)
#930    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#931    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#932    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#933    StatelessElement.update (package:flutter/src/widgets/framework.dart:5895:5)
#934    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#935    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#936    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#937    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#938    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#939    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#940    RootElement._rebuild (package:flutter/src/widgets/binding.dart:1822:16)
#941    RootElement.update (package:flutter/src/widgets/binding.dart:1800:5)
#942    RootElement.performRebuild (package:flutter/src/widgets/binding.dart:1814:7)
#943    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#944    BuildScope._tryRebuild (package:flutter/src/widgets/framework.dart:2750:15)
#945    BuildScope._flushDirtyElements (package:flutter/src/widgets/framework.dart:2807:11)
#946    BuildOwner.buildScope (package:flutter/src/widgets/framework.dart:3111:18)
#947    AutomatedTestWidgetsFlutterBinding.drawFrame (package:flutter_test/src/binding.dart:2131:19)
#948    RendererBinding._handlePersistentFrameCallback (package:flutter/src/rendering/binding.dart:495:5)
#949    SchedulerBinding._invokeFrameCallback (package:flutter/src/scheduler/binding.dart:1430:15)
#950    SchedulerBinding.handleDrawFrame (package:flutter/src/scheduler/binding.dart:1345:9)
#951    AutomatedTestWidgetsFlutterBinding.pump.<anonymous closure> (package:flutter_test/src/binding.dart:1960:9)
#954    TestAsyncUtils.guard (package:flutter_test/src/test_async_utils.dart:74:41)
#955    AutomatedTestWidgetsFlutterBinding.pump (package:flutter_test/src/binding.dart:1949:27)
#956    WidgetTester.pumpWidget.<anonymous closure> (package:flutter_test/src/widget_tester.dart:598:22)
#959    TestAsyncUtils.guard (package:flutter_test/src/test_async_utils.dart:74:41)
#960    WidgetTester.pumpWidget (package:flutter_test/src/widget_tester.dart:595:27)
#961    main.<anonymous closure> (file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/simulation_dashboard_test.dart:17:18)
#962    testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:29)
<asynchronous suspension>
#963    TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1682:5)
<asynchronous suspension>
<asynchronous suspension>
(elided 5 frames from dart:async and package:stack_trace)

════════════════════════════════════════════════════════════════════════════════════════════════════
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following TestFailure was thrown running a test:
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Run a simulation to see results here.": []>
   Which: means none were found but one was expected

When the exception was thrown, this was the stack:
#4      main.<anonymous closure> (file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/simulation_dashboard_test.dart:25:5)
<asynchronous suspension>
#5      testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:15)
<asynchronous suspension>
#6      TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1682:5)
<asynchronous suspension>
<asynchronous suspension>
(elided one frame from package:stack_trace)

This was caught by the test expectation on the following line:
  file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/simulation_dashboard_test.dart line 25
The test description was:
  SimulationDashboard shows placeholder when no simulation result
════════════════════════════════════════════════════════════════════════════════════════════════════
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following message was thrown:
Multiple exceptions (2) were detected during the running of the current test, and at least one was
unexpected.
════════════════════════════════════════════════════════════════════════════════════════════════════
00:04 +40 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/teensy_deploy_panel_test.dart: TeensyDeployPanel shows CircularProgressIndicator when validating
00:04 +40 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/simulation_dashboard_test.dart: SimulationDashboard shows placeholder when no simulation result [E]
  Test failed. See exception logs above.
  The test description was: SimulationDashboard shows placeholder when no simulation result
  
00:04 +41 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/teensy_deploy_panel_test.dart: TeensyDeployPanel shows CircularProgressIndicator when validating
00:04 +41 -1: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/simulation_dashboard_test.dart: SimulationDashboard renders summary and plots when result is present
══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════════════════════════════════════════════
The following _TypeError was thrown building SimulationDashboard(dirty, dependencies:
[UncontrolledProviderScope, _LocalizationsScope-[GlobalKey#df969]], state: _ConsumerState#f2ced):
Null check operator used on a null value

The relevant error-causing widget was:
  SimulationDashboard
  SimulationDashboard:file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/simulation_dashboard_test.dart:62:32

When the exception was thrown, this was the stack:
#0      SimulationDashboard.build (package:neurocnl_studio/widgets/simulation_dashboard.dart:20:46)
#1      _ConsumerState.build (package:flutter_riverpod/src/consumer.dart:476:19)
#2      StatefulElement.build (package:flutter/src/widgets/framework.dart:5931:27)
#3      ConsumerStatefulElement.build (package:flutter_riverpod/src/consumer.dart:539:20)
#4      ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5817:15)
#5      StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#6      Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#7      ComponentElement._firstBuild (package:flutter/src/widgets/framework.dart:5799:5)
#8      StatefulElement._firstBuild (package:flutter/src/widgets/framework.dart:5973:11)
#9      ComponentElement.mount (package:flutter/src/widgets/framework.dart:5793:5)
...     Normal element mounting (25 frames)
#34     Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#35     MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:7264:36)
#36     MultiChildRenderObjectElement.mount (package:flutter/src/widgets/framework.dart:7279:32)
...     Normal element mounting (364 frames)
#400    Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#401    MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:7264:36)
#402    MultiChildRenderObjectElement.mount (package:flutter/src/widgets/framework.dart:7279:32)
...     Normal element mounting (473 frames)
#875    _UncontrolledProviderScopeElement.mount (package:flutter_riverpod/src/framework.dart:315:11)
...     Normal element mounting (9 frames)
#884    Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#885    Element.updateChild (package:flutter/src/widgets/framework.dart:4053:20)
#886    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#887    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#888    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#889    _InheritedNotifierElement.update (package:flutter/src/widgets/inherited_notifier.dart:108:11)
#890    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#891    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#892    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#893    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#894    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#895    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#896    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#897    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#898    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#899    _InheritedNotifierElement.update (package:flutter/src/widgets/inherited_notifier.dart:108:11)
#900    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#901    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#902    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#903    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#904    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#905    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#906    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#907    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#908    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#909    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#910    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#911    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#912    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#913    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#914    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#915    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#916    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#917    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#918    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#919    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#920    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#921    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#922    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#923    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#924    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#925    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#926    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#927    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#928    _RawViewElement._updateChild (package:flutter/src/widgets/view.dart:481:16)
#929    _RawViewElement.update (package:flutter/src/widgets/view.dart:568:5)
#930    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#931    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#932    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#933    StatelessElement.update (package:flutter/src/widgets/framework.dart:5895:5)
#934    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#935    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#936    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#937    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#938    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#939    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#940    RootElement._rebuild (package:flutter/src/widgets/binding.dart:1822:16)
#941    RootElement.update (package:flutter/src/widgets/binding.dart:1800:5)
#942    RootElement.performRebuild (package:flutter/src/widgets/binding.dart:1814:7)
#943    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#944    BuildScope._tryRebuild (package:flutter/src/widgets/framework.dart:2750:15)
#945    BuildScope._flushDirtyElements (package:flutter/src/widgets/framework.dart:2807:11)
#946    BuildOwner.buildScope (package:flutter/src/widgets/framework.dart:3111:18)
#947    AutomatedTestWidgetsFlutterBinding.drawFrame (package:flutter_test/src/binding.dart:2131:19)
#948    RendererBinding._handlePersistentFrameCallback (package:flutter/src/rendering/binding.dart:495:5)
#949    SchedulerBinding._invokeFrameCallback (package:flutter/src/scheduler/binding.dart:1430:15)
#950    SchedulerBinding.handleDrawFrame (package:flutter/src/scheduler/binding.dart:1345:9)
#951    AutomatedTestWidgetsFlutterBinding.pump.<anonymous closure> (package:flutter_test/src/binding.dart:1960:9)
#954    TestAsyncUtils.guard (package:flutter_test/src/test_async_utils.dart:74:41)
#955    AutomatedTestWidgetsFlutterBinding.pump (package:flutter_test/src/binding.dart:1949:27)
#956    WidgetTester.pumpWidget.<anonymous closure> (package:flutter_test/src/widget_tester.dart:598:22)
#959    TestAsyncUtils.guard (package:flutter_test/src/test_async_utils.dart:74:41)
#960    WidgetTester.pumpWidget (package:flutter_test/src/widget_tester.dart:595:27)
#961    main.<anonymous closure> (file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/simulation_dashboard_test.dart:54:18)
#962    testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:29)
<asynchronous suspension>
#963    TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1682:5)
<asynchronous suspension>
<asynchronous suspension>
(elided 5 frames from dart:async and package:stack_trace)

════════════════════════════════════════════════════════════════════════════════════════════════════
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following TestFailure was thrown running a test:
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Simulation Summary": []>
   Which: means none were found but one was expected

When the exception was thrown, this was the stack:
#4      main.<anonymous closure> (file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/simulation_dashboard_test.dart:71:5)
<asynchronous suspension>
#5      testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:15)
<asynchronous suspension>
#6      TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1682:5)
<asynchronous suspension>
<asynchronous suspension>
(elided one frame from package:stack_trace)

This was caught by the test expectation on the following line:
  file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/simulation_dashboard_test.dart line 71
The test description was:
  SimulationDashboard renders summary and plots when result is present
════════════════════════════════════════════════════════════════════════════════════════════════════
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following message was thrown:
Multiple exceptions (2) were detected during the running of the current test, and at least one was
unexpected.
════════════════════════════════════════════════════════════════════════════════════════════════════
00:04 +41 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/teensy_deploy_panel_test.dart: TeensyDeployPanel shows CircularProgressIndicator when validating
00:04 +41 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/simulation_dashboard_test.dart: SimulationDashboard renders summary and plots when result is present [E]
  Test failed. See exception logs above.
  The test description was: SimulationDashboard renders summary and plots when result is present
  
00:04 +41 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/teensy_deploy_panel_test.dart: TeensyDeployPanel shows CircularProgressIndicator when validating
00:04 +42 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/teensy_deploy_panel_test.dart: TeensyDeployPanel shows CircularProgressIndicator when validating
00:05 +43 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/teensy_deploy_panel_test.dart: TeensyDeployPanel shows green faithful badge when verdict is faithful
00:05 +44 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/mujoco_stream_view_test.dart: MujocoStreamView shows unavailable state text
00:05 +45 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/mujoco_stream_view_test.dart: MujocoStreamView shows unavailable state text
00:05 +46 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/mujoco_stream_view_test.dart: MujocoStreamView shows unavailable state text
00:05 +47 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/mujoco_stream_view_test.dart: MujocoStreamView shows unavailable state text
00:05 +48 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/mujoco_stream_view_test.dart: MujocoStreamView shows unavailable state text
00:05 +49 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/mujoco_stream_view_test.dart: MujocoStreamView shows unavailable state text
00:05 +50 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/mujoco_stream_view_test.dart: MujocoStreamView shows unavailable state text
00:05 +51 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/mujoco_stream_view_test.dart: MujocoStreamView shows unavailable state text
00:05 +52 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/mujoco_stream_view_test.dart: MujocoStreamView shows unavailable state text
00:05 +53 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/mujoco_stream_view_test.dart: MujocoStreamView shows unavailable state text
00:05 +54 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/mujoco_stream_view_test.dart: MujocoStreamView shows videocam_off icon
00:05 +55 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/mujoco_stream_view_test.dart: MujocoStreamView does not contain "coming soon" text
00:05 +56 -2: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart: ParameterExplorer shows placeholder when no numeric values in spec
══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════════════════════════════════════════════
The following LateError was thrown building ParameterExplorer(dirty, dependencies:
[UncontrolledProviderScope], state: _ParameterExplorerState#3929f):
LateInitializationError: Field '_prefs@304450276' has not been initialized.

The relevant error-causing widget was:
  ParameterExplorer
  ParameterExplorer:file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart:15:32

When the exception was thrown, this was the stack:
#1      _ProviderStateSubscription.read (package:riverpod/src/framework/provider_base.dart:181:28)
#2      ConsumerStatefulElement.watch (package:flutter_riverpod/src/consumer.dart:568:8)
#3      _ParameterExplorerState.build (package:neurocnl_studio/widgets/parameter_explorer.dart:44:22)
#4      StatefulElement.build (package:flutter/src/widgets/framework.dart:5931:27)
#5      ConsumerStatefulElement.build (package:flutter_riverpod/src/consumer.dart:539:20)
#6      ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5817:15)
#7      StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#8      Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#9      ComponentElement._firstBuild (package:flutter/src/widgets/framework.dart:5799:5)
#10     StatefulElement._firstBuild (package:flutter/src/widgets/framework.dart:5973:11)
#11     ComponentElement.mount (package:flutter/src/widgets/framework.dart:5793:5)
...     Normal element mounting (25 frames)
#36     Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#37     MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:7264:36)
#38     MultiChildRenderObjectElement.mount (package:flutter/src/widgets/framework.dart:7279:32)
...     Normal element mounting (364 frames)
#402    Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#403    MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:7264:36)
#404    MultiChildRenderObjectElement.mount (package:flutter/src/widgets/framework.dart:7279:32)
...     Normal element mounting (473 frames)
#877    _UncontrolledProviderScopeElement.mount (package:flutter_riverpod/src/framework.dart:315:11)
...     Normal element mounting (9 frames)
#886    Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#887    Element.updateChild (package:flutter/src/widgets/framework.dart:4053:20)
#888    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#889    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#890    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#891    _InheritedNotifierElement.update (package:flutter/src/widgets/inherited_notifier.dart:108:11)
#892    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#893    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#894    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#895    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#896    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#897    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#898    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#899    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#900    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#901    _InheritedNotifierElement.update (package:flutter/src/widgets/inherited_notifier.dart:108:11)
#902    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#903    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#904    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#905    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#906    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#907    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#908    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#909    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#910    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#911    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#912    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#913    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#914    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#915    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#916    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#917    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#918    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#919    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#920    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#921    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#922    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#923    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#924    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#925    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#926    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#927    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#928    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#929    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#930    _RawViewElement._updateChild (package:flutter/src/widgets/view.dart:481:16)
#931    _RawViewElement.update (package:flutter/src/widgets/view.dart:568:5)
#932    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#933    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#934    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#935    StatelessElement.update (package:flutter/src/widgets/framework.dart:5895:5)
#936    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#937    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#938    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#939    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#940    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#941    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#942    RootElement._rebuild (package:flutter/src/widgets/binding.dart:1822:16)
#943    RootElement.update (package:flutter/src/widgets/binding.dart:1800:5)
#944    RootElement.performRebuild (package:flutter/src/widgets/binding.dart:1814:7)
#945    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#946    BuildScope._tryRebuild (package:flutter/src/widgets/framework.dart:2750:15)
#947    BuildScope._flushDirtyElements (package:flutter/src/widgets/framework.dart:2807:11)
#948    BuildOwner.buildScope (package:flutter/src/widgets/framework.dart:3111:18)
#949    AutomatedTestWidgetsFlutterBinding.drawFrame (package:flutter_test/src/binding.dart:2131:19)
#950    RendererBinding._handlePersistentFrameCallback (package:flutter/src/rendering/binding.dart:495:5)
#951    SchedulerBinding._invokeFrameCallback (package:flutter/src/scheduler/binding.dart:1430:15)
#952    SchedulerBinding.handleDrawFrame (package:flutter/src/scheduler/binding.dart:1345:9)
#953    AutomatedTestWidgetsFlutterBinding.pump.<anonymous closure> (package:flutter_test/src/binding.dart:1960:9)
#956    TestAsyncUtils.guard (package:flutter_test/src/test_async_utils.dart:74:41)
#957    AutomatedTestWidgetsFlutterBinding.pump (package:flutter_test/src/binding.dart:1949:27)
#958    WidgetTester.pumpWidget.<anonymous closure> (package:flutter_test/src/widget_tester.dart:598:22)
#961    TestAsyncUtils.guard (package:flutter_test/src/test_async_utils.dart:74:41)
#962    WidgetTester.pumpWidget (package:flutter_test/src/widget_tester.dart:595:27)
#963    main.<anonymous closure> (file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart:9:18)
#964    testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:29)
#965    TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1682:5)
#967    ServerConfigService._prefs (package:neurocnl_studio/services/server_config_service.dart:0:0)
#968    ServerConfigService.getString (package:neurocnl_studio/services/server_config_service.dart:39:43)
#969    new SpecTextNotifier (package:neurocnl_studio/providers/spec_provider.dart:15:50)
#970    main.<anonymous closure>.<anonymous closure> (file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart:12:50)
#971    ProviderContainer.listen (package:riverpod/src/framework/container.dart:280:21)
#972    ConsumerStatefulElement.watch.<anonymous closure> (package:flutter_riverpod/src/consumer.dart:564:25)
#973    _LinkedHashMapMixin.putIfAbsent (dart:_compact_hash:675:23)
#974    ConsumerStatefulElement.watch (package:flutter_riverpod/src/consumer.dart:557:26)
#975    _ParameterExplorerState.build (package:neurocnl_studio/widgets/parameter_explorer.dart:44:22)
#976    StatefulElement.build (package:flutter/src/widgets/framework.dart:5931:27)
#977    ConsumerStatefulElement.build (package:flutter_riverpod/src/consumer.dart:539:20)
#978    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5817:15)
#979    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#980    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#981    ComponentElement._firstBuild (package:flutter/src/widgets/framework.dart:5799:5)
#982    StatefulElement._firstBuild (package:flutter/src/widgets/framework.dart:5973:11)
#983    ComponentElement.mount (package:flutter/src/widgets/framework.dart:5793:5)
...     Normal element mounting (25 frames)
#1008   Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#1009   MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:7264:36)
#1010   MultiChildRenderObjectElement.mount (package:flutter/src/widgets/framework.dart:7279:32)
...     Normal element mounting (364 frames)
#1374   Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#1375   MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:7264:36)
#1376   MultiChildRenderObjectElement.mount (package:flutter/src/widgets/framework.dart:7279:32)
...     Normal element mounting (473 frames)
#1849   _UncontrolledProviderScopeElement.mount (package:flutter_riverpod/src/framework.dart:315:11)
...     Normal element mounting (9 frames)
#1858   Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#1859   Element.updateChild (package:flutter/src/widgets/framework.dart:4053:20)
#1860   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1861   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1862   ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#1863   _InheritedNotifierElement.update (package:flutter/src/widgets/inherited_notifier.dart:108:11)
#1864   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1865   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1866   StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#1867   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1868   StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#1869   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1870   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1871   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1872   ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#1873   _InheritedNotifierElement.update (package:flutter/src/widgets/inherited_notifier.dart:108:11)
#1874   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1875   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1876   StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#1877   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1878   StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#1879   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1880   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1881   StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#1882   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1883   StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#1884   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1885   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1886   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1887   ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#1888   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1889   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1890   StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#1891   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1892   StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#1893   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1894   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1895   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1896   ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#1897   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1898   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1899   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1900   ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#1901   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1902   _RawViewElement._updateChild (package:flutter/src/widgets/view.dart:481:16)
#1903   _RawViewElement.update (package:flutter/src/widgets/view.dart:568:5)
#1904   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1905   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1906   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1907   StatelessElement.update (package:flutter/src/widgets/framework.dart:5895:5)
#1908   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1909   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1910   StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#1911   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1912   StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#1913   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1914   RootElement._rebuild (package:flutter/src/widgets/binding.dart:1822:16)
#1915   RootElement.update (package:flutter/src/widgets/binding.dart:1800:5)
#1916   RootElement.performRebuild (package:flutter/src/widgets/binding.dart:1814:7)
#1917   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1918   BuildScope._tryRebuild (package:flutter/src/widgets/framework.dart:2750:15)
#1919   BuildScope._flushDirtyElements (package:flutter/src/widgets/framework.dart:2807:11)
#1920   BuildOwner.buildScope (package:flutter/src/widgets/framework.dart:3111:18)
#1921   AutomatedTestWidgetsFlutterBinding.drawFrame (package:flutter_test/src/binding.dart:2131:19)
#1922   RendererBinding._handlePersistentFrameCallback (package:flutter/src/rendering/binding.dart:495:5)
#1923   SchedulerBinding._invokeFrameCallback (package:flutter/src/scheduler/binding.dart:1430:15)
#1924   SchedulerBinding.handleDrawFrame (package:flutter/src/scheduler/binding.dart:1345:9)
#1925   AutomatedTestWidgetsFlutterBinding.pump.<anonymous closure> (package:flutter_test/src/binding.dart:1960:9)
#1928   TestAsyncUtils.guard (package:flutter_test/src/test_async_utils.dart:74:41)
#1929   AutomatedTestWidgetsFlutterBinding.pump (package:flutter_test/src/binding.dart:1949:27)
#1930   WidgetTester.pumpWidget.<anonymous closure> (package:flutter_test/src/widget_tester.dart:598:22)
#1933   TestAsyncUtils.guard (package:flutter_test/src/test_async_utils.dart:74:41)
#1934   WidgetTester.pumpWidget (package:flutter_test/src/widget_tester.dart:595:27)
#1935   main.<anonymous closure> (file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart:9:18)
#1936   testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:29)
#1938   testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:189:25)
#1939   TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1682:19)
#1941   TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1671:5)
#1944   TestWidgetsFlutterBinding._runTest (package:flutter_test/src/binding.dart:1656:10)
#1945   AutomatedTestWidgetsFlutterBinding.runTest.<anonymous closure> (package:flutter_test/src/binding.dart:2189:24)
#1946   FakeAsync.run.<anonymous closure>.<anonymous closure> (package:fake_async/fake_async.dart:182:47)
#1951   withClock (package:clock/src/default.dart:52:10)
#1952   FakeAsync.run.<anonymous closure> (package:fake_async/fake_async.dart:182:15)
#1957   FakeAsync.run (package:fake_async/fake_async.dart:181:52)
#1958   AutomatedTestWidgetsFlutterBinding.runTest (package:flutter_test/src/binding.dart:2186:15)
#1959   testWidgets.<anonymous closure> (package:flutter_test/src/widget_tester.dart:184:24)
#1960   Declarer.test.<anonymous closure>.<anonymous closure> (package:test_api/src/backend/declarer.dart:253:25)
#1962   Declarer.test.<anonymous closure>.<anonymous closure> (package:test_api/src/backend/declarer.dart:252:15)
#1967   Declarer.test.<anonymous closure> (package:test_api/src/backend/declarer.dart:250:17)
#1968   Invoker._waitForOutstandingCallbacks.<anonymous closure> (package:test_api/src/backend/invoker.dart:318:17)
#1973   Invoker._waitForOutstandingCallbacks (package:test_api/src/backend/invoker.dart:314:5)
#1974   Invoker._onRun.<anonymous closure>.<anonymous closure>.<anonymous closure> (package:test_api/src/backend/invoker.dart:457:21)
#1976   Invoker._onRun.<anonymous closure>.<anonymous closure>.<anonymous closure> (package:test_api/src/backend/invoker.dart:455:15)
#1981   Invoker._onRun.<anonymous closure>.<anonymous closure> (package:test_api/src/backend/invoker.dart:445:11)
#1982   Invoker._guardIfGuarded (package:test_api/src/backend/invoker.dart:500:15)
#1983   Invoker._onRun.<anonymous closure> (package:test_api/src/backend/invoker.dart:444:9)
#1990   Invoker._onRun (package:test_api/src/backend/invoker.dart:442:11)
#1991   LiveTestController.run (package:test_api/src/backend/live_test_controller.dart:161:11)
#1992   RemoteListener._runLiveTest.<anonymous closure> (package:test_api/src/backend/remote_listener.dart:323:16)
#1997   RemoteListener._runLiveTest (package:test_api/src/backend/remote_listener.dart:322:5)
#1998   RemoteListener._serializeTest.<anonymous closure> (package:test_api/src/backend/remote_listener.dart:263:7)
#2016   _GuaranteeSink.add (package:stream_channel/src/guarantee_channel.dart:125:12)
#2017   new _MultiChannel.<anonymous closure> (package:stream_channel/src/multi_channel.dart:159:31)
#2019   CastStreamSubscription._onData (dart:_internal/async_cast.dart:95:11)
#2045   new _WebSocketImpl._fromSocket.<anonymous closure> (dart:_http/websocket_impl.dart:1252:27)
#2051   _WebSocketProtocolTransformer._messageFrameEnd (dart:_http/websocket_impl.dart:348:23)
#2052   _WebSocketProtocolTransformer.add (dart:_http/websocket_impl.dart:238:46)
#2060   _Socket._onData (dart:io-patch/socket_patch.dart:2874:41)
#2067   new _RawSocket.<anonymous closure> (dart:io-patch/socket_patch.dart:2312:31)
#2068   _NativeSocket.issueReadEvent.issue (dart:io-patch/socket_patch.dart:1647:14)
(elided 108 frames from dart:async and package:stack_trace)

════════════════════════════════════════════════════════════════════════════════════════════════════
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following TestFailure was thrown running a test:
Expected: exactly one matching candidate
  Actual: _TextContainingWidgetFinder:<Found 0 widgets with text containing Parameters will appear
here: []>
   Which: means none were found but one was expected

When the exception was thrown, this was the stack:
#4      main.<anonymous closure> (file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart:20:5)
<asynchronous suspension>
#5      testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:15)
<asynchronous suspension>
#6      TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1682:5)
<asynchronous suspension>
<asynchronous suspension>
(elided one frame from package:stack_trace)

This was caught by the test expectation on the following line:
  file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart line 20
The test description was:
  ParameterExplorer shows placeholder when no numeric values in spec
════════════════════════════════════════════════════════════════════════════════════════════════════
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following message was thrown:
Multiple exceptions (2) were detected during the running of the current test, and at least one was
unexpected.
════════════════════════════════════════════════════════════════════════════════════════════════════
00:06 +56 -3: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart: ParameterExplorer shows placeholder when no numeric values in spec [E]
  Test failed. See exception logs above.
  The test description was: ParameterExplorer shows placeholder when no numeric values in spec
  
00:06 +56 -3: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart: ParameterExplorer shows sliders for numeric patterns in spec
══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════════════════════════════════════════════
The following LateError was thrown building ParameterExplorer(dirty, dependencies:
[UncontrolledProviderScope], state: _ParameterExplorerState#3cccc):
LateInitializationError: Field '_prefs@304450276' has not been initialized.

The relevant error-causing widget was:
  ParameterExplorer
  ParameterExplorer:file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart:37:32

When the exception was thrown, this was the stack:
#1      _ProviderStateSubscription.read (package:riverpod/src/framework/provider_base.dart:181:28)
#2      ConsumerStatefulElement.watch (package:flutter_riverpod/src/consumer.dart:568:8)
#3      _ParameterExplorerState.build (package:neurocnl_studio/widgets/parameter_explorer.dart:44:22)
#4      StatefulElement.build (package:flutter/src/widgets/framework.dart:5931:27)
#5      ConsumerStatefulElement.build (package:flutter_riverpod/src/consumer.dart:539:20)
#6      ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5817:15)
#7      StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#8      Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#9      ComponentElement._firstBuild (package:flutter/src/widgets/framework.dart:5799:5)
#10     StatefulElement._firstBuild (package:flutter/src/widgets/framework.dart:5973:11)
#11     ComponentElement.mount (package:flutter/src/widgets/framework.dart:5793:5)
...     Normal element mounting (25 frames)
#36     Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#37     MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:7264:36)
#38     MultiChildRenderObjectElement.mount (package:flutter/src/widgets/framework.dart:7279:32)
...     Normal element mounting (364 frames)
#402    Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#403    MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:7264:36)
#404    MultiChildRenderObjectElement.mount (package:flutter/src/widgets/framework.dart:7279:32)
...     Normal element mounting (473 frames)
#877    _UncontrolledProviderScopeElement.mount (package:flutter_riverpod/src/framework.dart:315:11)
...     Normal element mounting (9 frames)
#886    Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#887    Element.updateChild (package:flutter/src/widgets/framework.dart:4053:20)
#888    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#889    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#890    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#891    _InheritedNotifierElement.update (package:flutter/src/widgets/inherited_notifier.dart:108:11)
#892    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#893    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#894    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#895    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#896    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#897    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#898    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#899    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#900    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#901    _InheritedNotifierElement.update (package:flutter/src/widgets/inherited_notifier.dart:108:11)
#902    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#903    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#904    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#905    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#906    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#907    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#908    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#909    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#910    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#911    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#912    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#913    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#914    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#915    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#916    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#917    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#918    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#919    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#920    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#921    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#922    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#923    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#924    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#925    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#926    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#927    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#928    ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#929    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#930    _RawViewElement._updateChild (package:flutter/src/widgets/view.dart:481:16)
#931    _RawViewElement.update (package:flutter/src/widgets/view.dart:568:5)
#932    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#933    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#934    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#935    StatelessElement.update (package:flutter/src/widgets/framework.dart:5895:5)
#936    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#937    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#938    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#939    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#940    StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#941    Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#942    RootElement._rebuild (package:flutter/src/widgets/binding.dart:1822:16)
#943    RootElement.update (package:flutter/src/widgets/binding.dart:1800:5)
#944    RootElement.performRebuild (package:flutter/src/widgets/binding.dart:1814:7)
#945    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#946    BuildScope._tryRebuild (package:flutter/src/widgets/framework.dart:2750:15)
#947    BuildScope._flushDirtyElements (package:flutter/src/widgets/framework.dart:2807:11)
#948    BuildOwner.buildScope (package:flutter/src/widgets/framework.dart:3111:18)
#949    AutomatedTestWidgetsFlutterBinding.drawFrame (package:flutter_test/src/binding.dart:2131:19)
#950    RendererBinding._handlePersistentFrameCallback (package:flutter/src/rendering/binding.dart:495:5)
#951    SchedulerBinding._invokeFrameCallback (package:flutter/src/scheduler/binding.dart:1430:15)
#952    SchedulerBinding.handleDrawFrame (package:flutter/src/scheduler/binding.dart:1345:9)
#953    AutomatedTestWidgetsFlutterBinding.pump.<anonymous closure> (package:flutter_test/src/binding.dart:1960:9)
#956    TestAsyncUtils.guard (package:flutter_test/src/test_async_utils.dart:74:41)
#957    AutomatedTestWidgetsFlutterBinding.pump (package:flutter_test/src/binding.dart:1949:27)
#958    WidgetTester.pumpWidget.<anonymous closure> (package:flutter_test/src/widget_tester.dart:598:22)
#961    TestAsyncUtils.guard (package:flutter_test/src/test_async_utils.dart:74:41)
#962    WidgetTester.pumpWidget (package:flutter_test/src/widget_tester.dart:595:27)
#963    main.<anonymous closure> (file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart:31:18)
#964    testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:29)
#965    TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1682:5)
#967    ServerConfigService._prefs (package:neurocnl_studio/services/server_config_service.dart:0:0)
#968    ServerConfigService.getString (package:neurocnl_studio/services/server_config_service.dart:39:43)
#969    new SpecTextNotifier (package:neurocnl_studio/providers/spec_provider.dart:15:50)
#970    main.<anonymous closure>.<anonymous closure> (file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart:34:50)
#971    ProviderContainer.listen (package:riverpod/src/framework/container.dart:280:21)
#972    ConsumerStatefulElement.watch.<anonymous closure> (package:flutter_riverpod/src/consumer.dart:564:25)
#973    _LinkedHashMapMixin.putIfAbsent (dart:_compact_hash:675:23)
#974    ConsumerStatefulElement.watch (package:flutter_riverpod/src/consumer.dart:557:26)
#975    _ParameterExplorerState.build (package:neurocnl_studio/widgets/parameter_explorer.dart:44:22)
#976    StatefulElement.build (package:flutter/src/widgets/framework.dart:5931:27)
#977    ConsumerStatefulElement.build (package:flutter_riverpod/src/consumer.dart:539:20)
#978    ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5817:15)
#979    StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#980    Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#981    ComponentElement._firstBuild (package:flutter/src/widgets/framework.dart:5799:5)
#982    StatefulElement._firstBuild (package:flutter/src/widgets/framework.dart:5973:11)
#983    ComponentElement.mount (package:flutter/src/widgets/framework.dart:5793:5)
...     Normal element mounting (25 frames)
#1008   Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#1009   MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:7264:36)
#1010   MultiChildRenderObjectElement.mount (package:flutter/src/widgets/framework.dart:7279:32)
...     Normal element mounting (364 frames)
#1374   Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#1375   MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:7264:36)
#1376   MultiChildRenderObjectElement.mount (package:flutter/src/widgets/framework.dart:7279:32)
...     Normal element mounting (473 frames)
#1849   _UncontrolledProviderScopeElement.mount (package:flutter_riverpod/src/framework.dart:315:11)
...     Normal element mounting (9 frames)
#1858   Element.inflateWidget (package:flutter/src/widgets/framework.dart:4587:20)
#1859   Element.updateChild (package:flutter/src/widgets/framework.dart:4053:20)
#1860   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1861   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1862   ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#1863   _InheritedNotifierElement.update (package:flutter/src/widgets/inherited_notifier.dart:108:11)
#1864   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1865   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1866   StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#1867   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1868   StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#1869   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1870   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1871   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1872   ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#1873   _InheritedNotifierElement.update (package:flutter/src/widgets/inherited_notifier.dart:108:11)
#1874   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1875   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1876   StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#1877   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1878   StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#1879   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1880   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1881   StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#1882   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1883   StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#1884   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1885   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1886   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1887   ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#1888   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1889   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1890   StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#1891   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1892   StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#1893   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1894   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1895   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1896   ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#1897   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1898   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1899   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1900   ProxyElement.update (package:flutter/src/widgets/framework.dart:6149:5)
#1901   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1902   _RawViewElement._updateChild (package:flutter/src/widgets/view.dart:481:16)
#1903   _RawViewElement.update (package:flutter/src/widgets/view.dart:568:5)
#1904   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1905   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1906   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1907   StatelessElement.update (package:flutter/src/widgets/framework.dart:5895:5)
#1908   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1909   ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5841:16)
#1910   StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5982:11)
#1911   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1912   StatefulElement.update (package:flutter/src/widgets/framework.dart:6007:5)
#1913   Element.updateChild (package:flutter/src/widgets/framework.dart:4037:15)
#1914   RootElement._rebuild (package:flutter/src/widgets/binding.dart:1822:16)
#1915   RootElement.update (package:flutter/src/widgets/binding.dart:1800:5)
#1916   RootElement.performRebuild (package:flutter/src/widgets/binding.dart:1814:7)
#1917   Element.rebuild (package:flutter/src/widgets/framework.dart:5529:7)
#1918   BuildScope._tryRebuild (package:flutter/src/widgets/framework.dart:2750:15)
#1919   BuildScope._flushDirtyElements (package:flutter/src/widgets/framework.dart:2807:11)
#1920   BuildOwner.buildScope (package:flutter/src/widgets/framework.dart:3111:18)
#1921   AutomatedTestWidgetsFlutterBinding.drawFrame (package:flutter_test/src/binding.dart:2131:19)
#1922   RendererBinding._handlePersistentFrameCallback (package:flutter/src/rendering/binding.dart:495:5)
#1923   SchedulerBinding._invokeFrameCallback (package:flutter/src/scheduler/binding.dart:1430:15)
#1924   SchedulerBinding.handleDrawFrame (package:flutter/src/scheduler/binding.dart:1345:9)
#1925   AutomatedTestWidgetsFlutterBinding.pump.<anonymous closure> (package:flutter_test/src/binding.dart:1960:9)
#1928   TestAsyncUtils.guard (package:flutter_test/src/test_async_utils.dart:74:41)
#1929   AutomatedTestWidgetsFlutterBinding.pump (package:flutter_test/src/binding.dart:1949:27)
#1930   WidgetTester.pumpWidget.<anonymous closure> (package:flutter_test/src/widget_tester.dart:598:22)
#1933   TestAsyncUtils.guard (package:flutter_test/src/test_async_utils.dart:74:41)
#1934   WidgetTester.pumpWidget (package:flutter_test/src/widget_tester.dart:595:27)
#1935   main.<anonymous closure> (file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart:31:18)
#1936   testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:29)
#1938   testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:189:25)
#1939   TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1682:19)
#1941   TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1671:5)
#1944   TestWidgetsFlutterBinding._runTest (package:flutter_test/src/binding.dart:1656:10)
#1945   AutomatedTestWidgetsFlutterBinding.runTest.<anonymous closure> (package:flutter_test/src/binding.dart:2189:24)
#1946   FakeAsync.run.<anonymous closure>.<anonymous closure> (package:fake_async/fake_async.dart:182:47)
#1951   withClock (package:clock/src/default.dart:52:10)
#1952   FakeAsync.run.<anonymous closure> (package:fake_async/fake_async.dart:182:15)
#1957   FakeAsync.run (package:fake_async/fake_async.dart:181:52)
#1958   AutomatedTestWidgetsFlutterBinding.runTest (package:flutter_test/src/binding.dart:2186:15)
#1959   testWidgets.<anonymous closure> (package:flutter_test/src/widget_tester.dart:184:24)
#1960   Declarer.test.<anonymous closure>.<anonymous closure> (package:test_api/src/backend/declarer.dart:253:25)
#1962   Declarer.test.<anonymous closure>.<anonymous closure> (package:test_api/src/backend/declarer.dart:252:15)
#1967   Declarer.test.<anonymous closure> (package:test_api/src/backend/declarer.dart:250:17)
#1968   Invoker._waitForOutstandingCallbacks.<anonymous closure> (package:test_api/src/backend/invoker.dart:318:17)
#1973   Invoker._waitForOutstandingCallbacks (package:test_api/src/backend/invoker.dart:314:5)
#1974   Invoker._onRun.<anonymous closure>.<anonymous closure>.<anonymous closure> (package:test_api/src/backend/invoker.dart:457:21)
#1976   Invoker._onRun.<anonymous closure>.<anonymous closure>.<anonymous closure> (package:test_api/src/backend/invoker.dart:455:15)
#1981   Invoker._onRun.<anonymous closure>.<anonymous closure> (package:test_api/src/backend/invoker.dart:445:11)
#1982   Invoker._guardIfGuarded (package:test_api/src/backend/invoker.dart:500:15)
#1983   Invoker._onRun.<anonymous closure> (package:test_api/src/backend/invoker.dart:444:9)
#1990   Invoker._onRun (package:test_api/src/backend/invoker.dart:442:11)
#1991   LiveTestController.run (package:test_api/src/backend/live_test_controller.dart:161:11)
#1992   RemoteListener._runLiveTest.<anonymous closure> (package:test_api/src/backend/remote_listener.dart:323:16)
#1997   RemoteListener._runLiveTest (package:test_api/src/backend/remote_listener.dart:322:5)
#1998   RemoteListener._serializeTest.<anonymous closure> (package:test_api/src/backend/remote_listener.dart:263:7)
#2016   _GuaranteeSink.add (package:stream_channel/src/guarantee_channel.dart:125:12)
#2017   new _MultiChannel.<anonymous closure> (package:stream_channel/src/multi_channel.dart:159:31)
#2019   CastStreamSubscription._onData (dart:_internal/async_cast.dart:95:11)
#2045   new _WebSocketImpl._fromSocket.<anonymous closure> (dart:_http/websocket_impl.dart:1252:27)
#2051   _WebSocketProtocolTransformer._messageFrameEnd (dart:_http/websocket_impl.dart:348:23)
#2052   _WebSocketProtocolTransformer.add (dart:_http/websocket_impl.dart:238:46)
#2060   _Socket._onData (dart:io-patch/socket_patch.dart:2874:41)
#2067   new _RawSocket.<anonymous closure> (dart:io-patch/socket_patch.dart:2312:31)
#2068   _NativeSocket.issueReadEvent.issue (dart:io-patch/socket_patch.dart:1647:14)
(elided 108 frames from dart:async and package:stack_trace)

════════════════════════════════════════════════════════════════════════════════════════════════════
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following TestFailure was thrown running a test:
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Threshold": []>
   Which: means none were found but one was expected

When the exception was thrown, this was the stack:
#4      main.<anonymous closure> (file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart:46:5)
<asynchronous suspension>
#5      testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:15)
<asynchronous suspension>
#6      TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1682:5)
<asynchronous suspension>
<asynchronous suspension>
(elided one frame from package:stack_trace)

This was caught by the test expectation on the following line:
  file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart line 46
The test description was:
  ParameterExplorer shows sliders for numeric patterns in spec
════════════════════════════════════════════════════════════════════════════════════════════════════
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following message was thrown:
Multiple exceptions (2) were detected during the running of the current test, and at least one was
unexpected.
════════════════════════════════════════════════════════════════════════════════════════════════════
00:06 +56 -4: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/test/widgets/parameter_explorer_test.dart: ParameterExplorer shows sliders for numeric patterns in spec [E]
  Test failed. See exception logs above.
  The test description was: ParameterExplorer shows sliders for numeric patterns in spec
  
00:06 +56 -4: Some tests failed.
```

