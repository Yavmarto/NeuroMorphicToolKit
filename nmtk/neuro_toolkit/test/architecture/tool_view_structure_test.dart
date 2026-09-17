import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tool_view has zero part/part-of directives', () {
    final toolViewDir = Directory('lib/screens/tool_view');
    final files = <File>[
      File('lib/screens/tool_view.dart'),
      if (toolViewDir.existsSync())
        ...toolViewDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
    ];
    final partDirective = RegExp(r'^part\s', multiLine: true);
    final partOfDirective = RegExp(r'^part of\s', multiLine: true);

    for (final file in files) {
      final content = file.readAsStringSync();
      expect(
        partDirective.hasMatch(content),
        isFalse,
        reason: '${file.path} still has a `part` directive.',
      );
      expect(
        partOfDirective.hasMatch(content),
        isFalse,
        reason: '${file.path} still has a `part of` directive.',
      );
    }
  });

  test('tool_view keeps each public class in its own file', () {
    final toolViewDir = Directory('lib/screens/tool_view');
    final files = <File>[
      File('lib/screens/tool_view.dart'),
      if (toolViewDir.existsSync())
        ...toolViewDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
    ];
    final classPattern = RegExp(r'^class\s+([A-Za-z_]\w*)\b', multiLine: true);

    for (final file in files) {
      final names = classPattern
          .allMatches(file.readAsStringSync())
          .map((match) => match.group(1)!)
          .toList(growable: false);
      final privateClasses = names.where((name) => name.startsWith('_'));

      expect(
        privateClasses.every((name) => name.endsWith('State')),
        isTrue,
        reason: '${file.path} contains a private non-State class: $names',
      );
      expect(
        names.length,
        lessThanOrEqualTo(2),
        reason: '${file.path} contains more than one class pair: $names',
      );
      if (names.length == 2) {
        final nonStateClasses = names.where((name) => !name.endsWith('State'));
        final widget = nonStateClasses.single;
        expect(
          names,
          anyOf(contains('_${widget}State'), contains('${widget}State')),
          reason:
              '${file.path} may only pair $widget with its (private or '
              'GlobalKey-public) State.',
        );
      }
    }
  });
}
