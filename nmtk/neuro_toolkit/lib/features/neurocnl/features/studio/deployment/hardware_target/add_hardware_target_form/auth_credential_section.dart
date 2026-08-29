import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';

class AuthCredentialSection extends StatelessWidget {
  const AuthCredentialSection({
    super.key,
    required this.authMode,
    required this.onAuthModeChanged,
    required this.passwordController,
    required this.sshKeyPathController,
    this.hasSavedPassword = false,
  });

  final String authMode;
  final ValueChanged<String> onAuthModeChanged;
  final TextEditingController passwordController;
  final TextEditingController sshKeyPathController;

  /// Whether the backend already has a saved password for this entry. When
  /// true and the user leaves the field masked, no password is transmitted.
  final bool hasSavedPassword;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'Auth method',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 12),
            ZetaSegmentedControl<String>(
              selected: authMode,
              onChanged: onAuthModeChanged,
              segments: const [
                ZetaButtonSegment<String>(
                  value: 'password',
                  child: Text('Password'),
                ),
                ZetaButtonSegment<String>(
                  value: 'ssh_key',
                  child: Text('SSH Key'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (authMode == 'ssh_key')
          StudioFormField(
            controller: sshKeyPathController,
            label: 'SSH key path',
            helperText:
                'Absolute path to the private key file on this machine.',
          )
        else
          StudioFormField(
            controller: passwordController,
            label: 'SSH password',
            obscureText: true,
            helperText: hasSavedPassword
                ? 'Password saved. Leave unchanged to keep it.'
                : null,
          ),
      ],
    );
  }
}
