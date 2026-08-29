import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

class SetupHeaderActions extends StatelessWidget {
  const SetupHeaderActions({
    super.key,
    required this.onLoadFromHub,
    required this.onLoadFromDisk,
    required this.onLoadFromServer,
  });

  final VoidCallback onLoadFromHub;
  final VoidCallback onLoadFromDisk;
  final VoidCallback onLoadFromServer;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NmtkOutlinedButton(
          label: 'Load from hub',
          icon: ZetaIcons.cloud_download,
          onPressed: onLoadFromHub,
        ),
        const SizedBox(width: 8),
        NmtkOutlinedButton(
          label: 'Load from disc',
          icon: ZetaIcons.upload_file,
          onPressed: onLoadFromDisk,
        ),
        const SizedBox(width: 8),
        NmtkOutlinedButton(
          label: 'Load from server',
          icon: ZetaIcons.server,
          onPressed: onLoadFromServer,
        ),
      ],
    );
  }
}
