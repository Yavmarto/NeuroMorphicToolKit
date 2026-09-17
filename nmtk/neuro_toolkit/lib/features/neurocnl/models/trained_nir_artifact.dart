/// A trained NIR graph discovered in a Jupyter workspace.
///
/// The NIR Exporter canvas node writes this after loading `best_model.pt` and
/// overlaying the learned weights, so it is the only artifact carrying real
/// values — the CNL spec stores tensor shape only. Every target without a bundle
/// format of its own gets its weights from here: the PYNQ deploy payload and the
/// three software simulators both read the same file.
class TrainedNirArtifact {
  const TrainedNirArtifact({
    required this.filename,
    required this.nirBase64,
    required this.sha256,
  });

  factory TrainedNirArtifact.fromJson(Map<String, dynamic> json) {
    return TrainedNirArtifact(
      filename: json['filename'] as String? ?? 'model.nir',
      nirBase64: json['nir_base64'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
    );
  }

  final String filename;
  final String nirBase64;
  final String sha256;

  bool get isUsable => nirBase64.isNotEmpty;
}
