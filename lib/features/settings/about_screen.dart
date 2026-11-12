import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/founder_note.dart';
import '../../ui/components/ui_app_bar.dart';
import '../../ui/components/ui_button.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../feedback/life_spark_help_mail.dart';
import '../profile/album_listing.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final actionHeight = BlurredBottomAction.height(
      context,
      aboveShellDock: true,
    );
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: UiAppBar(title: l10n.settingsAbout),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(
              LayoutTokens.shellPageInset,
              LayoutTokens.gr4,
              LayoutTokens.shellPageInset,
              actionHeight,
            ),
            children: const [
              Center(
                child: BrandLogo(layout: BrandLogoLayout.vertical, height: 72),
              ),
              SizedBox(height: LayoutTokens.gr4),
              FounderNote(),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BlurredBottomAction(
              aboveShellDock: true,
              child: UiButton(
                key: const ValueKey('about-report-bug'),
                label: l10n.settingsReportBug,
                variant: UiButtonVariant.secondary,
                icon: const Icon(Icons.bug_report_outlined, size: 20),
                onPressed:
                    () => openLifeSparkHelpMail(
                      context: context,
                      subject: l10n.reportBugMailSubject,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
