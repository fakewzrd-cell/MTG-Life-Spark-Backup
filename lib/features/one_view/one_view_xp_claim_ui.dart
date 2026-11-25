import 'package:flutter/material.dart';

import 'one_view_qr_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/one_view/one_view_state.dart';
import '../../core/one_view/one_view_xp_claim.dart';
import '../../core/one_view/one_view_xp_claim_service.dart';
import '../../core/persistence/providers.dart';
import '../../features/game/widgets/game_modal_chrome.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import 'one_view_chrome.dart';

/// Host phone: show claim QRs for each sit-code seat after end-table.
Future<void> showOneViewXpClaimHandoffSheet({
  required BuildContext context,
  required List<({OneViewSeat seat, String payload})> claims,
}) async {
  if (claims.isEmpty) return;
  await showGameBottomSheet<void>(
    context: context,
    builder: (ctx) => _XpClaimHandoffBody(claims: claims),
  );
}

class _XpClaimHandoffBody extends StatefulWidget {
  const _XpClaimHandoffBody({required this.claims});

  final List<({OneViewSeat seat, String payload})> claims;

  @override
  State<_XpClaimHandoffBody> createState() => _XpClaimHandoffBodyState();
}

class _XpClaimHandoffBodyState extends State<_XpClaimHandoffBody> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final item = widget.claims[_index];
    final isLast = _index >= widget.claims.length - 1;

    return GameSheetBody(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GameSheetHeader(title: l10n.oneViewXpClaimTitle),
          SizedBox(height: LayoutTokens.gr2),
          Text(
            l10n.oneViewXpClaimBody,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary),
          ),
          SizedBox(height: LayoutTokens.gr2),
          AnimatedSwitcher(
            duration:
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
            child: Column(
              key: ValueKey(item.payload),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.oneViewXpClaimFor(item.seat.displayName),
                  textAlign: TextAlign.center,
                  style: OneViewChrome.dialogTitleStyle(context),
                ),
                if (widget.claims.length > 1) ...[
                  SizedBox(height: LayoutTokens.gr1),
                  Text(
                    l10n.oneViewXpClaimStep(_index + 1, widget.claims.length),
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ],
                SizedBox(height: LayoutTokens.gr3),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: RadiusTokens.radiusXl,
                  ),
                  child: QrImageView(
                    data: item.payload,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: LayoutTokens.gr3),
          Row(
            children: [
              if (_index > 0)
                IconButton(
                  onPressed: () => setState(() => _index -= 1),
                  tooltip:
                      MaterialLocalizations.of(context).previousPageTooltip,
                  icon: const Icon(Icons.chevron_left_rounded),
                )
              else
                const SizedBox(width: 48),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  if (isLast) {
                    Navigator.pop(context);
                  } else {
                    setState(() => _index += 1);
                  }
                },
                child: Text(
                  isLast ? l10n.oneViewXpClaimDone : l10n.oneViewXpClaimNext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Profile → Claim One View XP: scan a handoff QR and apply XP.
Future<void> showOneViewXpClaimScanner(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = AppLocalizations.of(context);
  final raw = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder:
          (_) => OneViewQrScanner<String>(
            title: l10n.oneViewClaimXpScanTitle,
            hint: l10n.oneViewScanXpHint,
            invalidMessage: l10n.oneViewClaimXpInvalid,
            parse: (raw) => OneViewXpClaim.parse(raw) == null ? null : raw,
          ),
    ),
  );
  if (raw == null || !context.mounted) return;

  final claim = OneViewXpClaim.parse(raw);
  if (claim == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.oneViewClaimXpInvalid)));
    return;
  }

  final result = await ref.read(oneViewXpClaimServiceProvider).apply(claim);
  bumpProfileRevision(ref);
  if (!context.mounted) return;

  final message = switch (result.status) {
    OneViewXpClaimStatus.applied => l10n.oneViewClaimXpApplied(result.xpGained),
    OneViewXpClaimStatus.alreadyClaimed => l10n.oneViewClaimXpAlready,
    OneViewXpClaimStatus.wrongProfile => l10n.oneViewClaimXpWrongProfile,
    OneViewXpClaimStatus.noProfile => l10n.hostCreateProfileFirst,
    OneViewXpClaimStatus.failed => l10n.oneViewClaimXpFailed,
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
