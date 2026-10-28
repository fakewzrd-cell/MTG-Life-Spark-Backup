import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/theme/app_color_tokens.dart';
import '../../core/network/session_providers.dart';
import '../../core/game/game_providers.dart';
import '../../core/game/game_state.dart';
import '../../core/game/lobby_state.dart';
import '../../core/game/player_game_state.dart';
import '../../core/game/progression_service.dart';
import '../../core/game/session_exit_helpers.dart';
import '../../shared/widgets/game_icon.dart';
import '../../core/persistence/providers.dart';
import '../../core/debug/app_log.dart';
import '../../core/models/game_feedback.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/app_router.dart';
import '../../shared/utils/wizard_rank_titles.dart';
import '../../shared/widgets/block_system_app_exit.dart';
import '../../shared/widgets/player_feedback_widgets.dart';
import '../../ui/components/ui_button.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/opacity_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../../ui/tokens/typography_tokens.dart';

class EndGameScreen extends ConsumerStatefulWidget {
  const EndGameScreen({super.key});

  @override
  ConsumerState<EndGameScreen> createState() => _EndGameScreenState();
}

class _EndGameScreenState extends ConsumerState<EndGameScreen> {
  bool _saved = false;
  bool _saveFailed = false;
  ProgressResult? _result;
  bool _saving = true;
  bool _feedbackSubmitted = false;
  final Set<String> _likePlayerIds = {};
  final Set<String> _dislikePlayerIds = {};
  String? _starPlayerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFirstFrame());
  }

  void _onFirstFrame() {
    final game = ref.read(gameProvider);
    if (!game.gameOver) {
      if (!mounted) return;
      // Align with router safety net: stale /end-game → home.
      context.go(AppRoutes.home);
      return;
    }
    _saveMatch();
  }

  Future<void> _saveMatch() async {
    if (_saved) return;

    final game = ref.read(gameProvider);
    if (!game.gameOver) {
      if (mounted) context.go(AppRoutes.home);
      return;
    }

    setState(() {
      _saving = true;
      _saveFailed = false;
    });

    final pending = ref.read(pendingFeedbackProvider);
    final submittedFromForfeit = pending?.hasContent ?? false;
    if (submittedFromForfeit && mounted) {
      setState(() => _feedbackSubmitted = true);
    }

    try {
      final lobby = ref.read(lobbyProvider);
      final service = ref.read(progressionServiceProvider);

      final stableMatchId = stableMatchIdForGame(game);

      final result = await service.recordMatch(
        finalState: game,
        lobbyState: lobby,
        startTime: game.gameStartTime ?? DateTime.now(),
        matchId: stableMatchId,
      );

      if (submittedFromForfeit && result.matchId.isNotEmpty) {
        final feedback = GameFeedback(
          matchId: result.matchId,
          voterPlayerId: game.localPlayerId,
          likePlayerIds: pending!.likePlayerIds,
          dislikePlayerIds: pending.dislikePlayerIds,
          starPlayerId: pending.starPlayerId,
        );
        await service.saveFeedback(feedback);
        ref.read(gameProvider.notifier).broadcastMatchFeedback(feedback);
        ref.read(pendingFeedbackProvider.notifier).state = null;
      }

      bumpProfileRevision(ref);
      bumpDeckListRevision(ref);
      _saved = true;

      if (mounted) {
        setState(() {
          _result = result;
          _saving = false;
          _feedbackSubmitted = submittedFromForfeit;
        });
      }
    } catch (e, st) {
      appLog('EndGameScreen._saveMatch failed', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final game = ref.watch(gameProvider);
    final winner =
        game.winnerPlayerId != null
            ? game.playerById(game.winnerPlayerId!)
            : null;
    final isWinner = winner?.playerId == game.localPlayerId;
    final profile = ref.read(profileRepositoryProvider).getProfile();
    final (int, int)? xpProgress =
        profile != null && (_result?.awardsProgression ?? false)
            ? ref.read(profileRepositoryProvider).computeXpProgress(profile.xp)
            : null;

    return BlockSystemAppExit(
      child: Scaffold(
        backgroundColor: colors.backgroundPrimary,
        body: SafeArea(
          child:
              _saving
                  ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: colors.primaryAccent),
                        SizedBox(height: LayoutTokens.gr3),
                        Text(
                          l10n.endGameSavingResults,
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  )
                  : _saveFailed
                  ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(LayoutTokens.gr4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: colors.primaryAccent,
                            size: 48,
                          ),
                          SizedBox(height: LayoutTokens.gr3),
                          Text(
                            l10n.endGameSaveFailedTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: LayoutTokens.gr2),
                          Text(
                            l10n.endGameSaveFailedBody,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textSecondary),
                          ),
                          SizedBox(height: LayoutTokens.gr4),
                          UiButton(
                            label: l10n.endGameRetry,
                            onPressed: _saveMatch,
                          ),
                          SizedBox(height: LayoutTokens.gr2),
                          UiButton(
                            label: l10n.endGameContinueWithoutSaving,
                            variant: UiButtonVariant.secondary,
                            onPressed: () => _leaveToHome(context),
                          ),
                        ],
                      ),
                    ),
                  )
                  : SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: LayoutTokens.gr4),

                        _MatchPoster(
                          winner: winner,
                          isLocalWinner: isWinner,
                          noWinnerHeadline: _noWinnerHeadline(game, l10n),
                          result: _result,
                          xpInLevel: xpProgress?.$1,
                          xpNeeded: xpProgress?.$2,
                        ),

                        SizedBox(height: LayoutTokens.gr4),

                        // ── Post-game feedback sits under the poster ──────────
                        if (_result != null && _result!.matchId.isNotEmpty)
                          _FeedbackCard(
                            game: game,
                            feedbackSubmitted: _feedbackSubmitted,
                            likePlayerIds: _likePlayerIds,
                            dislikePlayerIds: _dislikePlayerIds,
                            starPlayerId: _starPlayerId,
                            onLike:
                                (pid) => setState(() {
                                  togglePlayerLike(
                                    likeIds: _likePlayerIds,
                                    dislikeIds: _dislikePlayerIds,
                                    playerId: pid,
                                    apply: (likes, dislikes) {
                                      _likePlayerIds
                                        ..clear()
                                        ..addAll(likes);
                                      _dislikePlayerIds
                                        ..clear()
                                        ..addAll(dislikes);
                                    },
                                  );
                                }),
                            onDislike:
                                (pid) => setState(() {
                                  togglePlayerDislike(
                                    likeIds: _likePlayerIds,
                                    dislikeIds: _dislikePlayerIds,
                                    playerId: pid,
                                    apply: (likes, dislikes) {
                                      _likePlayerIds
                                        ..clear()
                                        ..addAll(likes);
                                      _dislikePlayerIds
                                        ..clear()
                                        ..addAll(dislikes);
                                    },
                                  );
                                }),
                            onStarChanged:
                                (pid) => setState(() => _starPlayerId = pid),
                            onSubmit: () => _submitFeedback(game),
                          ),

                        SizedBox(height: LayoutTokens.gr4),

                        // ── Final standings ────────────────────────────────────
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: LayoutTokens.shellPageInset,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.endGameFinalStandings,
                                style: TypographyTokens.sectionTitle(
                                  colors.textSecondary,
                                ).copyWith(
                                  fontSize: FontTokens.label,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1,
                                ),
                              ),
                              SizedBox(height: LayoutTokens.gr1),
                              ...game.players.map(
                                (p) => _FinalPlayerRow(
                                  p: p,
                                  isWinner: p.playerId == game.winnerPlayerId,
                                  isLocal: p.playerId == game.localPlayerId,
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: LayoutTokens.gr5),

                        // ── Actions ────────────────────────────────────────────
                        _ActionButtons(onHome: () => _leaveToHome(context)),

                        SizedBox(height: LayoutTokens.gr5),
                      ],
                    ),
                  ),
        ),
      ),
    );
  }

  Future<void> _leaveToHome(BuildContext context) async {
    // Navigate away first while gameOver is still true. Clearing state before
    // go(home) rebuilds this route empty and fights the /end-game redirect.
    if (context.mounted) context.go(AppRoutes.home);
    await quitActiveGame(ref);
  }

  Future<void> _submitFeedback(GameState game) async {
    if (_result == null || _result!.matchId.isEmpty) return;
    final feedback = GameFeedback(
      matchId: _result!.matchId,
      voterPlayerId: game.localPlayerId,
      likePlayerIds: _likePlayerIds.toList(),
      dislikePlayerIds: _dislikePlayerIds.toList(),
      starPlayerId: _starPlayerId,
    );
    await ref.read(progressionServiceProvider).saveFeedback(feedback);
    ref.read(gameProvider.notifier).broadcastMatchFeedback(feedback);
    bumpProfileRevision(ref);
    if (mounted) setState(() => _feedbackSubmitted = true);
  }
}

