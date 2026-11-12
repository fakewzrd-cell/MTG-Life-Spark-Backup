import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/ui_snack_bar.dart';

const kLifeSparkHelpEmail = 'lifespark.help@gmail.com';

/// Opens a mail draft to [kLifeSparkHelpEmail], or copies the address if none.
Future<void> openLifeSparkHelpMail({
  required BuildContext context,
  required String subject,
  String body = '',
}) async {
  final l10n = AppLocalizations.of(context);
  final encodedSubject = Uri.encodeComponent(subject);
  final encodedBody = Uri.encodeComponent(body);
  final uri = Uri.parse(
    body.isEmpty
        ? 'mailto:$kLifeSparkHelpEmail?subject=$encodedSubject'
        : 'mailto:$kLifeSparkHelpEmail?subject=$encodedSubject&body=$encodedBody',
  );

  try {
    if (await canLaunchUrl(uri)) {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!context.mounted) return;
      if (launched) {
        showUiSnackBar(context, l10n.feedbackOpeningMail);
        return;
      }
    }
  } catch (_) {}

  if (!context.mounted) return;
  final text = l10n.reportBugClipboardFallback(
    kLifeSparkHelpEmail,
    subject,
    body,
  );
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showUiSnackBar(context, l10n.feedbackNoMailAppCopied(kLifeSparkHelpEmail));
}
