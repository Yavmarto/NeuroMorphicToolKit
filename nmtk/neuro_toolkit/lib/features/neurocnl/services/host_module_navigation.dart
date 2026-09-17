import 'package:flutter/widgets.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

bool hasHostedModuleNavigator(BuildContext context) {
  return NmtkHostNavigationScope.maybeNavigatorOf(context) != null;
}

Future<bool> openModuleInHost(
  BuildContext context, {
  required String moduleId,
  String? deepLink,
  Map<String, Object?> restorationState = const <String, Object?>{},
}) {
  return NmtkHostNavigationScope.openModule(
    context,
    NmtkFeatureNavigationRequest(
      moduleId: NmtkModuleId.fromExternal(moduleId),
      deepLink: deepLink,
      restorationState: restorationState,
    ),
  );
}
