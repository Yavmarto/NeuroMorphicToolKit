export 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_app.dart';
export 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_deep_link.dart';
export 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_restoration_snapshot.dart';
export 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_route_state.dart';
export 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_workspace_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_app.dart';

/// Embeds [NeuroSimApp] inside a fresh [ProviderScope] so each embedding
/// gets isolated canvas/project/simulation state, pre-initialised for the
/// given [initialLocation] and [initialSnapshot].
///
/// These are passed straight through as constructor parameters rather than
/// via provider overrides: Riverpod only honors `ProviderScope.overrides`
/// for providers that declare scoped `dependencies`, so an override set on
/// a *nested* ProviderScope (as this one is, sitting under the host app's
/// root ProviderScope) is silently ignored for plain providers.
class NeuroSimShellAdapter extends StatelessWidget {
  const NeuroSimShellAdapter({
    super.key,
    this.initialLocation = '/',
    this.initialSnapshot,
  });

  final String initialLocation;
  final String? initialSnapshot;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: NeuroSimApp(
        showShellChrome: false,
        initialLocation: initialLocation,
        initialSnapshot: initialSnapshot,
      ),
    );
  }
}
