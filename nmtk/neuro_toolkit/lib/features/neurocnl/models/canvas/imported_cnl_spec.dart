enum ImportedCnlSource { file, studioImport }

class ImportedCnlSpec {
  const ImportedCnlSpec({
    required this.content,
    required this.source,
    this.label,
  });

  final String content;
  final ImportedCnlSource source;
  final String? label;

  String get sourceLabel {
    return switch (source) {
      ImportedCnlSource.file =>
        label == null ? 'Imported file' : 'File: $label',
      ImportedCnlSource.studioImport => 'Imported from CNL Studio',
    };
  }
}
