import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/screens/workbench_shell.dart';

/// Workbench desktop layout requires width above 1080 logical pixels.
void useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> pumpWorkbench(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> pumpWorkbenchShell(
  WidgetTester tester, {
  required ProviderContainer container,
  NeurobenchRouteState routeState = const NeurobenchRouteState(),
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: WorkbenchShellScreen(routeState: routeState)),
    ),
  );
  await pumpWorkbench(tester);
  await pumpWorkbench(tester);
}
