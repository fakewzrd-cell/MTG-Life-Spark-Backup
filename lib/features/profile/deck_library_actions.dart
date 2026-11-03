import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/game/game_format.dart';
import '../../core/models/player_deck.dart';
import '../../core/persistence/deck_repository.dart';
import '../../core/persistence/providers.dart';
import '../../shared/utils/app_router.dart';
import 'deck_options_sheet.dart';
import 'deck_style_picker_sheet.dart';
import 'game_format_picker_sheet.dart';

/// Runs one action from the deck detail sheet.
///
/// Returns true when the deck was deleted.
Future<bool> applyDeckSheetAction({
  required BuildContext context,
  required WidgetRef ref,
  required DeckRepository repo,
  required PlayerDeck deck,
  required DeckSheetAction action,
}) async {
  switch (action) {
    case DeckSheetAction.pasteList:
    case DeckSheetAction.copyList:
      return false;
    case DeckSheetAction.changeFormat:
      final picked = await showGameFormatPickerSheet(
        context,
        selected: deck.gameFormat,
      );
      if (picked == null || picked == deck.gameFormat || !context.mounted) {
        return false;
      }
      final wasCommander = deck.isCommanderDeck;
      deck.format = picked.name;
      if (wasCommander && !picked.isCommanderStyle) {
        deck.partnerCommanderName = null;
        deck.partnerCommanderImageUrl = null;
        deck.partnerManaCost = null;
      }
      await repo.save(deck);
      bumpDeckListRevision(ref);
      return false;
    case DeckSheetAction.changeStyle:
      final picked = await showDeckStylePickerSheet(
        context,
        selected: deck.deckStyle,
      );
      if (picked == null || picked.id == deck.deckStyleId) return false;
      deck.deckStyleId = picked.id;
      await repo.save(deck);
      bumpDeckListRevision(ref);
      return false;
    case DeckSheetAction.editCover:
      if (!deck.hasDeckStyle) {
        final picked = await showDeckStylePickerSheet(context);
        if (picked == null || !context.mounted) return false;
        deck.deckStyleId = picked.id;
        await repo.save(deck);
        bumpDeckListRevision(ref);
      }
      if (!context.mounted) return false;
      final profile = ref.read(profileRepositoryProvider).getProfile();
      if (profile == null) return false;
      await context.push(
        AppRoutes.commanderSelect,
        extra: {
          'playerId': profile.playerId,
          'editDeckId': deck.id,
          'deckFormat': deck.format,
        },
      );
      bumpDeckListRevision(ref);
      return false;
    case DeckSheetAction.rename:
      final name = await showRenameDeckDialog(
        context,
        initialName: deck.displayName,
      );
      if (name == null || name == deck.displayName || !context.mounted) {
        return false;
      }
      deck.displayName = name;
      await repo.save(deck);
      bumpDeckListRevision(ref);
      return false;
    case DeckSheetAction.duplicate:
      await repo.duplicate(deck);
      bumpDeckListRevision(ref);
      return false;
    case DeckSheetAction.delete:
      final ok = await showDeleteDeckConfirm(context, deck);
      if (!ok || !context.mounted) return false;
      await repo.delete(deck.id);
      bumpDeckListRevision(ref);
      return true;
  }
}
