import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Studio keeps each public class in its own file', () {
    final studioRoot = Directory('lib/features/neurocnl/features/studio');
    final files = <File>[
      File('lib/features/neurocnl/screens/studio_screen.dart'),
      if (studioRoot.existsSync())
        ...studioRoot
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
        // A file may pair exactly one public Widget with its State class,
        // which is private (`_${Widget}State`) unless the State must be
        // addressed from outside its library — e.g. via a `GlobalKey`, the
        // same pattern Flutter itself uses for `FormState`/`ScaffoldState`
        // — in which case the State class is public (`${Widget}State`).
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
