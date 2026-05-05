import 'package:flutter/foundation.dart';

typedef NmtkHostModuleNavigator =
    Future<bool> Function(NmtkHostNavigationRequest request);

@immutable
class NmtkHostNavigationRequest {
  const NmtkHostNavigationRequest({
    required this.moduleId,
    this.deepLink,
    this.restoreState = const <String, dynamic>{},
  });

  final String moduleId;
  final String? deepLink;
  final Map<String, dynamic> restoreState;
}
