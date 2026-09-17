import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_destination.dart';

class NeurobenchRouteState {
  const NeurobenchRouteState({
    this.tab = NeurobenchWorkbenchTab.configure,
    this.benchmarkId,
    this.baselineId,
    this.resultId,
    this.jobId,
  });

  final NeurobenchWorkbenchTab tab;
  final String? benchmarkId;
  final String? baselineId;
  final String? resultId;
  final String? jobId;

  NeurobenchWorkspace get workspace => switch (tab) {
        NeurobenchWorkbenchTab.compare => NeurobenchWorkspace.comparison,
        NeurobenchWorkbenchTab.reports => NeurobenchWorkspace.reports,
        NeurobenchWorkbenchTab.robustness => NeurobenchWorkspace.robustness,
        NeurobenchWorkbenchTab.configure ||
        NeurobenchWorkbenchTab.results =>
          NeurobenchWorkspace.summary,
      };

  factory NeurobenchRouteState.fromUri(Uri uri) {
    final tabFromPath = workbenchTabFromLegacyPath(uri.path);
    final tabFromQuery = uri.queryParameters['tab'];
    final tab = tabFromQuery != null && uri.path == '/'
        ? workbenchTabFromQuery(tabFromQuery)
        : tabFromPath;

    return NeurobenchRouteState(
      tab: tab,
      benchmarkId: _normalize(uri.queryParameters['benchmarkId']),
      baselineId: _normalize(uri.queryParameters['baselineId']),
      resultId: _normalize(uri.queryParameters['resultId']),
      jobId: _normalize(uri.queryParameters['jobId']),
    );
  }

  String get location {
    final uri = Uri(
      path: '/',
      queryParameters: {
        if (tab != NeurobenchWorkbenchTab.configure) 'tab': tab.queryValue,
        'benchmarkId': ?_normalize(benchmarkId),
        'baselineId': ?_normalize(baselineId),
        'resultId': ?_normalize(resultId),
        'jobId': ?_normalize(jobId),
      },
    );
    final location = uri.toString();
    return location.isEmpty ? '/' : location;
  }

  NeurobenchRouteState copyWith({
    NeurobenchWorkbenchTab? tab,
    String? benchmarkId,
    String? baselineId,
    String? resultId,
    String? jobId,
    bool clearBenchmarkId = false,
    bool clearBaselineId = false,
    bool clearResultId = false,
    bool clearJobId = false,
  }) {
    return NeurobenchRouteState(
      tab: tab ?? this.tab,
      benchmarkId: clearBenchmarkId ? null : benchmarkId ?? this.benchmarkId,
      baselineId: clearBaselineId ? null : baselineId ?? this.baselineId,
      resultId: clearResultId ? null : resultId ?? this.resultId,
      jobId: clearJobId ? null : jobId ?? this.jobId,
    );
  }

  static String? _normalize(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}

/// Maps legacy top-level paths (`/comparison`, `/reports`, `/robustness`) to `/?tab=…`.
String? legacyWorkbenchRedirectLocation(Uri uri) {
  final path = uri.path;
  if (path == '/' || path.isEmpty) {
    return null;
  }

  final tab = switch (path) {
    '/comparison' => 'compare',
    '/reports' => 'reports',
    '/robustness' => 'robustness',
    _ => null,
  };
  if (tab == null) {
    return null;
  }

  final query = Map<String, String>.from(uri.queryParameters);
  query['tab'] = tab;
  return Uri(path: '/', queryParameters: query).toString();
}
