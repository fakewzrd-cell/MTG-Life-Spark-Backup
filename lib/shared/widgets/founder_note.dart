import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';

/// Grateful note from the maker — Welcome and Settings → About.
class FounderNote extends StatelessWidget {
  const FounderNote({super.key, this.includeTitle = true});

  final bool includeTitle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
      fontSize: FontTokens.body,
      height: 1.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (includeTitle) ...[
          Text(
            l10n.founderNoteTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          SizedBox(height: LayoutTokens.gr3),
        ],
        Text(l10n.founderNoteP1, style: bodyStyle),
        SizedBox(height: LayoutTokens.gr3),
        Text(l10n.founderNoteP2, style: bodyStyle),
        SizedBox(height: LayoutTokens.gr3),
        Text(l10n.founderNoteP3, style: bodyStyle),
        SizedBox(height: LayoutTokens.gr3),
        Text(
          l10n.founderNoteSignoff,
          style: bodyStyle?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
