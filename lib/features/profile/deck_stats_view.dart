import 'package:flutter/material.dart';

import '../../core/deck/deck_list_text.dart';
import '../../core/game/scryfall_service.dart';
import '../../core/models/deck_card_entry.dart';
import '../../core/models/player_deck.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/mana_cost_pips.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import 'deck_stats.dart';

class DeckAlbumPageSwitch extends StatelessWidget {
  const DeckAlbumPageSwitch({
    super.key,
    required this.showStats,
    required this.onChanged,
  });

  final bool showStats;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RadiusTokens.pill),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: _PageSegment(
                label: l10n.deckAlbumTabCards,
                selected: !showStats,
                colors: colors,
                onTap: () => onChanged(false),
              ),
            ),
            Expanded(
              child: _PageSegment(
                label: l10n.deckAlbumTabStats,
                selected: showStats,
                colors: colors,
                onTap: () => onChanged(true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageSegment extends StatelessWidget {
  const _PageSegment({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppColorTokens colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.pill);
    return Material(
      color: selected ? colors.primaryAccent : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : colors.textPrimary,
              fontSize: FontTokens.body,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class DeckStatsView extends StatelessWidget {
  const DeckStatsView({
    super.key,
    required this.deck,
    required this.entries,
    required this.cards,
  });

  final PlayerDeck deck;
  final List<DeckCardEntry> entries;
  final Map<String, ScryfallCard> cards;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stats = computeDeckStats(deck: deck, entries: entries, cards: cards);
    if (stats.countedCards == 0) {
      return Padding(
        padding: const EdgeInsets.only(top: LayoutTokens.gr5),
        child: Text(
          l10n.deckStatsEmpty,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColorTokens.of(context).textSecondary,
            fontSize: FontTokens.body,
          ),
        ),
      );
    }

    final average = stats.averageManaValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: LayoutTokens.gr3),
        Row(
          children: [
            Expanded(
              child: _SummaryTile(
                label: l10n.deckStatsAverageManaValue,
                value: average == null ? '—' : average.toStringAsFixed(1),
              ),
            ),
            SizedBox(width: LayoutTokens.gr3),
            Expanded(
              child: _SummaryTile(
                label: l10n.deckStatsLands,
                value: '${stats.landCount}',
              ),
            ),
          ],
        ),
        SizedBox(height: LayoutTokens.gr3),
        _StatCard(
          title: l10n.deckStatsManaValue,
          child:
              stats.manaValue.every((count) => count == 0)
                  ? const _NoneLabel()
                  : _ManaCurve(counts: stats.manaValue),
        ),
        SizedBox(height: LayoutTokens.gr3),
        _StatCard(
          title: l10n.deckStatsManaCost,
          child:
              stats.manaCost.isEmpty
                  ? const _NoneLabel()
                  : _ColorBars(rows: stats.manaCost),
        ),
        SizedBox(height: LayoutTokens.gr3),
        _StatCard(
          title: l10n.deckStatsManaProduction,
          child:
              stats.manaProduction.isEmpty
                  ? const _NoneLabel()
                  : _ColorBars(rows: stats.manaProduction),
        ),
        SizedBox(height: LayoutTokens.gr3),
        _StatCard(
          title: l10n.deckStatsCardType,
          child:
              stats.cardTypes.isEmpty
                  ? const _NoneLabel()
                  : _LabelBars(
                    rows: [
                      for (final row in stats.cardTypes)
                        DeckNamedCount(_typeLabel(l10n, row.group), row.count),
                    ],
                    barColors: [
                      for (final row in stats.cardTypes) _typeColor(row.group),
                    ],
                  ),
        ),
        SizedBox(height: LayoutTokens.gr3),
        _StatCard(
          title: l10n.deckStatsSubtype,
          child:
              stats.subtypes.isEmpty
                  ? const _NoneLabel()
                  : _LabelBars(rows: stats.subtypes),
        ),
        SizedBox(height: LayoutTokens.gr3),
        _StatCard(
          title: l10n.deckStatsToken,
          child:
              stats.tokens.isEmpty
                  ? const _NoneLabel()
                  : _LabelBars(rows: stats.tokens),
        ),
      ],
    );
  }
}

String _typeLabel(AppLocalizations l10n, DeckCardGroup group) {
  return switch (group) {
    DeckCardGroup.creature => l10n.deckAlbumCreatures,
    DeckCardGroup.instant => l10n.deckAlbumInstants,
    DeckCardGroup.sorcery => l10n.deckAlbumSorceries,
    DeckCardGroup.artifact => l10n.deckAlbumArtifacts,
    DeckCardGroup.enchantment => l10n.deckAlbumEnchantments,
    DeckCardGroup.planeswalker => l10n.deckAlbumPlaneswalkers,
    DeckCardGroup.land => l10n.deckAlbumLands,
    DeckCardGroup.other => l10n.deckAlbumOther,
  };
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RadiusTokens.lg),
        border: Border.all(color: colors.primaryAccent.withValues(alpha: 0.35)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryAccent.withValues(alpha: 0.22),
            colors.surface,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LayoutTokens.gr3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: colors.primaryAccent,
                fontSize: FontTokens.headline,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            SizedBox(height: LayoutTokens.gr1),
            Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: FontTokens.caption,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RadiusTokens.lg),
        border: Border.all(color: colors.borderSubtle),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.surfaceElevated, colors.surface],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LayoutTokens.gr3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: colors.primaryAccent,
                    borderRadius: BorderRadius.circular(RadiusTokens.xs),
                  ),
                ),
                SizedBox(width: LayoutTokens.gr2),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: FontTokens.body,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: LayoutTokens.gr2),
            Container(height: 1, color: colors.borderSubtle),
            SizedBox(height: LayoutTokens.gr3),
            child,
          ],
        ),
      ),
    );
  }
}

