/// Fault injection analysis report from the backend.
class FaultInjectionReport {
  final double errorRate;
  final double baselineAccuracy;
  final double degradedAccuracy;
  final List<String> failedNodes;
  final double resilienceScore;

  const FaultInjectionReport({
    required this.errorRate,
    required this.baselineAccuracy,
    required this.degradedAccuracy,
    required this.failedNodes,
    required this.resilienceScore,
  });

  factory FaultInjectionReport.fromJson(Map<String, dynamic> json) {
    return FaultInjectionReport(
      errorRate: (json['error_rate'] as num).toDouble(),
      baselineAccuracy: (json['baseline_accuracy'] as num).toDouble(),
      degradedAccuracy: (json['degraded_accuracy'] as num).toDouble(),
      failedNodes: (json['failed_nodes'] as List).cast<String>(),
      resilienceScore: (json['resilience_score'] as num).toDouble(),
    );
  }
}
