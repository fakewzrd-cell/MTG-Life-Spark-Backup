import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../ui/theme/app_color_tokens.dart';
import '../../shared/utils/profile_avatar_storage.dart';
import '../game/widgets/game_modal_chrome.dart';

/// Typography and transitions scoped to the shared-phone flow.
abstract final class OneViewChrome {
  static TextStyle dialogTitleStyle(BuildContext context) =>
      GameModalChrome.dialogTitleStyle(context).copyWith(fontSize: 24);
  static TextStyle menuLabelStyle(BuildContext context, {Color? color}) =>
      GameModalChrome.menuLabelStyle(
        context,
        color: color,
      ).copyWith(fontSize: 16, fontWeight: FontWeight.w500, height: 1.3);
  static TextStyle dialogBodyStyle(BuildContext context) =>
      GameModalChrome.dialogBodyStyle(
        context,
      ).copyWith(fontSize: 14, height: 1.4);
  static TextStyle menuSectionStyle(BuildContext context) =>
      GameModalChrome.menuSectionStyle(context).copyWith(fontSize: 14);
}

Future<T?> showOneViewDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  animationStyle: AnimationStyle(
    duration:
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
    reverseDuration:
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
  ),
  builder: builder,
);

class OneViewMenuDialog extends StatelessWidget {
  const OneViewMenuDialog({
    super.key,
    this.title,
    this.titleWidget,
    required this.child,
    this.maxWidth,
    this.expandBody = false,
  });
  final String? title;
  final Widget? titleWidget;
  final Widget child;
  final double? maxWidth;
  final bool expandBody;

  @override
  Widget build(BuildContext context) => GameMenuDialog(
    titleWidget:
        titleWidget ??
        Text(title!, style: OneViewChrome.dialogTitleStyle(context)),
    maxWidth: maxWidth,
    headerLeadingInset: 16,
    expandBody: expandBody,
    child: child,
  );
}

class OneViewMenuAction extends StatelessWidget {
  const OneViewMenuAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.detail,
    this.color,
    this.enabled = true,
    this.leading,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? subtitle;
  final String? detail;
  final Color? color;
  final bool enabled;
  final Widget? leading;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final ink = enabled ? color ?? colors.textPrimary : colors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment:
                  subtitle == null
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
              children: [
                leading ??
                    Icon(
                      icon,
                      size: 22,
                      color:
                          enabled
                              ? color ?? colors.primaryAccent
                              : colors.textMuted,
                    ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: OneViewChrome.menuLabelStyle(
                          context,
                          color: ink,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: OneViewChrome.dialogBodyStyle(context),
                        ),
                      ],
                      if (detail != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          detail!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: OneViewChrome.dialogBodyStyle(context),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_rounded,
                    size: 22,
                    color: colors.primaryAccent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small portrait used in deck, counter, and winner lists.
class OneViewPortrait extends StatelessWidget {
  const OneViewPortrait({super.key, this.url, this.size = 32});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final fallback = ColoredBox(
      color: colors.backgroundSecondary,
      child: Center(
        child: Icon(
          Icons.person_outline_rounded,
          size: size * 0.6,
          color: colors.textSecondary,
        ),
      ),
    );
    final local = url == null ? null : localFileFromRef(url!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child:
            url == null || url!.isEmpty
                ? fallback
                : local != null
                ? Image.file(
                  local,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallback,
                )
                : CachedNetworkImage(
                  imageUrl: url!,
                  fit: BoxFit.cover,
                  memCacheWidth: (size * 3).round(),
                  fadeInDuration: Duration.zero,
                  placeholder: (_, __) => fallback,
                  errorWidget: (_, __, ___) => fallback,
                ),
      ),
    );
  }
}

class OneViewFormDialog extends StatelessWidget {
  const OneViewFormDialog({
    super.key,
    required this.title,
    required this.content,
    required this.submitLabel,
    required this.onSubmit,
    this.enabled = true,
  });
  final String title;
  final Widget content;
  final String submitLabel;
  final VoidCallback? onSubmit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          headlineMedium: OneViewChrome.dialogTitleStyle(context),
        ),
      ),
      child: GameFormDialog(
        title: title,
        content: content,
        submitLabel: submitLabel,
        onSubmit: onSubmit,
        enabled: enabled,
      ),
    );
  }
}
