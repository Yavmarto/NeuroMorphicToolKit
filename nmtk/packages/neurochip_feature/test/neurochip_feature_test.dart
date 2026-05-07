import 'package:flutter_test/flutter_test.dart';
import 'package:neurochip_feature/neurochip_feature.dart';

void main() {
  test('normalizes legacy teensy deep links into Studio deploy routes', () {
    expect(
      normalizeNeurochipDeepLinkForStudio(
        'https://neurochip.local/teensy?selectedTargetId=teensy41',
      ),
      '/?selectedTargetId=teensy41&panel=deploy&target=teensy',
    );
  });

  test('preserves Akida handoff payloads when normalizing deep links', () {
    expect(
      normalizeNeurochipDeepLinkForStudio(
        '/akida?import_akida=payload123&selectedTargetId=akida',
      ),
      '/?import_akida=payload123&selectedTargetId=akida&panel=deploy&target=akida',
    );
  });
}
