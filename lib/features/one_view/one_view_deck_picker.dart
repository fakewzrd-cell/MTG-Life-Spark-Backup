import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/one_view/one_view_state.dart';
import '../../core/persistence/providers.dart';
import '../../features/game/widgets/game_modal_chrome.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/deck_style_l10n.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';

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

  await showGameBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    builder: (ctx) {
      final colors = AppColorTokens.of(ctx);
      final l10n = AppLocalizations.of(ctx);
      return GameSheetBody(
        scrollable: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            GameSheetHeader(title: l10n.deckPickerTitle),
            SizedBox(height: LayoutTokens.gr2),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.clear_rounded, color: colors.textSecondary),
              title: Text(
                l10n.oneViewSkipDeck,
                style: TextStyle(color: colors.textPrimary),
              ),
              onTap: () {
                ref.read(oneViewProvider.notifier).clearDeck(seatIndex);
                Navigator.pop(ctx);
              },
            ),
            Divider(color: colors.borderSubtle, height: 1),
            if (decks.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: LayoutTokens.gr2),
                child: Text(
                  l10n.oneViewNoDecks,
                  style: TextStyle(color: colors.textSecondary),
                ),
              )
            else
              ...decks.map((deck) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.style, color: colors.primaryAccent),
                  title: Text(
                    deck.displayName,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (deck.deckStyle != null)
                        localizedDeckStyleName(l10n, deck.deckStyle!),
                      if (deck.commanderName.trim().isNotEmpty)
                        deck.commanderName,
                    ].join(' · '),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: FontTokens.caption,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    ref
                        .read(oneViewProvider.notifier)
                        .applyDeck(seatIndex: seatIndex, deck: deck);
                    Navigator.pop(ctx);
                  },
                );
              }),
          ],
        ),
      );
    },
  );
}
