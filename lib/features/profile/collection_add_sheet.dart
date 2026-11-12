import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug/app_log.dart';
import '../../core/deck/deck_list_text.dart';
import '../../core/game/scryfall_service.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/ui_app_bar.dart';
import '../../ui/components/ui_snack_bar.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/motion_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../game/widgets/game_modal_chrome.dart';
import 'album_listing.dart';

enum CollectionAddChoice { search, paste }

Future<CollectionAddChoice?> showCollectionAddSheet(
  BuildContext context, {
  String? searchBody,
  String? pasteBody,
}) {
  return showGameBottomSheet<CollectionAddChoice>(
    context: context,
    showDragHandle: true,
    builder:
        (context) =>
            _CollectionAddSheet(searchBody: searchBody, pasteBody: pasteBody),
  );
}

class _CollectionAddSheet extends StatelessWidget {
  const _CollectionAddSheet({this.searchBody, this.pasteBody});

  final String? searchBody;
  final String? pasteBody;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LayoutTokens.gr4,
          LayoutTokens.gr2,
          LayoutTokens.gr4,
          LayoutTokens.gr4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.search_rounded, color: colors.primaryAccent),
              title: Text(
                l10n.collectionAddSearch,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: FontTokens.body,
                ),
              ),
              subtitle: Text(
                searchBody ?? l10n.collectionAddSearchBody,
                style: TextStyle(color: colors.textSecondary),
              ),
              onTap: () => Navigator.pop(context, CollectionAddChoice.search),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.content_paste_outlined,
                color: colors.primaryAccent,
              ),
              title: Text(
                l10n.deckAlbumPaste,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: FontTokens.body,
                ),
              ),
              subtitle: Text(
                pasteBody ?? l10n.collectionAddPasteBody,
                style: TextStyle(color: colors.textSecondary),
              ),
              onTap: () => Navigator.pop(context, CollectionAddChoice.paste),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLine {
  _CartLine({required this.card, required this.count});

  final ScryfallCard card;
  int count;
}

class CollectionSearchPage extends ConsumerStatefulWidget {
  const CollectionSearchPage({
    super.key,
    required this.onAdd,
    this.rejectionFor,
    this.checkoutLabel,
  });

  final Future<int> Function(String name, int count) onAdd;

  /// When this returns a message, the card is not added and the message is shown.
  final String? Function(ScryfallCard card)? rejectionFor;

  /// Primary checkout label, e.g. Add to album / Add to deck.
  final String? checkoutLabel;

  @override
  ConsumerState<CollectionSearchPage> createState() =>
      _CollectionSearchPageState();
}

class _CollectionSearchPageState extends ConsumerState<CollectionSearchPage> {
  final _search = TextEditingController();
  final _cart = <String, _CartLine>{};
  Timer? _debounce;
  Timer? _pulseTimer;
  List<ScryfallCard> _results = const [];
  var _searching = false;
  String? _error;
  String? _pulseName;
  var _checkingOut = false;
  var _requestId = 0;
  var _listing = AlbumListing.grid;

  int get _cartCopies =>
      _cart.values.fold<int>(0, (sum, line) => sum + line.count);

