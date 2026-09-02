import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

/// Reusable widget with a serial port dropdown and refresh button.
class SerialPortSelector extends StatelessWidget {
  final List<String> availablePorts;
  final String? selectedPort;
  final bool isRefreshing;
  final ValueChanged<String?> onPortChanged;
  final VoidCallback onRefresh;

  const SerialPortSelector({
    super.key,
    required this.availablePorts,
    required this.selectedPort,
    required this.isRefreshing,
    required this.onPortChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Serial Port',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: availablePorts.contains(selectedPort)
                    ? selectedPort
                    : null,
                hint: const Text('Select a port'),
                isExpanded: true,
                isDense: true,
                items: availablePorts
                    .map(
                      (port) => DropdownMenuItem(
                        value: port,
                        child: Text(port, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: onPortChanged,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        isRefreshing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Tooltip(
                message: 'Refresh ports',
                child: ZetaIconButton.text(
                  icon: ZetaIcons.refresh,
                  semanticLabel: 'Refresh ports',
                  onPressed: onRefresh,
                ),
              ),
      ],
    );
  }
}
