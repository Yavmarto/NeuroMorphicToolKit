import 'package:neuro_toolkit/features/neurocnl/services/import_text_file_picker_stub.dart'
    if (dart.library.html) 'import_text_file_picker_web.dart';

class ImportedTextFile {
  const ImportedTextFile({required this.name, required this.text});

  final String name;
  final String text;
}

abstract class ImportTextFilePicker {
  const ImportTextFilePicker();

  Future<ImportedTextFile?> pickFile({
    List<String> acceptedExtensions = const <String>['cnl'],
  });
}

ImportTextFilePicker createImportTextFilePicker() => createPicker();
