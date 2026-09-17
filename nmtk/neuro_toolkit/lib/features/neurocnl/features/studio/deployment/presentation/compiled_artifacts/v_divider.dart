import 'package:flutter/widgets.dart';

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';

/// Vertical divider used by the compiled artifact header.

class VDivider extends StatelessWidget {
  const VDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 16, color: AppTheme.border);
  }
}
