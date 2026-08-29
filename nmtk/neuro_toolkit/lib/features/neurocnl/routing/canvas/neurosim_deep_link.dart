import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_route_state.dart';

class NeurosimModuleDeepLink {
  const NeurosimModuleDeepLink({
    this.version = 1,
    required this.target,
    this.entityId,
    this.context = const <String, String>{},
  });

  final int version;
  final String target;
  final String? entityId;
  final Map<String, String> context;

  static const String canvasTarget = 'project_canvas';
  static const String projectListTarget = 'project_list';
  static const String previewTarget = 'preview';
  static const String sweepTarget = 'sweep';
  static const String exportTarget = 'export';

  factory NeurosimModuleDeepLink.fromLocation(String location) {
    final uri = Uri.parse(location.isEmpty ? '/' : location);
    final segments = uri.pathSegments;

    if (segments.isEmpty || uri.path == '/' || uri.path == '/canvas') {
      return NeurosimModuleDeepLink(
        target: canvasTarget,
        context: uri.queryParameters,
      );
    }

    if (segments.length == 1 && segments[0] == 'projects') {
      return NeurosimModuleDeepLink(
        target: projectListTarget,
        entityId: uri.queryParameters['projectId'],
        context: uri.queryParameters,
      );
    }

    if (segments.length >= 2 && segments[0] == 'projects') {
      final projectId = segments[1];
      if (segments.length == 2) {
        return NeurosimModuleDeepLink(
          target: canvasTarget,
          entityId: projectId,
          context: uri.queryParameters,
        );
      }
      if (segments.length >= 3) {
        final leaf = segments[2];
        if (leaf == 'preview') {
          return NeurosimModuleDeepLink(
            target: previewTarget,
            entityId: projectId,
            context: uri.queryParameters,
          );
        }
        if (leaf == 'sweep') {
          return NeurosimModuleDeepLink(
            target: sweepTarget,
            entityId: projectId,
            context: uri.queryParameters,
          );
        }
        if (leaf == 'export') {
          return NeurosimModuleDeepLink(
            target: exportTarget,
            entityId: projectId,
            context: uri.queryParameters,
          );
        }
      }
    }

    return NeurosimModuleDeepLink(
      target: canvasTarget,
      context: uri.queryParameters,
    );
  }

  NeurosimRouteState toRouteState() {
    final showPreview =
        _parseBool(context['preview']) ?? target == previewTarget;
    final previewCurrentTime = double.tryParse(context['time'] ?? '') ?? 0.0;

    return NeurosimRouteState(
      target: switch (target) {
        projectListTarget => NeurosimRouteTarget.projectList,
        previewTarget => NeurosimRouteTarget.preview,
        sweepTarget => NeurosimRouteTarget.sweep,
        exportTarget => NeurosimRouteTarget.export,
        _ => NeurosimRouteTarget.canvas,
      },
      selectedProjectId: entityId,
      selectedNodeId: context['nodeId'],
      selectedEdgeId: context['edgeId'],
      showPreview: showPreview,
      previewCurrentTime: previewCurrentTime,
    );
  }

  static bool? _parseBool(String? value) {
    switch (value) {
      case 'true':
      case '1':
      case 'open':
        return true;
      case 'false':
      case '0':
      case 'closed':
        return false;
      default:
        return null;
    }
  }
}
