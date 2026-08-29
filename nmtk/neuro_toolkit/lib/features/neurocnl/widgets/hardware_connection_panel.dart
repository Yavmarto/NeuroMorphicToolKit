import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/hardware_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/serial_port_selector.dart';

/// Displays the port selector, baud rate picker, connect/disconnect button,
/// connection status badge, and error text.
///
/// Accepts callbacks so the parent [ConsumerStatefulWidget] retains ownership
/// of [_selectedPort] and [_baudRate] — the only local UI-only state in the
/// hardware screen.
class HardwareConnectionPanel extends StatelessWidget {
  const HardwareConnectionPanel({
    super.key,
    required this.state,
    required this.selectedPort,
    required this.baudRate,
    required this.onPortChanged,
    required this.onBaudRateChanged,
    required this.onRefresh,
    required this.onConnect,
    required this.onDisconnect,
  });

  final HardwareState state;
  final String? selectedPort;
  final int baudRate;
  final ValueChanged<String?> onPortChanged;
  final ValueChanged<int> onBaudRateChanged;
  final VoidCallback onRefresh;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  static const _baudRates = <int>[9600, 115200, 230400];

  static final List<DropdownMenuItem<int>> _baudRateItems = _baudRates
      .map(
        (rate) =>
            DropdownMenuItem<int>(value: rate, child: Text(rate.toString())),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    // zeta-card-reduction Task 10: NeurocnlSectionCard → NmtkSection.
    return NmtkSection(
      title: 'Local Serial Check',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SerialPortSelector(
            availablePorts: state.availablePorts,
            selectedPort: selectedPort,
            isRefreshing: state.isRefreshing,
            onPortChanged: onPortChanged,
            onRefresh: onRefresh,
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Baud Rate',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: baudRate,
                isExpanded: true,
                isDense: true,
                items: _baudRateItems,
                onChanged: (val) {
                  if (val != null) onBaudRateChanged(val);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ConnectButton(
                  state: state,
                  selectedPort: selectedPort,
                  onConnect: onConnect,
                  onDisconnect: onDisconnect,
                ),
              ),
              const SizedBox(width: 16),
              _StatusBadge(state: state),
            ],
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 8),
            _ErrorText(message: state.errorMessage!),
          ],
        ],
      ),
    );
  }
}

// ── Private sub-widgets ────────────────────────────────────────────────────

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.state,
    required this.selectedPort,
    required this.onConnect,
    required this.onDisconnect,
  });

  final HardwareState state;
  final String? selectedPort;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    if (state.isConnected) {
      return ZetaButton.negative(
        onPressed: onDisconnect,
        leadingIcon: ZetaIcons.link,
        label: 'Disconnect',
      );
    }

    return ZetaButton.positive(
      onPressed: selectedPort == null ? null : onConnect,
      leadingIcon: ZetaIcons.link,
      label: 'Connect',
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});

  final HardwareState state;

  @override
  Widget build(BuildContext context) {
    final status = NmtkShellStatusSpec.fromReadinessState(
      state.isConnected
          ? NmtkShellReadinessState.ready
          : NmtkShellReadinessState.degraded,
      detailText: state.isConnected
          ? 'Connected to ${state.connectedPort}'
          : 'Disconnected',
    );
    return NmtkShellStatusBadge(status: status);
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Zeta.of(context).textStyles.bodyMedium.copyWith(
        color: NmtkShellTokens.of(context).errorColor,
      ),
    );
  }
}
