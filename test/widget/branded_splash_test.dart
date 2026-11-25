import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:mgt_life_spark/shared/widgets/branded_splash.dart';
import 'package:video_player/video_player.dart';

void main() {
  test('intro fades in quickly after playback starts', () {
    expect(BrandedSplash.introFade.inMilliseconds, inInclusiveRange(100, 200));
    expect(
      BrandedSplash.videoStartTimeout,
      greaterThan(BrandedSplash.introFade),
    );
  });

  testWidgets('BrandedSplash does not show loading cue on a fast ready path', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: BrandedSplash(ready: true, useVideoIntro: false)),
    );

    await tester.pump();
    expect(find.text('Loading Life Spark…'), findsNothing);
    await tester.pump(BrandedSplash.revealDuration);
    await tester.pump(BrandedSplash.revealHold);
  });

  testWidgets('BrandedSplash shows loading cue only after slow threshold', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: BrandedSplash(useVideoIntro: false)),
    );

    await tester.pump();
    expect(find.text('Loading Life Spark…'), findsNothing);

    await tester.pump(BrandedSplash.slowLoadThreshold);
    expect(find.text('Loading Life Spark…'), findsOneWidget);
    await tester.pump(BrandedSplash.revealDuration);
  });

  testWidgets('BrandedSplash completes after black intro hold when ready', (
    tester,
  ) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: BrandedSplash(
          ready: true,
          useVideoIntro: false,
          onRevealComplete: () => completed = true,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(BrandedSplash.revealDuration);
    await tester.pump(BrandedSplash.revealHold);
    await tester.pump();

    expect(completed, isTrue);
  });

  testWidgets('ready flipping after intro does not setState during build', (
    tester,
  ) async {
    var ready = false;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return BrandedSplash(
              ready: ready,
              useVideoIntro: false,
              onRevealComplete: () => completed = true,
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(BrandedSplash.revealDuration);

    ready = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return BrandedSplash(
              ready: ready,
              useVideoIntro: false,
              onRevealComplete: () => completed = true,
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(BrandedSplash.revealHold);
    await tester.pump();
    await tester.pump(BrandedSplash.slowLoadThreshold);

    expect(tester.takeException(), isNull);
    expect(completed, isTrue);
  });

  testWidgets('logo animation hands off once when ready', (tester) async {
    final data = await rootBundle.load(BrandedSplash.logoAnimationAsset);
    final composition = await LottieComposition.fromBytes(
      data.buffer.asUint8List(),
    );
    expect(composition.duration, BrandedSplash.logoAnimationDuration);

    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: BrandedSplash(
          ready: true,
          onRevealComplete: () => completed = true,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    // Let the composition mount, then play past its end plus the handoff holds.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(BrandedSplash.logoAnimationDuration);
    await tester.pump(BrandedSplash.taglineHold);
    await tester.pump(BrandedSplash.revealHold);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(completed, isTrue);
  });

  testWidgets('logo frames stay cheap enough to leave the splash', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: BrandedSplash(ready: true)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final clock = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    clock.stop();
    expect(tester.takeException(), isNull);
    // 20 frames of the spinning mark should not stall startup.
    expect(clock.elapsedMilliseconds, lessThan(4000));
  });

  testWidgets('disabled video intro stays black with no player', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: BrandedSplash(ready: true, useVideoIntro: false)),
    );
    await tester.pump();
    expect(find.byType(VideoPlayer), findsNothing);
    await tester.pump(BrandedSplash.revealDuration);
    await tester.pump(BrandedSplash.revealHold);
  });
}
