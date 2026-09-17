// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

import 'package:neuro_toolkit/features/neurocnl/services/import_text_file_picker.dart';

class WebImportTextFilePicker extends ImportTextFilePicker {
  const WebImportTextFilePicker();

  @override
  Future<ImportedTextFile?> pickFile({
    List<String> acceptedExtensions = const <String>['cnl'],
  }) async {
    final input = html.FileUploadInputElement()
      ..accept = acceptedExtensions.map((ext) => '.$ext').join(',')
      ..multiple = false;
    input.click();

    await input.onChange.first;
    final file = input.files?.first;
    if (file == null) {
      return null;
    }

    final reader = html.FileReader();
    final completer = Completer<ImportedTextFile?>();
    reader.onLoadEnd.listen((_) {
      final text = reader.result as String?;
      if (text == null) {
        completer.complete(null);
        return;
      }
      completer.complete(ImportedTextFile(name: file.name, text: text));
    });
    reader.onError.listen((_) {
      completer.completeError(reader.error ?? 'Failed to read imported file.');
    });
    reader.readAsText(file);
    return completer.future;
  }
}

ImportTextFilePicker createPicker() => const WebImportTextFilePicker();
