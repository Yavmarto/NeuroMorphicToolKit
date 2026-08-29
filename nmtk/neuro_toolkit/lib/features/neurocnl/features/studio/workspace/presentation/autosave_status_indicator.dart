import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/providers/autosave_status_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';

class AutosaveStatusIndicator extends ConsumerWidget {
  const AutosaveStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(autosaveStatusProvider);
    return switch (status) {
      AutosaveStatus.saving => Tooltip(
        message: 'Saving…',
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: null,
            color: Zeta.of(context).colors.mainSubtle,
          ),
        ),
      ),
      AutosaveStatus.saved => Tooltip(
        message: 'All changes saved',
        child: Icon(
          ZetaIcons.check_circle_outline,
          size: 18,
          color: AppTheme.healthyColorOf(context),
        ),
      ),
    };
  }
}
