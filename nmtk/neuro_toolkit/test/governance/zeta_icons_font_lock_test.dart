// Locks ZetaIcons codepoints to the pinned zeta_icons version (1.9.3).
// If zeta_icons drifts, profile/release builds can show CJK fallback glyphs
// instead of icons — see CEL-178. macOS/APK deliver scripts must pass
// --no-tree-shake-icons so Flutter does not subset zeta-icons-round.ttf
// (CEL-229).

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

void main() {
  test('ZetaIcons.play matches zeta_icons 1.9.3 codepoint and font metadata', () {
    expect(ZetaIcons.play.codePoint, 0xe1d6);
    expect(ZetaIcons.play.fontPackage, 'zeta_icons');
    expect(ZetaIcons.play.fontFamily, isNotNull);
    expect(ZetaIcons.play.fontFamily, isNotEmpty);
  });

  test('ZetaIcons.stop matches zeta_icons 1.9.3 codepoint', () {
    expect(ZetaIcons.stop.codePoint, 0xe24f);
  });
}
