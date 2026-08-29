import 'package:flutter/widgets.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Standard status banner for a deployment workflow phase.

class StudioPhaseBanner extends StatelessWidget {
  const StudioPhaseBanner({super.key, required this.label, required this.tone});

  final String label;
  final NmtkTone tone;

  @override
  Widget build(BuildContext context) {
    return NmtkStatusBanner(title: label, tone: tone);
  }
}
