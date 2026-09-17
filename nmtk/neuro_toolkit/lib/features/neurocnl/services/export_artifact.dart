import 'dart:typed_data';

class ExportArtifact {
  const ExportArtifact.text({
    required this.filename,
    required this.mimeType,
    required String content,
  }) : textContent = content,
       bytes = null;

  const ExportArtifact.binary({
    required this.filename,
    required this.mimeType,
    required Uint8List payload,
  }) : textContent = null,
       bytes = payload;

  final String filename;
  final String mimeType;
  final String? textContent;
  final Uint8List? bytes;

  bool get isBinary => bytes != null;
}
