import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug/app_log.dart';
import '../../core/persistence/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/theme/theme_provider.dart';
import '../../ui/components/shell_destructive_dialog.dart';
import '../../ui/components/ui_snack_bar.dart';

/// Pick a backup file, confirm, restore, and refresh profile/settings/decks.
///
/// Returns true when a backup was applied. Cancelled picks return false.
Future<bool> restoreLifeSparkBackup({
  required BuildContext context,
  required WidgetRef ref,
  String logTag = 'Backup',
}) async {
  final l10n = AppLocalizations.of(context);
  try {
    final pending = await ref
        .read(backupServiceProvider)
        .pickBackupFile(fileTypeLabel: l10n.backupFileTypeLabel);
    if (!context.mounted || pending == null) return false;

    final confirmed = await showShellDestructiveConfirm(
      context: context,
      title: l10n.backupRestoreTitle(pending.profile.username),
      message: l10n.backupRestoreMessage,
      confirmLabel: l10n.backupRestoreConfirm,
      cancelLabel: l10n.commonCancel,
    );
    if (!confirmed || !context.mounted) return false;

    final backup = await ref.read(backupServiceProvider).restoreBackup(pending);
    if (!context.mounted) return false;

    ref.read(colorSchemePreferenceProvider.notifier).hydrateFromRepository();
    bumpSettingsRevision(ref);
    bumpProfileRevision(ref);
    bumpDeckListRevision(ref);
    showUiSnackBar(context, l10n.backupRestored(backup.profile.username));
    return true;
  } catch (e, st) {
    appLog('$logTag: restore backup failed', error: e, stackTrace: st);
    if (!context.mounted) return false;
    showUiSnackBar(context, localizeBackupError(l10n, e), isError: true);
    return false;
  }
}

String localizeBackupError(AppLocalizations l10n, Object error) {
  if (error is FormatException) {
    switch (error.message) {
      case 'Not a Life Spark backup file.':
        return l10n.backupNotValidFile;
      case 'Backup file is not valid JSON.':
        return l10n.backupNotValidJson;
      case 'Could not read the selected backup file.':
        return l10n.backupCouldNotRead;
    }
  }
  return l10n.backupRestoreFailed;
}
