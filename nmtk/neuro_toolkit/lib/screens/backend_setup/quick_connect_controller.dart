import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/screens/backend_setup/backend_setup_controller_host.dart';
import 'package:neuro_toolkit/screens/backend_setup/form_primitives.dart';

class QuickConnectController {
  QuickConnectController(this._host, {String initialHostText = ''})
    : quickConnectHost = TextEditingController(text: initialHostText);

  final BackendSetupControllerHost _host;
  final TextEditingController quickConnectHost;
  bool isQuickConnecting = false;
  String? quickConnectError;

  void dispose() {
    quickConnectHost.dispose();
  }

  Widget buildSection(NmtkShellTokens tokens) {
    final connectButton = ZetaButton(
      key: const Key('backend-setup-quick-connect'),
      onPressed: isQuickConnecting ? null : handleQuickConnect,
      label: isQuickConnecting ? 'Connecting…' : 'Connect',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Connect to server'),
        SizedBox(height: tokens.compactGap),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 560) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: buildTextField(quickConnectHost, 'Server IP'),
                  ),
                  SizedBox(width: tokens.compactGap),
                  connectButton,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildTextField(quickConnectHost, 'Server IP'),
                SizedBox(height: tokens.compactGap),
                connectButton,
              ],
            );
          },
        ),
        if (quickConnectError != null) ...[
          SizedBox(height: tokens.compactGap),
          NmtkStatusBanner(
            key: const Key('backend-setup-quick-connect-error'),
            title: 'Could not connect',
            content: Text(quickConnectError!),
            tone: NmtkTone.danger,
          ),
        ],
      ],
    );
  }

  Future<void> handleQuickConnect() async {
    final host = canonicalIpv4(quickConnectHost.text);
    if (host == null) {
      _host.rebuild(() {
        quickConnectError = 'Enter an IPv4 address, for example 192.168.2.34.';
      });
      return;
    }
    _host.rebuild(() {
      isQuickConnecting = true;
      quickConnectError = null;
    });
    try {
      final quickConnect = _host.onQuickConnect;
      String? error;
      if (quickConnect != null) {
        error = await quickConnect(host);
        if (_host.mounted && error == null) {
          _host.rebuild(() => _host.connectedHealthHost = host);
          _host.onQuickConnectSuccess?.call();
        }
      } else {
        final target = DeploymentTarget(
          id: 'quick-connect-$host',
          displayName: host,
          targetType: 'remote_host',
          mode: 'docker',
          authMode: 'none',
          backendPort: 9000,
          host: host,
        );
        await _host.onDeploymentReady?.call(target);
      }
      if (_host.mounted && error != null) {
        _host.rebuild(() => quickConnectError = error);
      }
    } on Object catch (error) {
      debugPrint('Quick connect failed: $error');
      if (_host.mounted) {
        _host.rebuild(() {
          quickConnectError =
              'The launcher could not be checked. Confirm the address and '
              'try again.';
        });
      }
    } finally {
      if (_host.mounted) _host.rebuild(() => isQuickConnecting = false);
    }
  }
}
