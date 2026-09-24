import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/game/scryfall_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/game_haptics.dart';
import '../../../shared/widgets/mana_cost_pips.dart';
import '../../../ui/theme/app_color_tokens.dart';
import '../../../ui/tokens/font_tokens.dart';
import '../../../ui/tokens/layout_tokens.dart';
import '../../../ui/tokens/opacity_tokens.dart';
import '../../../ui/tokens/radius_tokens.dart';
import 'game_colors.dart';
import 'game_modal_chrome.dart';

/// Cards opened in Lookup during this match. Cleared when a game screen starts.
class CardLookupSessionNotifier extends Notifier<List<ScryfallCard>> {
  static const int maxRecents = 8;

  @override
  List<ScryfallCard> build() => const [];

  void clear() => state = const [];

  void remember(ScryfallCard card) {
    final key = card.name.toLowerCase();
    final rest = state.where((c) => c.name.toLowerCase() != key);
    state = [card, ...rest].take(maxRecents).toList();
  }
}

final cardLookupSessionProvider =
    NotifierProvider<CardLookupSessionNotifier, List<ScryfallCard>>(
      CardLookupSessionNotifier.new,
    );

/// Lookup section: recent cards, or search, then rules in the same tab.
class CardLookupTab extends ConsumerStatefulWidget {
  const CardLookupTab({super.key});

  @override
  ConsumerState<CardLookupTab> createState() => _CardLookupTabState();
}

class _CardLookupTabState extends ConsumerState<CardLookupTab> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  List<ScryfallCard> _results = [];
  bool _searching = false;
  bool _networkError = false;
  bool _truncated = false;
  String? _error;
  int _searchRequestId = 0;

  static const int _resultCap = 20;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
        _networkError = false;
        _truncated = false;
        _searching = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
        _networkError = false;
        _truncated = false;
        _searching = false;
      });
      return;
    }
    final requestId = ++_searchRequestId;
    setState(() {
      _searching = true;
      _error = null;
      _networkError = false;
      _truncated = false;
    });
    try {
      final cards = await ref.read(scryfallServiceProvider).searchCards(q);
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _truncated = cards.length > _resultCap;
        _results = cards.take(_resultCap).toList();
        _searching = false;
        if (_results.isEmpty) {
          _error = AppLocalizations.of(context).lookupNoResults(q);
        }
      });
    } catch (e, st) {
      appLog('CardLookup: Scryfall search failed', error: e, stackTrace: st);
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searching = false;
        _results = [];
        _truncated = false;
        _networkError = true;
        _error = AppLocalizations.of(context).lookupNetworkError;
      });
    }
  }

  Future<void> _openCard(ScryfallCard card) async {
    context.gameHapticSelection();
    _searchFocus.unfocus();
    ref.read(cardLookupSessionProvider.notifier).remember(card);
    await showGameBottomSheet<void>(
      context: context,
      builder: (_) => _CardDetailSheet(card: card),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recents = ref.watch(cardLookupSessionProvider);
    return _ListView(
      controller: _searchController,
      focusNode: _searchFocus,
      searching: _searching,
      results: _results,
      recents: recents,
      error: _error,
      networkError: _networkError,
      truncated: _truncated,
      onQueryChanged: _onQueryChanged,
      onClear: () {
        _searchController.clear();
        setState(() {});
        _onQueryChanged('');
      },
      onRetry: () => _search(_searchController.text),
      onOpen: _openCard,
    );
  }
}