  @override
  void dispose() {
    _debounce?.cancel();
    _pulseTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _searchCards(q));
  }

  Future<void> _searchCards(String query) async {
    final requestId = ++_requestId;
    try {
      final cards = await ref.read(scryfallServiceProvider).searchCards(query);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = cards.take(20).toList();
        _searching = false;
        _error =
            _results.isEmpty
                ? AppLocalizations.of(context).lookupNoResults(query)
                : null;
      });
    } catch (e, st) {
      appLog('Collection search failed', error: e, stackTrace: st);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = const [];
        _searching = false;
        _error = AppLocalizations.of(context).lookupNetworkError;
      });
    }
  }

  ScryfallCard? _sourceFor(String name) {
    final inCart = _cart[name]?.card;
    if (inCart != null) return inCart;
    for (final card in _results) {
      if (card.name == name) return card;
    }
    return null;
  }

  List<AlbumListCard> _albumCards() {
    return [
      for (final card in _results)
        AlbumListCard(
          name: card.name,
          count: _cart[card.name]?.count ?? 0,
          group: deckCardGroupForTypeLine(card.typeLine),
          imageUrl: scryfallDisplayCardUrl(card),
          backImageUrl: scryfallDisplayBackUrl(card),
          manaCost: card.manaCost,
          canAddCopy: (_cart[card.name]?.count ?? 0) < 99,
        ),
    ];
  }

  void _onListingTap(AlbumListCard card) {
    final source = _sourceFor(card.name);
    if (source == null) return;
    _addToCart(source);
  }

  void _onListingCount(AlbumListCard card, int delta) {
    if (delta > 0) {
      _onListingTap(card);
      return;
    }
    _setCount(card.name, card.count + delta);
  }

  void _pulse(String name) {
    _pulseTimer?.cancel();
    setState(() => _pulseName = name);
    _pulseTimer = Timer(MotionTokens.standard, () {
      if (!mounted) return;
      setState(() => _pulseName = null);
    });
  }

  void _addToCart(ScryfallCard card) {
    final rejection = widget.rejectionFor?.call(card);
    if (rejection != null) {
      showUiSnackBar(context, rejection, isError: true);
      return;
    }
    HapticFeedback.selectionClick();
    final line = _cart[card.name];
    if (line != null && line.count >= 99) return;
    setState(() {
      if (line == null) {
        _cart[card.name] = _CartLine(card: card, count: 1);
      } else {
        line.count += 1;
      }
    });
    _pulse(card.name);
  }

  void _setCount(String name, int count) {
    if (count < 1) {
      setState(() => _cart.remove(name));
      return;
    }
    final line = _cart[name];
    if (line == null) return;
    HapticFeedback.selectionClick();
    setState(() => line.count = count.clamp(1, 99));
    _pulse(name);
  }

  Future<void> _openCart() async {
    if (_cart.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    await showGameBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final lines = _cart.values.toList();
            final checkoutLabel =
                widget.checkoutLabel ?? l10n.collectionCartCheckoutAlbum;
            return SafeArea(
              child: Padding(
                padding: GameModalChrome.sheetPadding(ctx),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.collectionCartTitle,
                      style: GameModalChrome.sheetTitleStyle(ctx),
                    ),
                    SizedBox(height: LayoutTokens.gr2),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: lines.length,
                        separatorBuilder:
                            (_, __) => SizedBox(height: LayoutTokens.gr1),
                        itemBuilder: (context, index) {
                          final line = lines[index];
                          return _CartResultRow(
                            card: line.card,
                            count: line.count,
                            pulsing: _pulseName == line.card.name,
                            inset: false,
                            onAdd: () {
                              _addToCart(line.card);
                              setSheet(() {});
                            },
                            onRemove: () {
                              _setCount(line.card.name, line.count - 1);
                              setSheet(() {});
                              if (_cart.isEmpty && Navigator.of(ctx).canPop()) {
                                Navigator.pop(ctx);
                              }
                            },
                          );
                        },
                      ),
                    ),
                    SizedBox(height: LayoutTokens.gr2),
                    FilledButton(
                      onPressed:
                          _checkingOut
                              ? null
                              : () {
                                Navigator.pop(ctx);
                                _checkout();
                              },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: AppColorTokens.of(ctx).primaryAccent,
                        foregroundColor: AppColorTokens.of(ctx).onAccent,
                      ),
                      child: Text(checkoutLabel),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _checkout() async {
    if (_checkingOut || _cart.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _checkingOut = true);
    var total = 0;
    final remaining = <String, _CartLine>{};
    for (final line in _cart.values.toList()) {
      final added = await widget.onAdd(line.card.name, line.count);
      if (!mounted) return;
      if (added > 0) {
        total += added;
        if (added < line.count) {
          remaining[line.card.name] = _CartLine(
            card: line.card,
            count: line.count - added,
          );
        }
      } else {
        remaining[line.card.name] = line;
      }
    }
    if (!mounted) return;
    setState(() {
      _cart
        ..clear()
        ..addAll(remaining);
      _checkingOut = false;
    });
    if (total < 1) {
      showUiSnackBar(context, l10n.deckAlbumCannotAdd, isError: true);
      return;
    }
    if (remaining.isNotEmpty) {
      showUiSnackBar(context, l10n.collectionCartPartial(total), isError: true);
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context, total);
    }
  }

  Future<void> _onLeave() async {
    if (_cart.isNotEmpty) {
      final l10n = AppLocalizations.of(context);
      final leave = await showGameConfirmDialog(
        context: context,
        title: l10n.collectionCartDiscardTitle,
        message: l10n.collectionCartDiscardBody,
        confirmLabel: l10n.collectionCartLeave,
        destructive: true,
      );
      if (leave != true || !mounted) return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    final checkoutLabel =
        widget.checkoutLabel ?? l10n.collectionCartCheckoutAlbum;
    final cartOpen = _cart.isNotEmpty;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onLeave();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: UiAppBar(title: l10n.collectionSearchTitle),
        body: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    LayoutTokens.gr4,
                    LayoutTokens.gr2,
                    LayoutTokens.gr4,
                    LayoutTokens.gr2,
                  ),
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    onChanged: _onQuery,
                    decoration: InputDecoration(
                      hintText: l10n.collectionSearchHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                if (_searching) const LinearProgressIndicator(),
                if (_results.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      LayoutTokens.gr4,
                      0,
                      LayoutTokens.gr4,
                      LayoutTokens.gr2,
                    ),
                    child: AlbumListingSwitch(
                      listing: _listing,
                      onChanged: (value) => setState(() => _listing = value),
                    ),
                  ),
                Expanded(
                  child:
                      _error != null && _results.isEmpty
                          ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(LayoutTokens.gr4),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colors.textSecondary),
                              ),
                            ),
                          )
                          : ListView(
                            padding: EdgeInsets.fromLTRB(
                              LayoutTokens.gr4,
                              0,
                              LayoutTokens.gr4,
                              cartOpen
                                  ? BlurredBottomAction.height(context) +
                                      LayoutTokens.gr5
                                  : LayoutTokens.gr2,
                            ),
                            children: albumListingChildren(
                              context: context,
                              listing: _listing,
                              cards: _albumCards(),
                              onCount: _onListingCount,
                              onCardTap: _onListingTap,
                            ),
                          ),
                ),
              ],
            ),
            if (cartOpen)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: BlurredBottomAction(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Material(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(
                            RadiusTokens.lgIncreased,
                          ),
                          child: InkWell(
                            onTap: _openCart,
                            borderRadius: BorderRadius.circular(
                              RadiusTokens.lgIncreased,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: LayoutTokens.gr2,
                                vertical: LayoutTokens.gr2,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.style_outlined,
                                    color: colors.textPrimary,
                                  ),
                                  SizedBox(width: LayoutTokens.gr1),
                                  Expanded(
                                    child: Text(
                                      l10n.collectionCartLabel(_cartCopies),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: FontTokens.body,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: LayoutTokens.gr2),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          key: const Key('card-cart-checkout'),
                          onPressed: _checkingOut ? null : _checkout,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 52),
                            backgroundColor: colors.primaryAccent,
                            foregroundColor: colors.onAccent,
                          ),
                          child:
                              _checkingOut
                                  ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.onAccent,
                                    ),
                                  )
                                  : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(checkoutLabel),
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CartResultRow extends StatelessWidget {
  const _CartResultRow({
    required this.card,
    required this.count,
    required this.pulsing,
    required this.onAdd,
    this.onRemove,
    this.inset = true,
  });

  final ScryfallCard card;
  final int count;
  final bool pulsing;
  final VoidCallback onAdd;
  final VoidCallback? onRemove;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    final inCart = count > 0;
    final info = Row(
      children: [
        _CartThumb(url: scryfallDisplayCardUrl(card)),
        SizedBox(width: LayoutTokens.gr2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: FontTokens.body,
                ),
              ),
              if (card.typeLine != null && card.typeLine!.isNotEmpty)
                Text(
                  card.typeLine!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: FontTokens.sm,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    final stepper = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: l10n.collectionCartRemoveOne,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: onRemove,
          icon: const Icon(Icons.remove_rounded),
        ),
        AnimatedScale(
          scale: pulsing ? 1.18 : 1,
          duration: MotionTokens.fast,
          curve: MotionTokens.easeOut,
          child: SizedBox(
            width: 36,
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: FontTokens.title,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.collectionCartAddOne,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: inset ? LayoutTokens.gr4 : 0,
        vertical: LayoutTokens.gr1,
      ),
      child:
          inCart
              ? Row(
                children: [
                  Expanded(child: InkWell(onTap: onAdd, child: info)),
                  stepper,
                ],
              )
              : InkWell(
                onTap: onAdd,
                child: Row(
                  children: [
                    Expanded(child: info),
                    Icon(Icons.add_rounded, color: colors.textSecondary),
                  ],
                ),
              ),
    );
  }
}

class _CartThumb extends StatelessWidget {
  const _CartThumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(RadiusTokens.sm),
      child: SizedBox(
        width: 40,
        height: 56,
        child:
            url == null || url!.isEmpty
                ? ColoredBox(color: colors.surfaceElevated)
                : CachedNetworkImage(
                  imageUrl: url!,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  memCacheWidth: 80,
                  placeholder:
                      (_, __) => ColoredBox(color: colors.surfaceElevated),
                  errorWidget:
                      (_, __, ___) => ColoredBox(color: colors.surfaceElevated),
                ),
      ),
    );
  }
}
