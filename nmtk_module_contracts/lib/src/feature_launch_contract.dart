import 'dart:collection';

import 'package:flutter/widgets.dart';

/// The stable, lowercase identity used by root-hosted Flutter features.
enum NmtkModuleId {
  neurocnl('neurocnl'),
  neurochip('neurochip'),
  neurobench('neurobench'),
  neurosense('neurosense'),
  neurohub('neurohub'),
  lavaBackend('lava_backend'),
  jupyter('jupyter');

  const NmtkModuleId(this.value);

  final String value;

  static const Map<String, NmtkModuleId> _legacyValues = <String, NmtkModuleId>{
    'Neurochip': NmtkModuleId.neurochip,
    'Neurobench': NmtkModuleId.neurobench,
    'Neurosense': NmtkModuleId.neurosense,
    'Neurohub': NmtkModuleId.neurohub,
  };

  /// Converts canonical and legacy launcher values at the root boundary.
  static NmtkModuleId fromExternal(String value) {
    final normalized = value.trim();
    for (final moduleId in values) {
      if (moduleId.value == normalized) return moduleId;
    }
    final legacyValue = _legacyValues[normalized];
    if (legacyValue != null) return legacyValue;
    throw ArgumentError.value(
      value,
      'value',
      'Unknown NMTK module ID. Use a canonical lowercase module ID.',
    );
  }
}

@immutable
class NmtkFeatureAuthentication {
  const NmtkFeatureAuthentication({this.adminToken = ''});

  /// Root-owned credential for the selected backend tunnel.
  final String adminToken;
}

@immutable
class NmtkFeatureNavigationRequest {
  NmtkFeatureNavigationRequest({
    required this.moduleId,
    this.deepLink,
    Map<String, Object?> restorationState = const <String, Object?>{},
  }) : restorationState = UnmodifiableMapView(
         Map<String, Object?>.from(restorationState),
       );

  final NmtkModuleId moduleId;
  final String? deepLink;
  final Map<String, Object?> restorationState;
}

typedef NmtkFeatureNavigator =
    Future<bool> Function(NmtkFeatureNavigationRequest request);

enum NmtkFeatureErrorKind { connection, authentication, navigation, unexpected }

@immutable
class NmtkFeatureErrorEvent {
  const NmtkFeatureErrorEvent({
    required this.moduleId,
    required this.kind,
    required this.message,
  });

  final NmtkModuleId moduleId;
  final NmtkFeatureErrorKind kind;
  final String message;
}

typedef NmtkFeatureErrorReporter =
    Future<void> Function(NmtkFeatureErrorEvent event);

@immutable
class NmtkFeatureLaunchContext {
  NmtkFeatureLaunchContext({
    required this.moduleId,
    required this.backendUri,
    required this.onNavigate,
    required this.onReportError,
    required this.onEditServer,
    this.authentication = const NmtkFeatureAuthentication(),
    this.initialLocation = '/',
    Map<String, Object?> restorationState = const <String, Object?>{},
    this.workspaceHeaderAction,
  }) : restorationState = UnmodifiableMapView(
         Map<String, Object?>.from(restorationState),
       );

  final NmtkModuleId moduleId;
  final Uri backendUri;
  final NmtkFeatureAuthentication authentication;
  final String initialLocation;
  final Map<String, Object?> restorationState;
  final NmtkFeatureNavigator onNavigate;
  final NmtkFeatureErrorReporter onReportError;
  final Future<void> Function() onEditServer;
  final Widget? workspaceHeaderAction;
}
