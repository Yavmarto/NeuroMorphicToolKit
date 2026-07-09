import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

void main() {
  testWidgets('Zeta colors test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ZetaProvider(
        child: Builder(
          builder: (context) {
            final zetaColors = Zeta.of(context).colors;
            print(zetaColors.blue[10]);
            print(zetaColors.blue[100]);
            return Container();
          },
        ),
      ),
    );
  });
}
