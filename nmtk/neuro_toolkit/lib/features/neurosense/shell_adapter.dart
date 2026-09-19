import 'package:flutter/material.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

import 'package:neuro_toolkit/features/neurosense/neurosense_monitor_surface.dart';

class NeurosenseShellAdapter extends StatelessWidget {
  const NeurosenseShellAdapter({super.key, required this.launchContext});

  final NmtkFeatureLaunchContext launchContext;

  @override
  Widget build(BuildContext context) {
    return const NeurosenseMonitorSurface();
  }
}
