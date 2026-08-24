part of 'main.dart';

/// Compatibility wrapper retained for existing launch and widget-test entry
/// points. The application itself has one MaterialApp and provider graph.
class LauncherBootstrapHost extends StatelessWidget {
  const LauncherBootstrapHost({super.key});

  @override
  Widget build(BuildContext context) => const NeuroToolkitApp();
}
