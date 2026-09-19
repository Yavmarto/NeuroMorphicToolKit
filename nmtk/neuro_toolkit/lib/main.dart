import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/features/neurocnl/neurocnl_studio.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/server_access_gate.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/src/features/app/presentation/launcher_app_host.dart';
import 'package:neuro_toolkit/src/features/app/presentation/command_provider.dart';

part 'launcher_bootstrap_host.dart';
part 'neuro_toolkit_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final analytics = AnalyticsService();
  await analytics.init();

  // Global error handlers for crash reporting
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    analytics.logCrash(details.exception, details.stack ?? StackTrace.empty);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    analytics.logCrash(error, stack);
    return true;
  };

  final container = ProviderContainer(
    overrides: [analyticsServiceProvider.overrideWithValue(analytics)],
    // Riverpod 3 retries any provider whose build() throws, up to 10 times
    // with backoff. Each retry disposes and rebuilds the element underneath
    // the widgets watching it, and a `ref.watch` landing in that window reads
    // an uninitialized provider and kills the frame (CEL-270). The launcher
    // does its own recovery — ModuleNotifier polls every 3s and the
    // "Could Not Load Workspace" panel has an explicit Retry — so the
    // implicit retry only adds churn and duplicate network calls.
    retry: (_, _) => null,
  );

  // Await the settings to be loaded from SharedPreferences asynchronously
  await container.read(settingsProvider.future);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const LauncherBootstrapHost(),
    ),
  );
}
