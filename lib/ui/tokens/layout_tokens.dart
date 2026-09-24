import 'package:flutter/material.dart';

/// Layout and proportion constants.
///
/// **Spacing** uses four steps: 8 tight, 16 normal, 24 page margin, 32 between
/// sections. [gr0] and [gr1] are 8. [gr2] and [gr3] are 16. [gr6] is the 48dp
/// tap target, not a gap. Use [SpacingTokens] for the same steps with semantic
/// names (`xs`, `sm`, …).
///
/// **Golden ratio** helpers remain for non-spacing proportions (e.g. aspect
/// ratios), not for padding or font sizes.
class LayoutTokens {
  LayoutTokens._();

  /// Golden ratio φ ≈ 1.618 (aspect ratios only — not the spacing scale).
  static const double goldenRatio = 1.618;

  /// Inverse golden ratio 1/φ ≈ 0.618.
  static const double goldenRatioInverse = 0.618;

  /// Tight (8). Icon-to-label and other compact controls.
  static const double gr0 = 8;

  /// Tight (8). Same step as [gr0].
  static const double gr1 = 8;

  /// Normal (16). Card padding and gaps between related items.
  static const double gr2 = 16;

  /// Normal (16). Same step as [gr2].
  static const double gr3 = 16;

  /// Page margin (24).
  static const double gr4 = 24;

  /// Space between major sections (32).
  static const double gr5 = 32;

  /// Minimum tap target (48). Not a layout gap.
  static const double gr6 = 48;

  /// Minimum **48×48 dp** tap target.
  static const double minTapTarget = gr6;

  /// Comfortable thumb target for in-game ± steppers (table play).
  static const double thumbTapTarget = 56;

  // ── Named layout constants ────────────────────────────────────────────────

  /// Width of profile/My Decks horizontal carousel cards.
  ///
  /// Height is derived via [profileCarouselCardHeightForWidth] (2:3 portrait).
  static const double profileCarouselCardWidth = 240;

  /// Carousel card aspect ratio — width : height = 2 : 3.
  static const double profileCarouselCardWidthOverHeight = 2 / 3;

  /// Fixed 2:3 height for [profileCarouselCardWidth] (240×360).
  static const double profileCarouselCardCanonicalHeight = 360;

  /// Height for a carousel card at [width], preserving [profileCarouselCardWidthOverHeight].
  static double profileCarouselCardHeightForWidth(double width) {
    final h = width / profileCarouselCardWidthOverHeight;
    return (h / gr0).round() * gr0;
  }

  /// Height of the shell dock bar ([AppBottomNavBar] content area). 72dp.
  static const double bottomNavHeight = 72;

  /// Horizontal inset for full-width CTAs. Matches the 24 page margin.
  static const double ctaHorizontal = gr4;

  // ── Shell tab insets ([MainShell] + floating [AppBottomNavBar]) ───────────
  //
  // • [shellPageInset] (gr4 / 24) — default left/right for tab content, lists,
  //   profile hero.
  // • [shellSectionGap] (gr5 / 32) — vertical gap between page sections.
  // • [shellListPadding] — full ListView pad including [shellBottomInset] when
  //   the list scrolls above the dock with no sticky footer.
  // • [shellScrollPadding] — same horizontal/top when a bottom bar or CTA row
  //   applies [shellBottomInset] outside the scroll view.
  // • [ctaHorizontal] (gr4 / 24) — primary full-width buttons on setup/onboarding.

  /// Default horizontal margin for shell tabs (Home, Lobby, Decks, Settings).
  static const double shellPageInset = gr4;

  /// Vertical gap between major sections on shell pages.
  static const double shellSectionGap = gr5;

  /// Bottom clearance for content under [MainShell]'s floating nav + home indicator.
  static double shellBottomInset(BuildContext context) {
    return bottomNavHeight + MediaQuery.paddingOf(context).bottom + gr2;
  }

  /// Standard [ListView] padding inside shell tabs.
  static EdgeInsets shellListPadding(
    BuildContext context, {
    double horizontal = shellPageInset,
    double top = shellPageInset,
  }) {
    return EdgeInsets.fromLTRB(
      horizontal,
      top,
      horizontal,
      shellBottomInset(context),
    );
  }

  /// Scroll padding when bottom inset is handled by a sticky footer or dock bar.
  static EdgeInsets shellScrollPadding(
    BuildContext context, {
    double horizontal = shellPageInset,
    double top = shellPageInset,
    double bottom = gr2,
  }) {
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }
}

/// Width / height hints for **in-game** layouts (personal view, HUD rows).
abstract final class GameLayoutBreakpoints {
  static const double narrow = 320;
  static const double compact = 360;
  static const double comfortable = 400;
  static const double shortViewport = 720;
}
