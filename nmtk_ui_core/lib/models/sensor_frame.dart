/// A single sensor frame from hardware or replay.
class SensorFrame {
  final double timestamp;
  final List<double> emgChannels;
  final Map<String, double>? eegBands;
  final double? proximity;

  const SensorFrame({
    required this.timestamp,
    required this.emgChannels,
    this.eegBands,
    this.proximity,
  });

  factory SensorFrame.fromJson(Map<String, dynamic> json) {
    Map<String, double>? eeg;
    if (json['eeg_bands'] != null) {
      final raw = json['eeg_bands'] as Map<String, dynamic>;
      eeg = raw.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      );
    }
    return SensorFrame(
      timestamp: (json['timestamp'] as num).toDouble(),
      emgChannels: (json['emg_channels'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
      eegBands: eeg,
      proximity: (json['proximity'] as num?)?.toDouble(),
    );
  }
}
