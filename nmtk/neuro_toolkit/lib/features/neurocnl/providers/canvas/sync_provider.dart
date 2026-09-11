import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/admin_token_http_client.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';

part 'sync_provider.g.dart';

final apiClientProvider = Provider((ref) {
  final launchContext = ref.watch(featureLaunchContextProvider);
  return ApiClient(
    baseUrl: launchContext.backendUri.toString(),
    httpClient: AdminTokenHttpClient(
      adminToken: launchContext.authentication.adminToken,
      onReportError: launchContext.onReportError,
      onRecovered: launchContext.onRecovered,
    ),
  );
});

class CanvasSyncIssue {
  const CanvasSyncIssue({
    required this.message,
    this.unsupportedConcepts = const [],
  });

  final String message;
  final List<String> unsupportedConcepts;
}

@riverpod
class CanvasSyncIssueController extends _$CanvasSyncIssueController {
  @override
  CanvasSyncIssue? build() => null;

  void setState(CanvasSyncIssue? issue) => state = issue;
}

final canvasSyncIssueProvider = canvasSyncIssueControllerProvider;
