import 'package:flutter/material.dart';

/// Material 3 corner radius scale.
///
/// This app uses 4 (checkboxes), 20 (short controls), 28 (cards and bars),
/// and fully round. The other steps stay on the scale for reference.
/// https://m3.material.io/styles/shape/corner-radius-scale
class RadiusTokens {
  RadiusTokens._();

  // ── Standard UI scale ─────────────────────────────────────────────────────
  /// Extra-small (4). Tight controls, menus, compact badges.
  static const double xs = 4;

  /// Small (8). Compact tiles and small controls.
  static const double sm = 8;

  /// Medium (12). Default cards and buttons.
  static const double md = 12;

  /// Large (16). Larger cards and dialogs.
  static const double lg = 16;

  /// Large increased (20). Short controls where 28 would become a pill.
  static const double lgIncreased = 20;

  /// Extra-large (28). Hero surfaces, sheets, profile cards.
  static const double xl = 28;

  /// Full. Segmented controls and avatars only.
  static const double pill = 999;

  // ── Names kept for existing call sites ────────────────────────────────────

  /// Extra-small (4). QR frame, code chips, compact badges.
  static const double controlXs = xs;

  /// Small (8). Commander grid cells, onboarding dots.
  static const double controlMd = sm;

  /// Medium (12). HUD chips and modest buttons such as End turn.
  static const double controlSm = md;

  /// Medium (12). Lobby slot cards, end-game tiles.
  static const double chip = md;

  // ── Hero cards ────────────────────────────────────────────────────────────

  /// Profile carousel / deck shelf cards (28). Alias: [bento].
  static const double carouselCard = xl;

  /// Legacy name for [carouselCard].
  static const double bento = carouselCard;

  // ── BorderRadius constants ────────────────────────────────────────────────
  static const BorderRadius radiusXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius radiusControlMd = BorderRadius.all(
    Radius.circular(controlMd),
  );
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius radiusLgIncreased = BorderRadius.all(
    Radius.circular(lgIncreased),
  );
  static const BorderRadius radiusXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius radiusCarouselCard = BorderRadius.all(
    Radius.circular(carouselCard),
  );
  static const BorderRadius radiusBento = radiusCarouselCard;
  static const BorderRadius radiusPill = BorderRadius.all(
    Radius.circular(pill),
  );
  static const BorderRadius radiusControlSm = BorderRadius.all(
    Radius.circular(controlSm),
  );
  static const BorderRadius radiusChip = BorderRadius.all(
    Radius.circular(chip),
  );

  /// Modal bottom sheets in game / profile flows.
  static const BorderRadius radiusSheetTop = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
}
