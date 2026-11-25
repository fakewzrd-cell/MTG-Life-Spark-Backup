import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/game/scryfall_service.dart';
import '../../core/one_view/one_view_state.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import 'one_view_deck_picker.dart';
import 'one_view_chrome.dart';

/// Search a commander or any card and paint it on a One View seat.
///
/// Returns after the popup closes. Non-guest "Use a deck" opens the deck picker.
Future<void> showOneViewArtPicker(
  BuildContext context,
  WidgetRef ref,
  int seatIndex,
) async {
  final openDeck = await showOneViewDialog<bool>(
    context: context,
    builder: (ctx) => _ArtPickerSheet(seatIndex: seatIndex),
  );
  if (openDeck == true && context.mounted) {
    await showOneViewDeckPicker(context, ref, seatIndex);
  }
}

class _ArtPickerSheet extends ConsumerStatefulWidget {
  const _ArtPickerSheet({required this.seatIndex});

  final int seatIndex;

  @override
  ConsumerState<_ArtPickerSheet> createState() => _ArtPickerSheetState();
}

class _ArtPickerSheetState extends ConsumerState<_ArtPickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ScryfallCard> _results = [];
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _searchCards(query),
    );
  }

  Future<void> _searchCards(String query) async {
    final l10n = AppLocalizations.of(context);
    final trimmed = query.trim();
    final request = ++_request;
    if (trimmed.length < 2) {
      setState(() {
        _results = [];
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cards = await ref
          .read(scryfallServiceProvider)
          .searchCardPreviews(trimmed);
      if (!mounted || request != _request) return;
      setState(() {
        _results = cards;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _results = [];
        _loading = false;
        _error = l10n.oneViewCardArtFailed;
      });
    }
  }

  void _apply(ScryfallCard card) {
    final url = card.imageUrl ?? card.cardFaceUrl;
    if (url == null || url.isEmpty) return;
    ref
        .read(oneViewProvider.notifier)
        .setCommanderVisual(
          seatIndex: widget.seatIndex,
          name: card.name,
          imageUrl: url,
          colorIdentity: card.colorIdentity,
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final seat = ref.watch(
      oneViewProvider.select((s) => s.seats[widget.seatIndex]),
    );
    final hasArt =
        seat.commanderImageUrl != null && seat.commanderImageUrl!.isNotEmpty;

    final available =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        MediaQuery.viewPaddingOf(context).vertical;
    final resultsHeight = math.min(280.0, math.max(64.0, available * 0.32));
    return OneViewMenuDialog(
      title: l10n.oneViewCardArt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('one-view-art-search'),
            controller: _search,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.oneViewCardArtSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon:
                  _loading
                      ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                      : null,
            ),
            onChanged: _onChanged,
            onSubmitted: _searchCards,
          ),
          const SizedBox(height: 16),
          SizedBox(height: resultsHeight, child: _resultsBody(colors, l10n)),
          if (hasArt && _search.text.trim().isEmpty)
            OneViewMenuAction(
              icon: Icons.image_outlined,
              leading: OneViewPortrait(url: seat.commanderImageUrl, size: 36),
              label: seat.commanderName ?? l10n.oneViewCurrentArt,
              subtitle: l10n.oneViewCurrentArt,
              selected: true,
              onTap: null,
            ),
          if (!seat.isGuest || hasArt)
            Divider(color: colors.borderSubtle, height: 24),
          if (!seat.isGuest)
            OneViewMenuAction(
              icon: Icons.style,
              label: l10n.oneViewCardArtUseDeck,
              onTap: () => Navigator.pop(context, true),
            ),
          if (hasArt)
            OneViewMenuAction(
              icon: Icons.hide_image_outlined,
              label: l10n.oneViewCardArtRemove,
              color: colors.error,
              onTap: () {
                ref
                    .read(oneViewProvider.notifier)
                    .clearCommanderVisual(widget.seatIndex);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _resultsBody(AppColorTokens colors, AppLocalizations l10n) {
    if (_results.isEmpty) {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      final message =
          _error ??
          (_search.text.trim().length < 2
              ? l10n.oneViewCardArtEmpty
              : l10n.oneViewCardArtNone);
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          message,
          style: OneViewChrome.dialogBodyStyle(
            context,
          ).copyWith(color: _error == null ? null : colors.error),
        ),
      );
    }

    final cacheW = (36 * MediaQuery.devicePixelRatioOf(context)).round();
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemExtent: 64,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final card = _results[index];
        final thumb = scryfallListThumbUrl(card.imageUrl ?? card.cardFaceUrl);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: ClipRRect(
            borderRadius: RadiusTokens.radiusSm,
            child: SizedBox(
              width: 36,
              height: 50,
              child:
                  thumb == null
                      ? ColoredBox(color: colors.backgroundSecondary)
                      : CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        memCacheWidth: cacheW,
                        fadeInDuration: Duration.zero,
                        placeholder:
                            (_, __) =>
                                ColoredBox(color: colors.backgroundSecondary),
                        errorWidget:
                            (_, __, ___) =>
                                ColoredBox(color: colors.backgroundSecondary),
                      ),
            ),
          ),
          title: Text(
            card.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OneViewChrome.menuLabelStyle(context),
          ),
          trailing:
              ref.read(oneViewProvider).seats[widget.seatIndex].commanderName ==
                      card.name
                  ? Icon(Icons.check_rounded, color: colors.primaryAccent)
                  : null,
          onTap: () => _apply(card),
        );
      },
    );
  }
}
