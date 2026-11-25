import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/one_view/one_view_state.dart';
import '../../core/persistence/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/deck_style_l10n.dart';
import '../../ui/theme/app_color_tokens.dart';
import 'one_view_chrome.dart';

/// Pick a registered deck for a One View seat (guests skip this).
Future<void> showOneViewDeckPicker(
  BuildContext context,
  WidgetRef ref,
  int seatIndex,
) async {
  final format = ref.read(oneViewProvider).config.format;
  final allForFormat =
      ref
          .read(deckRepositoryProvider)
          .getAll()
          .where((d) => d.matchesLobbyFormat(format))
          .toList();
  final decks = allForFormat.where((d) => d.hasDeckStyle).toList();

  await showOneViewDialog<void>(
    context: context,
    builder: (ctx) {
      final colors = AppColorTokens.of(ctx);
      final l10n = AppLocalizations.of(ctx);
      return OneViewMenuDialog(
        title: l10n.deckPickerTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (decks.isEmpty)
              Text(
                l10n.oneViewNoDecks,
                style: OneViewChrome.dialogBodyStyle(ctx),
              )
            else
              for (final deck in decks)
                OneViewMenuAction(
                  icon: Icons.style,
                  leading: OneViewPortrait(
                    url: deck.commanderImageUrl,
                    size: 40,
                  ),
                  selected:
                      ref
                          .read(oneViewProvider)
                          .seats[seatIndex]
                          .selectedDeckId ==
                      deck.id,
                  label: deck.displayName,
                  subtitle: () {
                    final detail = [
                      if (deck.deckStyle != null)
                        localizedDeckStyleName(l10n, deck.deckStyle!),
                      if (deck.commanderName.trim().isNotEmpty)
                        deck.commanderName,
                    ].join(' · ');
                    return detail.isEmpty ? null : detail;
                  }(),
                  onTap: () {
                    ref
                        .read(oneViewProvider.notifier)
                        .applyDeck(seatIndex: seatIndex, deck: deck);
                    Navigator.pop(ctx);
                  },
                ),
            if (allForFormat.length > decks.length)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  l10n.oneViewDeckStyleMissing,
                  style: OneViewChrome.dialogBodyStyle(ctx),
                ),
              ),
            Divider(color: colors.borderSubtle, height: 24),
            OneViewMenuAction(
              icon: Icons.clear_rounded,
              label: l10n.oneViewSkipDeck,
              color: colors.textSecondary,
              onTap: () {
                ref.read(oneViewProvider.notifier).clearDeck(seatIndex);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      );
    },
  );
}
