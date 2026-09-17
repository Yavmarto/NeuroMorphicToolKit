import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

class ActivityComparisonData {
  const ActivityComparisonData({
    required this.frameworks,
    required this.matrix,
  });

  final List<String> frameworks;
  final List<List<double>> matrix;

  factory ActivityComparisonData.fromJson(Map<String, dynamic> json) =>
      ActivityComparisonData(
        frameworks: List<String>.from(json['frameworks'] as List),
        matrix: (json['matrix'] as List)
            .map(
              (row) => List<double>.from(
                (row as List).map((value) => (value as num).toDouble()),
              ),
            )
            .toList(),
      );
}

Future<ActivityComparisonData?> fetchActivityComparison(
  List<Map<String, String>> jobs,
  ApiClient client,
) async {
  if (jobs.length < 2) return null;
  try {
    return ActivityComparisonData.fromJson(await client.compareActivity(jobs));
  } catch (_) {
    return null;
  }
}
