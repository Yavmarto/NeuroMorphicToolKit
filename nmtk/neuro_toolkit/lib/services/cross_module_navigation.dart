import 'package:neuro_toolkit/models/module.dart';

class CrossModuleNavigation {
  const CrossModuleNavigation({
    required this.targetModule,
    required this.targetUri,
  });

  final Module targetModule;
  final Uri targetUri;
}

String launcherDeepLinkFromUri(Uri targetUri) {
  final buffer = StringBuffer(targetUri.path.isEmpty ? '/' : targetUri.path);
  if (targetUri.hasQuery) {
    buffer
      ..write('?')
      ..write(targetUri.query);
  }
  if (targetUri.hasFragment) {
    buffer
      ..write('#')
      ..write(targetUri.fragment);
  }
  return buffer.toString();
}

CrossModuleNavigation? resolveCrossModuleNavigation({
  required Uri targetUri,
  required List<Module> modules,
  required String currentModuleId,
}) {
  if (!(targetUri.scheme == 'http' || targetUri.scheme == 'https')) {
    return null;
  }

  Module? matchingModule;
  for (final module in modules) {
    if (module.id != currentModuleId &&
        module.effectivePort != null &&
        module.effectivePort == targetUri.port) {
      matchingModule = module;
      break;
    }
  }

  if (matchingModule == null) {
    return null;
  }

  return CrossModuleNavigation(
    targetModule: matchingModule,
    targetUri: targetUri,
  );
}
