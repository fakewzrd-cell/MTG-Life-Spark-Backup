import '../models/match_record.dart';
import '../persistence/match_repository.dart';
import '../persistence/profile_repository.dart';
import 'one_view_xp_claim.dart';
import 'one_view_xp_claim_repository.dart';

enum OneViewXpClaimStatus {
  applied,
  alreadyClaimed,
  wrongProfile,
  noProfile,
  failed,
}

class OneViewXpClaimResult {
  const OneViewXpClaimResult({
    required this.status,
    this.xpGained = 0,
    this.leveledUp = false,
    this.newLevel,
  });

  final OneViewXpClaimStatus status;
  final int xpGained;
  final bool leveledUp;
  final int? newLevel;
}

/// Applies a scanned One View XP claim QR on this device.
class OneViewXpClaimService {
  OneViewXpClaimService({
    required ProfileRepository profileRepo,
    required MatchRepository matchRepo,
    required OneViewXpClaimRepository claimRepo,
  }) : _profileRepo = profileRepo,
       _matchRepo = matchRepo,
       _claimRepo = claimRepo;

  final ProfileRepository _profileRepo;
  final MatchRepository _matchRepo;
  final OneViewXpClaimRepository _claimRepo;

  Future<OneViewXpClaimResult> apply(OneViewXpClaimData claim) async {
    await _claimRepo.init();
    final profile = _profileRepo.getProfile();
    if (profile == null) {
      return const OneViewXpClaimResult(status: OneViewXpClaimStatus.noProfile);
    }
    if (profile.playerId != claim.playerId) {
      return const OneViewXpClaimResult(
        status: OneViewXpClaimStatus.wrongProfile,
      );
    }
    if (_claimRepo.hasClaimed(claim.claimKey)) {
      return const OneViewXpClaimResult(
        status: OneViewXpClaimStatus.alreadyClaimed,
      );
    }

    final won = claim.won;
    final isFirstWin = won && profile.totalWins == 0;
    final xp = OneViewXpClaim.xpForClaim(
      won: won,
      isFirstWin: isFirstWin,
      playerCount: claim.playerCount,
    );
    if (xp <= 0) {
      await _claimRepo.markClaimed(claim.claimKey);
      return const OneViewXpClaimResult(
        status: OneViewXpClaimStatus.applied,
        xpGained: 0,
      );
    }

    try {
      if (!_matchRepo.hasMatch(claim.matchId)) {
        await _matchRepo.saveMatch(
          MatchRecord(
            matchId: claim.matchId,
            date: DateTime.now(),
            commanderName:
                (claim.commanderName != null && claim.commanderName!.isNotEmpty)
                    ? claim.commanderName!
                    : 'Unknown',
            opponentNames: claim.opponentNames,
            result: won ? 'win' : 'loss',
            eliminationReason: won ? 'survived' : 'survived',
            format: claim.format,
            durationMinutes: claim.durationSeconds ~/ 60,
            startingLifeTotal: claim.startingLife,
            playerCount: claim.playerCount,
            durationSeconds: claim.durationSeconds,
          ),
        );
      }

      final oldLevel = profile.level;
      await _profileRepo.recordMatchResult(
        commanderName:
            (claim.commanderName != null && claim.commanderName!.isNotEmpty)
                ? claim.commanderName!
                : 'Unknown',
        won: won,
        xpGained: xp,
      );
      await _claimRepo.markClaimed(claim.claimKey);

      final updated = _profileRepo.getProfile();
      return OneViewXpClaimResult(
        status: OneViewXpClaimStatus.applied,
        xpGained: xp,
        leveledUp: (updated?.level ?? oldLevel) > oldLevel,
        newLevel: updated?.level,
      );
    } catch (_) {
      return const OneViewXpClaimResult(status: OneViewXpClaimStatus.failed);
    }
  }
}
