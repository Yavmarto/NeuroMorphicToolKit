/// Energy profiling report from the backend.
class EnergyReport {
  final Map<String, double> perEnsemblePj;
  final double totalPj;
  final int opsCount;

  const EnergyReport({
    required this.perEnsemblePj,
    required this.totalPj,
    required this.opsCount,
  });

  factory EnergyReport.fromJson(Map<String, dynamic> json) {
    final raw = json['per_ensemble_pj'] as Map<String, dynamic>;
    final mapped = raw.map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    );
    return EnergyReport(
      perEnsemblePj: mapped,
      totalPj: (json['total_pj'] as num).toDouble(),
      opsCount: json['ops_count'] as int,
    );
  }
}
