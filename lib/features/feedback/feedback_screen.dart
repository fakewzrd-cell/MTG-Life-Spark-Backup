import 'package:flutter/material.dart';

import '../../core/play/play_review.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/ui_app_bar.dart';
import '../../ui/components/ui_button.dart';
import '../../ui/components/ui_text_field.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import 'life_spark_help_mail.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, this.review});

  /// Test seam. Production uses [PlayReview] against Play / App Store.
  final PlayReview? review;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _messageController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendFeedback() async {
    final msg = _messageController.text.trim();
    if (msg.isEmpty) return;

    final l10n = AppLocalizations.of(context);
    setState(() => _sending = true);
    await openLifeSparkHelpMail(
      context: context,
      subject: l10n.feedbackMailSubject,
      body: msg,
    );
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _openPlayStore() async {
    await (widget.review ?? PlayReview()).requestOrOpenStore();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: UiAppBar(title: l10n.feedbackTitle),
      backgroundColor: colors.backgroundPrimary,
      body: ListView(
        padding: LayoutTokens.shellListPadding(context, top: LayoutTokens.gr4),
        children: [
          const Center(child: Text('🛡️', style: TextStyle(fontSize: 48))),
          SizedBox(height: LayoutTokens.gr4),
          Text(
            l10n.feedbackHeadline,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontSize: MediaQuery.sizeOf(context).width < 360 ? 22 : 26,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: LayoutTokens.gr1),
          Text(
            l10n.feedbackBody,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: LayoutTokens.gr5),
          UiTextField(
            controller: _messageController,
            labelText: l10n.feedbackMessageLabel,
            hintText: l10n.feedbackMessageHint,
            maxLines: 6,
            maxLength: 500,
          ),
          SizedBox(height: LayoutTokens.gr4),
          UiButton(
            label: l10n.feedbackSend,
            icon: _sending ? null : Icon(Icons.send_outlined, size: 20),
            loading: _sending,
            onPressed: _sendFeedback,
          ),
          SizedBox(height: LayoutTokens.gr5),
          Row(
            children: [
              Expanded(child: Divider(color: colors.borderSubtle)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: LayoutTokens.gr2),
                child: Text(
                  l10n.feedbackOrDivider,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Expanded(child: Divider(color: colors.borderSubtle)),
            ],
          ),
          SizedBox(height: LayoutTokens.gr4),
          UiButton(
            key: const ValueKey('feedback-rate-play'),
            label: l10n.feedbackRatePlayStore,
            variant: UiButtonVariant.secondary,
            icon: Icon(Icons.star_outline, size: 20),
            onPressed: _openPlayStore,
          ),
        ],
      ),
    );
  }
}