String _noWinnerHeadline(GameState game, AppLocalizations l10n) {
  if (game.winnerPlayerId != null) return l10n.endGameOverNoWinner;
  final local = game.localPlayer;
  if (game.players.length == 1 && local?.eliminationReason == 'concede') {
    return l10n.endGamePracticeEnded;
  }
  return l10n.endGameOverNoWinner;
}

// ── Match poster ─────────────────────────────────────────────────────────────

class _MatchPoster extends StatelessWidget {
  final PlayerGameState? winner;
  final bool isLocalWinner;
  final String noWinnerHeadline;
  final ProgressResult? result;
  final int? xpInLevel;
  final int? xpNeeded;

  const _MatchPoster({
    required this.winner,
    required this.isLocalWinner,
    required this.noWinnerHeadline,
    required this.result,
    required this.xpInLevel,
    required this.xpNeeded,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final seat = winner;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: LayoutTokens.shellPageInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: RadiusTokens.radiusXl,
        ),
        child: ClipRRect(
          borderRadius: RadiusTokens.radiusXl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PosterArt(
                winner: seat,
                fallback: colors.backgroundSecondary,
                fade: colors.surface,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  LayoutTokens.gr3,
                  LayoutTokens.gr3,
                  LayoutTokens.gr3,
                  LayoutTokens.gr4,
                ),
                child: Column(
                  children: [
                    Text(
                      seat == null
                          ? noWinnerHeadline
                          : (isLocalWinner
                              ? l10n.endGameYouWin
                              : l10n.endGameWinner),
                      textAlign: TextAlign.center,
                      style: TypographyTokens.headline(context).copyWith(
                        color:
                            seat == null ? colors.textPrimary : colors.emphasis,
                      ),
                    ),
                    if (seat != null) ...[
                      SizedBox(height: LayoutTokens.gr1),
                      Text(
                        seat.username,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: seat.playerColor,
                          fontSize: FontTokens.headline,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (seat.commanderName != null)
                        Text(
                          seat.commanderName!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: FontTokens.hudSm,
                          ),
                        ),
                    ],
                    if (result != null &&
                        result!.awardsProgression &&
                        xpInLevel != null &&
                        xpNeeded != null &&
                        xpNeeded! > 0) ...[
                      SizedBox(height: LayoutTokens.gr3),
                      _RankBar(
                        result: result!,
                        xpInLevel: xpInLevel!,
                        xpNeeded: xpNeeded!,
                        isWinner: isLocalWinner,
                      ),
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

class _PosterArt extends StatelessWidget {
  const _PosterArt({
    required this.winner,
    required this.fallback,
    required this.fade,
  });

  final PlayerGameState? winner;
  final Color fallback;
  final Color fade;

  @override
  Widget build(BuildContext context) {
    final seat = winner;
    final url = seat?.commanderImageUrl;
    final hasArt = url != null && url.isNotEmpty;

    return SizedBox(
      height: 220,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasArt)
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorWidget: (_, __, ___) => ColoredBox(color: fallback),
            )
          else
            ColoredBox(color: seat?.playerColor ?? fallback),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [fade.withValues(alpha: 0), fade],
                stops: const [0.42, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankBar extends StatelessWidget {
  const _RankBar({
    required this.result,
    required this.xpInLevel,
    required this.xpNeeded,
    required this.isWinner,
  });

  final ProgressResult result;
  final int xpInLevel;
  final int xpNeeded;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final fraction = (xpInLevel / xpNeeded).clamp(0.0, 1.0);
    final rank = wizardRankTitle(l10n, result.newLevel);
    final oldRank = wizardRankTitle(l10n, result.oldLevel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.endGameRankLevel(result.newLevel),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: FontTokens.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              rank,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: FontTokens.hudXs,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SizedBox(height: LayoutTokens.gr1),
        ClipRRect(
          borderRadius: RadiusTokens.radiusPill,
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: colors.backgroundSecondary,
            color: colors.emphasis,
          ),
        ),
        SizedBox(height: LayoutTokens.gr1),
        Text(
          l10n.endGameXpGained(result.xpGained),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.emphasis,
            fontSize: FontTokens.hudSm,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          isWinner ? l10n.endGameWinBonusIncluded : l10n.endGameParticipationXp,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: FontTokens.hudXs,
          ),
        ),
        if (result.leveledUp) ...[
          SizedBox(height: LayoutTokens.gr1),
          Text(
            oldRank == rank
                ? l10n.endGameRankTransition(result.oldLevel, result.newLevel)
                : '$oldRank → $rank',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: FontTokens.hudSm,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Feedback Card ─────────────────────────────────────────────────────────────

class _FeedbackCard extends StatelessWidget {
  final GameState game;
  final bool feedbackSubmitted;
  final Set<String> likePlayerIds;
  final Set<String> dislikePlayerIds;
  final String? starPlayerId;
  final void Function(String) onLike;
  final void Function(String) onDislike;
  final void Function(String?) onStarChanged;
  final VoidCallback onSubmit;

  const _FeedbackCard({
    required this.game,
    required this.feedbackSubmitted,
    required this.likePlayerIds,
    required this.dislikePlayerIds,
    required this.starPlayerId,
    required this.onLike,
    required this.onDislike,
    required this.onStarChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final others =
        game.players.where((p) => p.playerId != game.localPlayerId).toList();

    if (feedbackSubmitted) {
      return Container(
        margin: EdgeInsets.symmetric(horizontal: LayoutTokens.shellPageInset),
        padding: EdgeInsets.all(LayoutTokens.gr3),
        decoration: BoxDecoration(
          color: colors.success.withValues(alpha: 0.15),
          borderRadius: RadiusTokens.radiusXl,
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: colors.success, size: 28),
            SizedBox(width: LayoutTokens.gr2),
            Expanded(
              child: Text(
                l10n.endGameFeedbackThanks,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: FontTokens.hudSm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: LayoutTokens.shellPageInset),
      padding: EdgeInsets.all(LayoutTokens.gr3),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: RadiusTokens.radiusXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.endGameRateOpponents,
            style: TypographyTokens.sectionTitle(colors.textPrimary),
          ),
          PlayerFeedbackFields(
            opponents: others,
            likePlayerIds: likePlayerIds,
            dislikePlayerIds: dislikePlayerIds,
            onLike: onLike,
            onDislike: onDislike,
            starPlayerId: starPlayerId,
            onStarChanged: onStarChanged,
            voteSpacing: LayoutTokens.gr1,
          ),
          SizedBox(height: LayoutTokens.gr3),
          UiButton(label: l10n.endGameSubmitFeedback, onPressed: onSubmit),
        ],
      ),
    );
  }
}

// ── Final Player Row ──────────────────────────────────────────────────────────

class _FinalPlayerRow extends StatelessWidget {
  final PlayerGameState p;
  final bool isWinner;
  final bool isLocal;

  const _FinalPlayerRow({
    required this.p,
    required this.isWinner,
    required this.isLocal,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: LayoutTokens.gr1),
      padding: EdgeInsets.symmetric(
        horizontal: LayoutTokens.gr2,
        vertical: LayoutTokens.gr2,
      ),
      decoration: BoxDecoration(
        color:
            isWinner
                ? colors.emphasis.withValues(alpha: OpacityTokens.subtle)
                : colors.surface,
        borderRadius: RadiusTokens.radiusXl,
      ),
      child: Row(
        children: [
          if (isWinner)
            Padding(
              padding: EdgeInsets.only(right: LayoutTokens.gr1),
              child: GameIcon.monarch(
                size: FontTokens.sm,
                color: colors.emphasis,
              ),
            ),
          Container(
            width: LayoutTokens.gr1,
            height: LayoutTokens.gr1,
            decoration: BoxDecoration(
              color: p.playerColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: LayoutTokens.gr1),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    p.username,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: isLocal ? FontWeight.bold : FontWeight.normal,
                      fontSize: FontTokens.hudSm,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isLocal)
                  Text(
                    ' ${l10n.endGameYouSuffix}',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: FontTokens.sm,
                    ),
                  ),
              ],
            ),
          ),
          if (p.commanderName != null)
            Flexible(
              child: Text(
                p.commanderName!,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: FontTokens.sm,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          SizedBox(width: LayoutTokens.gr1),
          Text(
            p.isEliminated
                ? _reasonLabel(l10n, p.eliminationReason)
                : '${p.life} ❤',
            style: TextStyle(
              color: p.isEliminated ? colors.primaryAccent : colors.textPrimary,
              fontSize: FontTokens.sm,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _reasonLabel(AppLocalizations l10n, String? r) {
    switch (r) {
      case 'life':
        return l10n.endGameElimReasonLife;
      case 'poison':
        return l10n.endGameElimReasonPoison;
      case 'commanderDamage':
        return l10n.endGameElimReasonCommanderDmg;
      case 'concede':
        return l10n.endGameElimReasonConcede;
      case 'disconnect':
        return l10n.endGameElimReasonDisconnect;
      default:
        return l10n.endGameElimReasonDefault;
    }
  }
}

// ── Action Buttons ────────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  final VoidCallback onHome;

  const _ActionButtons({required this.onHome});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: LayoutTokens.ctaHorizontal),
      child: UiButton(
        label: l10n.endGameBackToHome,
        variant: UiButtonVariant.secondary,
        icon: const Icon(Icons.home_outlined, size: 20),
        onPressed: onHome,
      ),
    );
  }
}
