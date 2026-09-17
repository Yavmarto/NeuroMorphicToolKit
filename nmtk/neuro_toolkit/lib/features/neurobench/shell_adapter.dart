import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

import 'package:neuro_toolkit/features/neurobench/app.dart';
import 'package:neuro_toolkit/features/neurobench/providers/feature_launch_provider.dart';

class NeurobenchShellAdapter extends StatelessWidget {
  const NeurobenchShellAdapter({super.key, required this.launchContext});

  /// Root-owned launch inputs for this embedded feature surface.
  final NmtkFeatureLaunchContext launchContext;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        initialLocationProvider.overrideWithValue(
          launchContext.initialLocation,
        ),
        showShellChromeProvider.overrideWithValue(false),
        featureLaunchContextProvider.overrideWithValue(launchContext),
      ],
      child: const NeuroBenchWorkbenchSurface(),
    );
  }
}
