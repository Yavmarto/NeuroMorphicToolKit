import 'package:flutter/widgets.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';

/// Selects the rendered workflow result view.

class ResultsViewSwitch extends StatelessWidget {
  const ResultsViewSwitch({
    super.key,
    required this.view,
    required this.onChanged,
  });

  final StudioResultView view;
  final ValueChanged<StudioResultView> onChanged;

  @override
  Widget build(BuildContext context) {
    return ZetaSegmentedControl<StudioResultView>(
      semanticLabel: 'Result view',
      selected: view,
      onChanged: onChanged,
      segments: [
        for (final value in StudioResultView.values)
          ZetaButtonSegment<StudioResultView>(
            value: value,
            child: Text(value.label),
          ),
      ],
    );
  }
}
