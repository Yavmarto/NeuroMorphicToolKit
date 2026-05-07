import 'package:flutter/widgets.dart';
import 'package:neurocnl_studio/shell_adapter.dart';

class NeurochipShellAdapter extends StatelessWidget {
  const NeurochipShellAdapter({
    super.key,
    this.initialDeepLink,
    this.initialRestoreState,
  });

  final String? initialDeepLink;
  final Map<String, dynamic>? initialRestoreState;

  @override
  Widget build(BuildContext context) {
    return NeurocnlShellAdapter(
      initialLocation: normalizeNeurochipDeepLinkForStudio(initialDeepLink),
      initialRestoreState: initialRestoreState ?? const <String, Object?>{},
    );
  }
}

String normalizeNeurochipDeepLinkForStudio(String? rawDeepLink) {
  final raw = rawDeepLink?.trim();
  if (raw == null || raw.isEmpty) {
    return '/?panel=deploy';
  }

  final uri = Uri.parse(raw);
  final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
  final selectedTargetId =
      uri.queryParameters['selectedTargetId']?.trim().toLowerCase();
  final target = _normalizeTargetId(segment, selectedTargetId, uri);

  final nextQuery = <String, String>{
    ...uri.queryParameters,
    'panel': 'deploy',
  };
  if (target != null) {
    nextQuery['target'] = target;
  }

  return Uri(path: '/', queryParameters: nextQuery).toString();
}

String? _normalizeTargetId(
  String segment,
  String? selectedTargetId,
  Uri uri,
) {
  if (selectedTargetId != null && selectedTargetId.isNotEmpty) {
    if (selectedTargetId.startsWith('teensy')) {
      return 'teensy';
    }
    if (selectedTargetId.startsWith('pynq')) {
      return 'pynq';
    }
    if (selectedTargetId.startsWith('akida')) {
      return 'akida';
    }
  }

  return switch (segment.toLowerCase()) {
    'teensy' => 'teensy',
    'pynq' => 'pynq',
    'akida' => 'akida',
    _ when uri.queryParameters.containsKey('import_akida') => 'akida',
    _ when uri.queryParameters.containsKey('import_network_handoff') =>
      selectedTargetId,
    _ => null,
  };
}
