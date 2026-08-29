import 'package:flutter/widgets.dart';

import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/screens/workbench_shell.dart';

class BenchmarkScreen extends StatelessWidget {
  const BenchmarkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const WorkbenchShellScreen(
      routeState: NeurobenchRouteState(tab: NeurobenchWorkbenchTab.configure),
    );
  }
}
