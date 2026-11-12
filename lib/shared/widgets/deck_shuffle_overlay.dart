import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_color_tokens.dart';

/// Khouloud's shuffle (Lottie Simple License), tinted to the current accent.
const kShuffleCardsAsset = 'assets/animations/shuffle_cards.json';

const kShuffleWaitDelay = Duration(milliseconds: 250);

/// Shows [DeckShuffleOverlay] only if a wait lasts longer than [kShuffleWaitDelay].
class ShuffleWait {
  ShuffleWait({required this.onChanged});

  final VoidCallback onChanged;
  Timer? _timer;
  var waiting = false;
  var visible = false;

  void begin() {
    waiting = true;
    _timer?.cancel();
    if (visible) return;
    _timer = Timer(kShuffleWaitDelay, () {
      if (!waiting || visible) return;
      visible = true;
      onChanged();
    });
  }

  void end() {
    waiting = false;
    _timer?.cancel();
    if (!visible) return;
    visible = false;
    onChanged();
  }

  void dispose() {
    waiting = false;
    _timer?.cancel();
  }
}

/// Frosted shuffle while Scryfall art is still in flight.
class DeckShuffleOverlay extends StatelessWidget {
  const DeckShuffleOverlay({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child:
              visible
                  ? const _ShuffleScrim(key: ValueKey('deck-shuffle-overlay'))
                  : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _ShuffleScrim extends StatelessWidget {
  const _ShuffleScrim({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final shades = _shuffleShades(colors.primaryAccent);
    return Semantics(
      label: AppLocalizations.of(context).deckAlbumShuffling,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: ColoredBox(
            color: colors.backgroundPrimary.withValues(alpha: 0.55),
            child: Center(
              child: SizedBox(
                width: 168,
                height: 168,
                child: Lottie.asset(
                  kShuffleCardsAsset,
                  repeat: true,
                  delegates: LottieDelegates(
                    values: [
                      for (var i = 0; i < _shuffleLayerNames.length; i++)
                        ValueDelegate.color([
                          _shuffleLayerNames[i],
                          '**',
                        ], value: shades[i]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _shuffleLayerNames = ['Card_1', 'Card_2', 'Card_3', 'Card_4', 'Card_5'];

List<Color> _shuffleShades(Color accent) {
  final hsl = HSLColor.fromColor(accent);
  double light(double amount) =>
      (hsl.lightness + amount).clamp(0.18, 0.94).toDouble();
  return [
    hsl.withLightness(light(0.38)).toColor(),
    hsl.withLightness(light(0.22)).toColor(),
    accent,
    hsl.withLightness(light(-0.08)).toColor(),
    hsl.withLightness(light(-0.22)).toColor(),
  ];
}
