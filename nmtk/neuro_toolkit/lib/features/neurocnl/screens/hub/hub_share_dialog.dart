import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/hub_preview.dart';

class HubShareDialog extends StatefulWidget {
  const HubShareDialog({
    super.key,
    required this.benchmark,
    required this.onSave,
  });

  final bool benchmark;
  final ValueChanged<HubVisibility> onSave;

  @override
  State<HubShareDialog> createState() => _HubShareDialogState();
}

class _HubShareDialogState extends State<HubShareDialog> {
  HubVisibility _visibility = HubVisibility.public;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.benchmark ? 'Share benchmark result' : 'Share workspace',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.benchmark
              ? 'Publish this result with its run context.'
              : 'Publish this workspace with its pipeline context.',
        ),
        const SizedBox(height: 16),
        ZetaSegmentedControl<HubVisibility>(
          semanticLabel: 'Item visibility',
          selected: _visibility,
          segments: const <ZetaButtonSegment<HubVisibility>>[
            ZetaButtonSegment(
              value: HubVisibility.public,
              child: Text('Public'),
            ),
            ZetaButtonSegment(
              value: HubVisibility.private,
              child: Text('Private'),
            ),
          ],
          onChanged: (value) => setState(() => _visibility = value),
        ),
        const SizedBox(height: 12),
        Text(
          _visibility == HubVisibility.public
              ? 'This item appears in Explore.'
              : 'This item appears only in My Profile.',
        ),
      ],
    ),
    actions: <Widget>[
      NmtkOutlinedButton(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(),
      ),
      NmtkPrimaryButton(
        label: 'Add to preview',
        icon: ZetaIcons.upload,
        onPressed: () {
          widget.onSave(_visibility);
          Navigator.of(context).pop();
        },
      ),
    ],
  );
}