class _NoneLabel extends StatelessWidget {
  const _NoneLabel();

  @override
  Widget build(BuildContext context) {
    return Text(
      AppLocalizations.of(context).deckStatsNone,
      style: TextStyle(
        color: AppColorTokens.of(context).textMuted,
        fontSize: FontTokens.caption,
      ),
    );
  }
}

class _ManaCurve extends StatelessWidget {
  const _ManaCurve({required this.counts});

  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    final maxCount = counts.fold<int>(
      0,
      (max, count) => count > max ? count : max,
    );
    return SizedBox(
      height: 148,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final count in counts)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '$count',
                          style: TextStyle(
                            color:
                                count == 0
                                    ? colors.textMuted
                                    : colors.textPrimary,
                            fontSize: FontTokens.caption,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: LayoutTokens.gr1),
                        Container(
                          width: 18,
                          height: _curveHeight(count, maxCount),
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                colors.primaryAccent,
                                colors.primaryAccent.withValues(alpha: 0.4),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: colors.borderSubtle),
          SizedBox(height: LayoutTokens.gr1),
          Row(
            children: [
              for (var index = 0; index < counts.length; index++)
                Expanded(
                  child: Text(
                    index == 7 ? l10n.deckStatsManaValuePlus : '$index',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: FontTokens.caption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

double _curveHeight(int count, int maxCount) {
  if (maxCount == 0 || count == 0) return 0;
  final raw = 88 * count / maxCount;
  if (raw < 4) return 4;
  if (raw > 88) return 88;
  return raw;
}

const _previewLimit = 10;

class _ColorBars extends StatelessWidget {
  const _ColorBars({required this.rows});

  final List<DeckNamedCount> rows;

  @override
  Widget build(BuildContext context) {
    return _ExpandableBars(
      rows: rows,
      bar:
          (row, maxCount) => _BarRow(
            leading: ManaCostPips(manaCost: '{${row.label}}', symbolHeight: 16),
            label: '',
            count: row.count,
            maxCount: maxCount,
            color: _manaColor(row.label),
          ),
    );
  }
}

class _LabelBars extends StatelessWidget {
  const _LabelBars({required this.rows, this.barColors});

  final List<DeckNamedCount> rows;
  final List<Color>? barColors;

  @override
  Widget build(BuildContext context) {
    final fallback = AppColorTokens.of(context).primaryAccent;
    return _ExpandableBars(
      rows: rows,
      bar: (row, maxCount) {
        final index = rows.indexOf(row);
        final paint =
            barColors != null && index >= 0 && index < barColors!.length
                ? barColors![index]
                : fallback;
        return _BarRow(
          label: row.label,
          count: row.count,
          maxCount: maxCount,
          color: paint,
        );
      },
    );
  }
}

class _ExpandableBars extends StatefulWidget {
  const _ExpandableBars({required this.rows, required this.bar});

  final List<DeckNamedCount> rows;
  final Widget Function(DeckNamedCount row, int maxCount) bar;

  @override
  State<_ExpandableBars> createState() => _ExpandableBarsState();
}

class _ExpandableBarsState extends State<_ExpandableBars> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final maxCount = widget.rows.fold<int>(
      0,
      (max, row) => row.count > max ? row.count : max,
    );
    final hidden = widget.rows.length > _previewLimit;
    final shown =
        hidden && !_open
            ? widget.rows.take(_previewLimit).toList()
            : widget.rows;
    return Column(
      children: [
        for (var index = 0; index < shown.length; index++) ...[
          widget.bar(shown[index], maxCount),
          if (index != shown.length - 1) SizedBox(height: LayoutTokens.gr2),
        ],
        if (hidden) ...[
          SizedBox(height: LayoutTokens.gr1),
          _ShowRestButton(
            open: _open,
            onTap: () => setState(() => _open = !_open),
          ),
        ],
      ],
    );
  }
}

class _ShowRestButton extends StatelessWidget {
  const _ShowRestButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    final label = open ? l10n.deckStatsShowLess : l10n.deckStatsShowRest;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RadiusTokens.pill),
        child: SizedBox(
          height: 28,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                open
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: colors.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.count,
    required this.maxCount,
    required this.color,
    this.leading,
  });

  final String label;
  final int count;
  final int maxCount;
  final Color color;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final factor = maxCount == 0 ? 0.0 : count / maxCount;
    return Row(
      children: [
        if (leading != null) ...[
          leading!,
          SizedBox(width: LayoutTokens.gr2),
        ] else
          SizedBox(
            width: 112,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: FontTokens.caption,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Expanded(
          child: SizedBox(
            height: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.backgroundPrimary.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(RadiusTokens.pill),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: factor.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(RadiusTokens.pill),
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 0.72), color],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: FontTokens.caption,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

Color _manaColor(String letter) {
  return switch (letter) {
    'W' => const Color(0xFFE4C56A),
    'U' => const Color(0xFF1F7AB8),
    'B' => const Color(0xFF6E6E6E),
    'R' => const Color(0xFFD13B32),
    'G' => const Color(0xFF1F8A4C),
    _ => const Color(0xFFB0B0B0),
  };
}

Color _typeColor(DeckCardGroup group) {
  return switch (group) {
    DeckCardGroup.creature => _manaColor('G'),
    DeckCardGroup.instant => _manaColor('U'),
    DeckCardGroup.sorcery => _manaColor('R'),
    DeckCardGroup.artifact => const Color(0xFF8E8A9A),
    DeckCardGroup.enchantment => _manaColor('W'),
    DeckCardGroup.planeswalker => const Color(0xFF7A5AF5),
    DeckCardGroup.land => const Color(0xFF8A6A3B),
    DeckCardGroup.other => _manaColor('C'),
  };
}
