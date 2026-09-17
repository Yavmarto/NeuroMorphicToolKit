import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';

void main() {
  group('distributePortOffset', () {
    test('proportional mode spreads ports evenly across the given length', () {
      final offsets = [
        for (int i = 0; i < 3; i += 1)
          distributePortOffset(index: i, count: 3, length: 100),
      ];

      expect(offsets, [25, 50, 75]);
    });

    test('proportional mode respects inset', () {
      final offset = distributePortOffset(
        index: 0,
        count: 1,
        length: 100,
        inset: 40,
      );

      expect(offset, 70);
    });
  });

  // Every canvas now takes its card footprint and port placement from these
  // two helpers. The Architecture cards used to render 150x132 with
  // proportionally-spread ports while the Train/Eval cards rendered 200-wide
  // with fixed 28px spacing, which is what made the two look unrelated.
  group('canvasNodeSize', () {
    test('a 1-2 port node keeps the baseline footprint', () {
      expect(
        canvasNodeSize(inputs: 1, outputs: 1, compact: false),
        const Size(kCanvasNodeWidth, kCanvasNodeBaseHeight),
      );
      expect(
        canvasNodeSize(inputs: 2, outputs: 1, compact: false),
        const Size(kCanvasNodeWidth, kCanvasNodeBaseHeight),
      );
    });

    test('grows only once proportional spacing would get too tight', () {
      final Size threePorts = canvasNodeSize(
        inputs: 1,
        outputs: 3,
        compact: false,
      );

      expect(threePorts.width, kCanvasNodeWidth);
      expect(threePorts.height, greaterThan(kCanvasNodeBaseHeight));

      // The reason it grows at all: ports must not crowd closer than
      // kCanvasNodeMinPortSpacing, or the 30px hit targets collide.
      final double spacing =
          (threePorts.height - kCanvasNodeHeaderHeight) / (3 + 1);
      expect(spacing, greaterThanOrEqualTo(kCanvasNodeMinPortSpacing));
    });

    test('a collapsed card is header-height only', () {
      expect(
        canvasNodeSize(
          inputs: 3,
          outputs: 3,
          compact: false,
          collapsed: true,
        ).height,
        kCanvasNodeCollapsedHeight,
      );
    });

    test('compact cards are the same width as horizontal ones', () {
      expect(
        canvasNodeSize(inputs: 1, outputs: 1, compact: true).width,
        canvasNodeSize(inputs: 1, outputs: 1, compact: false).width,
      );
    });
  });

  group('canvasNodePortCentre', () {
    const Size card = Size(kCanvasNodeWidth, kCanvasNodeBaseHeight);

    test('horizontal layout puts inputs left and outputs right, below the '
        'header', () {
      final Offset input = canvasNodePortCentre(
        index: 0,
        count: 1,
        cardSize: card,
        isInput: true,
        compact: false,
      );
      final Offset output = canvasNodePortCentre(
        index: 0,
        count: 1,
        cardSize: card,
        isInput: false,
        compact: false,
      );

      expect(input.dx, kCanvasPortHitTargetSize / 2);
      expect(output.dx, card.width - kCanvasPortHitTargetSize / 2);
      expect(input.dy, greaterThan(kCanvasNodeHeaderHeight));
      expect(input.dy, output.dy);
    });

    test('compact layout puts inputs on the top edge and outputs on the '
        'bottom', () {
      final Offset input = canvasNodePortCentre(
        index: 0,
        count: 2,
        cardSize: card,
        isInput: true,
        compact: true,
      );
      final Offset output = canvasNodePortCentre(
        index: 0,
        count: 2,
        cardSize: card,
        isInput: false,
        compact: true,
      );

      expect(input.dy, kCanvasPortHitTargetSize / 2);
      expect(output.dy, card.height - kCanvasPortHitTargetSize / 2);
      expect(input.dx, card.width / 3);
    });

    test('a collapsed card spreads its ports over the whole height', () {
      const Size collapsed = Size(kCanvasNodeWidth, kCanvasNodeCollapsedHeight);
      final Offset port = canvasNodePortCentre(
        index: 0,
        count: 1,
        cardSize: collapsed,
        isInput: true,
        compact: false,
        collapsed: true,
      );

      expect(port.dy, kCanvasNodeCollapsedHeight / 2);
    });

    test('topLeft is the centre minus half a hit target', () {
      final Offset centre = canvasNodePortCentre(
        index: 0,
        count: 1,
        cardSize: card,
        isInput: true,
        compact: false,
      );
      final Offset topLeft = canvasNodePortTopLeft(
        index: 0,
        count: 1,
        cardSize: card,
        isInput: true,
        compact: false,
      );

      expect(
        topLeft,
        centre -
            const Offset(
              kCanvasPortHitTargetSize / 2,
              kCanvasPortHitTargetSize / 2,
            ),
      );
    });
  });

  group('buildOutsidePortLabel', () {
    // Regression test: on the compact (mobile/vertical) layout, every port
    // on the same edge used to share the identical top/bottom offset, so
    // 2+ connector labels physically overlapped on one row. edgeIndex must
    // now push each successive label into its own row further from the card.
    test('stacks same-edge compact labels into separate rows', () {
      final first =
          buildOutsidePortLabel(
                text: 'a',
                anchor: const Offset(20, 0),
                portIsInput: true,
                isCompact: true,
                nodeWidth: 128,
                nodeHeight: 80,
                edgeIndex: 0,
              )
              as Positioned;
      final second =
          buildOutsidePortLabel(
                text: 'b',
                anchor: const Offset(60, 0),
                portIsInput: true,
                isCompact: true,
                nodeWidth: 128,
                nodeHeight: 80,
                edgeIndex: 1,
              )
              as Positioned;

      expect(first.bottom, isNotNull);
      expect(second.bottom, isNotNull);
      expect(
        second.bottom,
        greaterThan(first.bottom!),
        reason: 'the second same-edge label must sit in a further-out row',
      );
    });

    test('outputs anchor from the top (via `top`) instead of `bottom`', () {
      final label =
          buildOutsidePortLabel(
                text: 'out',
                anchor: const Offset(20, 0),
                portIsInput: false,
                isCompact: true,
                nodeWidth: 128,
                nodeHeight: 80,
                edgeIndex: 0,
              )
              as Positioned;

      expect(label.top, isNotNull);
      expect(label.bottom, isNull);
    });

    test('desktop/horizontal layout keeps ports on distinct anchors', () {
      final first =
          buildOutsidePortLabel(
                text: 'a',
                anchor: const Offset(0, 20),
                portIsInput: true,
                isCompact: false,
                nodeWidth: 150,
                nodeHeight: 132,
                edgeIndex: 0,
              )
              as Positioned;
      final second =
          buildOutsidePortLabel(
                text: 'b',
                anchor: const Offset(0, 60),
                portIsInput: true,
                isCompact: false,
                nodeWidth: 150,
                nodeHeight: 132,
                edgeIndex: 1,
              )
              as Positioned;

      expect(first.top, isNot(equals(second.top)));
    });
  });
}
