import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Frame-less ownership-boundary banner used inside Studio surfaces (Analysis,
/// Hardware) to communicate the handoff between Studio authoring and the
/// runtime modules (Neurochip, etc.).
///
/// zeta-card-reduction Task 10: replaced the `NeurocnlSectionCard`-based
/// rendering with [NmtkSection]. Both call sites in `analysis_screen.dart`
/// and `hardware_screen.dart` always passed the default neutral tone, so
/// the previous `tone` parameter has no remaining surface; if a future
/// caller needs a tone signal it should use [NmtkStatusBanner] alongside
/// the section, not a frame colour.
class NeurocnlOwnershipBoundaryCard extends StatelessWidget {
  const NeurocnlOwnershipBoundaryCard({
    super.key,
    required this.summary,
    this.details = const <String>[],
    this.actions,
  });

  final String summary;
  final List<String> details;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return NmtkSection(
      title: 'Ownership Boundary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary),
          for (final detail in details) ...[
            const SizedBox(height: 8),
            Text(detail),
          ],
          if (actions != null) ...[const SizedBox(height: 12), actions!],
        ],
      ),
    );
  }
}
