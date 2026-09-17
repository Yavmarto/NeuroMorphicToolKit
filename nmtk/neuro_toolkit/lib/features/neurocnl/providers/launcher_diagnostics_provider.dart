import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/launcher_diagnostics.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

final launcherDiagnosticsProvider =
    FutureProvider.autoDispose<LauncherDiagnostics>((ref) async {
      final client = ref.read(apiClientProvider);
      try {
        return await client.fetchLauncherDiagnostics();
      } catch (error) {
        return LauncherDiagnostics.unavailable(error.toString());
      }
    });
