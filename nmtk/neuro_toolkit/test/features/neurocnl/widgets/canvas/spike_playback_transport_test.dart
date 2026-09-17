import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/spike_playback_transport.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('spikePlaybackWallDuration', () {
    test('speed changes playback length even for short captures', () {
      // Regression: the floor used to be applied *after* dividing by speed
      // (`max(4s, duration * k / speed)`), so for any capture short enough to
      // hit it — which is every real one, at 20-32 timesteps — all four speeds
      // produced an identical 4-second playback. The buttons highlighted and
      // changed nothing.
      const shortCapture = 25.0;
      final half = spikePlaybackWallDuration(shortCapture, 0.5);
      final normal = spikePlaybackWallDuration(shortCapture, 1.0);
      final double_ = spikePlaybackWallDuration(shortCapture, 2.0);
      final quint = spikePlaybackWallDuration(shortCapture, 5.0);

      expect(half, greaterThan(normal));
      expect(normal, greaterThan(double_));
      expect(double_, greaterThan(quint));
      // 1x floors at 4s; 2x halves it.
      expect(normal.inMilliseconds, 4000);
      expect(double_.inMilliseconds, 2000);
    });

    test('a long capture scales with its duration rather than the floor', () {
      // 1000 ms * 0.03 = 30 s, well above the 4 s floor.
      expect(spikePlaybackWallDuration(1000, 1.0).inMilliseconds, 30000);
      expect(spikePlaybackWallDuration(1000, 2.0).inMilliseconds, 15000);
    });

    test('a non-positive speed does not divide by zero', () {
      expect(spikePlaybackWallDuration(25, 0).inMilliseconds, 4000);
    });
  });

  group('spikeTrailIntensity', () {
    test('is full brightness at the spike and decays over tau', () {
      // Replaces a frame-binned trail that retained 0.78 per 1 ms frame, so
      // these are the values that keep the grid looking the way it did while
      // being sampled continuously instead of 6.25 times a second.
      expect(spikeTrailIntensity(0), 1.0);
      expect(spikeTrailIntensity(1), closeTo(0.78, 0.01));
      expect(spikeTrailIntensity(kSpikeTrailTauMs), closeTo(0.37, 0.01));
      // The renderer only draws its hotspot glow above 0.05, so a trail is
      // visually finished by ~12 ms.
      expect(spikeTrailIntensity(12), lessThan(0.05));
    });

    test('is dark before the spike and when there is no spike', () {
      expect(spikeTrailIntensity(-1), 0.0);
      expect(spikeTrailIntensity(double.nan), 0.0);
      expect(spikeTrailIntensity(double.infinity), 0.0);
    });

    test('decays monotonically', () {
      var previous = 1.0;
      for (var since = 0.5; since < 20; since += 0.5) {
        final current = spikeTrailIntensity(since);
        expect(current, lessThan(previous));
        previous = current;
      }
    });
  });

  group('SpikePlaybackTransport', () {
    testWidgets('renders play/pause, every speed chip, and the ms readout', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SpikePlaybackTransport(
            isPlaying: false,
            speed: 1.0,
            currentTimeMs: 3.5,
            duration: 25,
            onTogglePlay: () {},
            onSpeedChanged: (_) {},
            onSeek: (_) {},
          ),
        ),
      );

      expect(find.byTooltip('Play'), findsOneWidget);
      for (final label in ['½×', '1×', '2×', '5×']) {
        expect(find.text(label), findsOneWidget);
      }
      // Both clocks: 25 ms of simulation takes 4 real seconds to play, and
      // showing only the sim axis left that wait unexplained.
      expect(find.text('3.5 / 25 ms sim · 0.6 / 4.0 s'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('reports the pressed speed and seek position', (tester) async {
      double? pickedSpeed;
      double? seeked;
      var toggled = 0;

      await tester.pumpWidget(
        _wrap(
          SpikePlaybackTransport(
            isPlaying: true,
            speed: 1.0,
            currentTimeMs: 0,
            duration: 25,
            onTogglePlay: () => toggled++,
            onSpeedChanged: (s) => pickedSpeed = s,
            onSeek: (v) => seeked = v,
          ),
        ),
      );

      expect(find.byTooltip('Pause'), findsOneWidget);

      await tester.tap(find.text('5×'));
      expect(pickedSpeed, 5.0);

      await tester.tap(find.byTooltip('Pause'));
      expect(toggled, 1);

      await tester.drag(find.byType(Slider), const Offset(60, 0));
      expect(seeked, isNotNull);
      expect(seeked, greaterThan(0));
    });
  });
}
