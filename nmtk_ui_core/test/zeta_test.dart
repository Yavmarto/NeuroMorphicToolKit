import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

void main() {
  testWidgets('Zeta colors test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ZetaProvider(
        builder: (context, lightTheme, darkTheme, themeMode) => MaterialApp(
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          home: Builder(
            builder: (context) {
              final zetaColors = Zeta.of(context).colors;
              expect(zetaColors.mainPrimary, isA<Color>());
              expect(zetaColors.mainDefault, isA<Color>());
              return Container();
            },
          ),
        ),
      ),
    );
  });
}