class _ListView extends StatelessWidget {
  const _ListView({
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.results,
    required this.recents,
    required this.error,
    required this.networkError,
    required this.truncated,
    required this.onQueryChanged,
    required this.onClear,
    required this.onRetry,
    required this.onOpen,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;
  final List<ScryfallCard> results;
  final List<ScryfallCard> recents;
  final String? error;
  final bool networkError;
  final bool truncated;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final VoidCallback onRetry;
  final ValueChanged<ScryfallCard> onOpen;

  bool get _searchingQuery => controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final l10n = AppLocalizations.of(context);
    final cards = _searchingQuery ? results : recents;

    // The game bar already sits under this list. Padding by the full keyboard
    // height lifts the search field by that bar as well, which leaves a blank
    // band between the field and the keyboard.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    var lift = 0.0;
    final box = context.findRenderObject();
    if (keyboard > 0 && box is RenderBox && box.hasSize && box.attached) {
      final screenBottom = MediaQuery.sizeOf(context).height;
      final widgetBottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      final overlap = widgetBottom - (screenBottom - keyboard);
      if (overlap > 0) lift = overlap;
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        LayoutTokens.shellPageInset,
        LayoutTokens.gr2,
        LayoutTokens.shellPageInset,
        lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: l10n.lookupHint,
              prefixIcon: Icon(
                Icons.search_rounded,
                color: colors.textSecondary,
              ),
              suffixIcon:
                  searching
                      ? const Padding(
                        padding: EdgeInsets.all(LayoutTokens.gr2),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                      : (controller.text.isNotEmpty
                          ? IconButton(
                            tooltip: l10n.lookupClearTooltip,
                            onPressed: onClear,
                            icon: Icon(
                              Icons.clear_rounded,
                              color: colors.textSecondary,
                            ),
                          )
                          : null),
            ),
          ),
          if (truncated) ...[
            SizedBox(height: LayoutTokens.gr1),
            Text(
              l10n.lookupFirstMatches(results.length),
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: FontTokens.caption,
                height: 1.3,
              ),
            ),
          ],
          SizedBox(height: LayoutTokens.gr2),
          Expanded(child: _body(context, colors, l10n, cards)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppColorTokens colors,
    AppLocalizations l10n,
    List<ScryfallCard> cards,
  ) {
    if (error != null && results.isEmpty && _searchingQuery) {
      return ListView(
        children: [
          Text(
            error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: networkError ? colors.error : colors.textSecondary,
              fontSize: FontTokens.hudSm,
              height: 1.4,
            ),
          ),
          if (networkError) ...[
            SizedBox(height: LayoutTokens.gr2),
            Center(
              child: TextButton(
                onPressed: onRetry,
                child: Text(l10n.commonTryAgain),
              ),
            ),
          ],
        ],
      );
    }
    if (cards.isEmpty && !searching) {
      return Center(
        child: Text(
          _searchingQuery ? l10n.lookupEmptyPrompt : l10n.lookupRecentEmpty,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: FontTokens.body,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(bottom: LayoutTokens.gr3),
      itemCount: cards.length,
      separatorBuilder: (_, __) => SizedBox(height: LayoutTokens.gr1),
      itemBuilder: (context, i) => _CardRow(card: cards[i], onTap: onOpen),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.card, required this.onTap});

  final ScryfallCard card;
  final ValueChanged<ScryfallCard> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final url = card.imageUrl;
    return Material(
      color: colors.surface,
      borderRadius: RadiusTokens.radiusXl,
      child: InkWell(
        onTap: () => onTap(card),
        borderRadius: RadiusTokens.radiusXl,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LayoutTokens.gr2,
            vertical: LayoutTokens.gr1,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: RadiusTokens.radiusLgIncreased,
                child: SizedBox(
                  width: 40,
                  height: 56,
                  child:
                      url != null && url.isNotEmpty
                          ? CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder:
                                (_, __) => ColoredBox(
                                  color: colors.backgroundSecondary,
                                ),
                            errorWidget:
                                (_, __, ___) => ColoredBox(
                                  color: colors.backgroundSecondary,
                                  child: Icon(
                                    Icons.style_outlined,
                                    color: colors.textSecondary,
                                    size: 20,
                                  ),
                                ),
                          )
                          : ColoredBox(
                            color: colors.backgroundSecondary,
                            child: Icon(
                              Icons.style_outlined,
                              color: colors.textSecondary,
                              size: 20,
                            ),
                          ),
                ),
              ),
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
                        height: 1,
                      ),
                    ),
                    if (card.manaCost != null &&
                        card.manaCost!.trim().isNotEmpty) ...[
                      SizedBox(height: LayoutTokens.gr0),
                      ManaCostPips(manaCost: card.manaCost, symbolHeight: 14),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardDetailSheet extends ConsumerStatefulWidget {
  const _CardDetailSheet({required this.card});

  final ScryfallCard card;

  @override
  ConsumerState<_CardDetailSheet> createState() => _CardDetailSheetState();
}

class _CardDetailSheetState extends ConsumerState<_CardDetailSheet> {
  late ScryfallCard _card = widget.card;
  List<ScryfallRuling> _rulings = const [];
  bool _loading = true;
  bool _rulingsFailed = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _rulingsFailed = false;
    });
    final service = ref.read(scryfallServiceProvider);
    final fresh = await service.fetchCardByName(_card.name) ?? _card;
    final rulings = await service.fetchRulings(fresh.id);
    if (!mounted) return;
    ref.read(cardLookupSessionProvider.notifier).remember(fresh);
    setState(() {
      _card = fresh;
      _rulingsFailed = rulings == null;
      _rulings = rulings ?? const [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final l10n = AppLocalizations.of(context);
    final card = _card;
    final oracle = card.oracleText?.trim();

    return GameSheetBody(
      scrollable: true,
      scrollController: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameSheetHeader(title: card.name),
          SizedBox(height: LayoutTokens.gr2),
          if (card.imageUrl != null && card.imageUrl!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: RadiusTokens.radiusXl,
              child: AspectRatio(
                aspectRatio: 63 / 44,
                child: CachedNetworkImage(
                  imageUrl: card.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder:
                      (_, __) => ColoredBox(color: colors.backgroundSecondary),
                  errorWidget:
                      (_, __, ___) => ColoredBox(
                        color: colors.backgroundSecondary,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: colors.textSecondary,
                        ),
                      ),
                ),
              ),
            ),
            SizedBox(height: LayoutTokens.gr2),
          ],
          if (card.typeLine != null && card.typeLine!.isNotEmpty)
            Text(
              card.typeLine!,
              style: TextStyle(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: FontTokens.hudSm,
              ),
            ),
          if (card.manaCost != null && card.manaCost!.trim().isNotEmpty) ...[
            SizedBox(height: LayoutTokens.gr1),
            Align(
              alignment: Alignment.centerLeft,
              child: ManaCostPips(manaCost: card.manaCost),
            ),
          ],
          SizedBox(height: LayoutTokens.gr3),
          Text(
            l10n.lookupOracleText,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: FontTokens.hudSm,
            ),
          ),
          SizedBox(height: LayoutTokens.gr1),
          if (oracle == null || oracle.isEmpty)
            Text(
              l10n.lookupNoOracle,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: FontTokens.hudSm,
                height: 1.4,
              ),
            )
          else
            Text(
              oracle,
              style: TextStyle(
                color: colors.textPrimary.withValues(alpha: 0.92),
                fontSize: FontTokens.hudSm,
                height: 1.45,
              ),
            ),
          SizedBox(height: LayoutTokens.gr3),
          Text(
            l10n.lookupRulings,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: FontTokens.hudSm,
            ),
          ),
          SizedBox(height: LayoutTokens.gr1),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: LayoutTokens.gr3),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_rulingsFailed)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.lookupRulingsError,
                  style: TextStyle(
                    color: colors.error,
                    fontSize: FontTokens.hudSm,
                    height: 1.4,
                  ),
                ),
                TextButton(
                  onPressed: _load,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, LayoutTokens.minTapTarget),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(l10n.commonTryAgain),
                ),
              ],
            )
          else if (_rulings.isEmpty)
            Text(
              l10n.lookupNoRulings,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: FontTokens.hudSm,
                height: 1.4,
              ),
            )
          else
            for (var i = 0; i < _rulings.length; i++) ...[
              if (i > 0) SizedBox(height: LayoutTokens.gr2),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.backgroundSecondary.withValues(
                    alpha: OpacityTokens.soft,
                  ),
                  borderRadius: RadiusTokens.radiusXl,
                ),
                child: Padding(
                  padding: EdgeInsets.all(LayoutTokens.gr2),
                  child: Text(
                    _rulings[i].comment,
                    style: TextStyle(
                      color: colors.textPrimary.withValues(alpha: 0.9),
                      fontSize: FontTokens.hudSm,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}
