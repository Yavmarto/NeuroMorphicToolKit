import 'dart:convert';

import 'package:neuro_toolkit/features/neurocnl/services/file_picker_native_file_backend.dart';
import 'package:neuro_toolkit/features/neurocnl/services/import_text_file_picker.dart';

class StubImportTextFilePicker extends ImportTextFilePicker {
  const StubImportTextFilePicker();

  @override
  Future<ImportedTextFile?> pickFile({
    List<String> acceptedExtensions = const <String>['cnl'],
  }) async {
    final files = await const FilePickerDialogGateway().pickFiles(
      allowMultiple: false,
      allowedExtensions: acceptedExtensions,
    );
    if (files == null || files.isEmpty) {
      return null;
    }
    final file = files.first;
    return ImportedTextFile(name: file.name, text: utf8.decode(file.bytes));
  }
}

ImportTextFilePicker createPicker() => const StubImportTextFilePicker();
