import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

import '../debug/app_log.dart';

/// Play Store listing used when the in-app review sheet is unavailable.
final playStoreListingUri = Uri.parse(
  'https://play.google.com/store/apps/details?id=app.lifespark.mtg',
);

/// Native review APIs. Production uses [InAppReview].
abstract class PlayReviewPlatform {
  Future<bool> isAvailable();
  Future<void> requestReview();
  Future<void> openStoreListing();
}

class InAppReviewPlatformBridge implements PlayReviewPlatform {
  InAppReviewPlatformBridge([InAppReview? review])
    : _review = review ?? InAppReview.instance;

  final InAppReview _review;

  @override
  Future<bool> isAvailable() => _review.isAvailable();

  @override
  Future<void> requestReview() => _review.requestReview();

  @override
  Future<void> openStoreListing() => _review.openStoreListing();
}

/// Google Play / App Store review sheet, with a listing fallback.
class PlayReview {
  PlayReview({PlayReviewPlatform? platform, UriLauncher? launch})
    : _platform = platform ?? InAppReviewPlatformBridge(),
      _launch = launch ?? _launchExternal;

  final PlayReviewPlatform _platform;
  final UriLauncher _launch;

  /// Shows the native review sheet when Play/App Store allows it.
  ///
  /// If the sheet cannot be shown (quota, sideload, web), opens the Play
  /// listing so the player can still rate.
  Future<void> requestOrOpenStore() async {
    if (await _tryInApp()) return;
    await openStoreListing();
  }

  /// Native sheet only. Does not leave the app if Play declines to show it.
  Future<void> requestInAppOnly() async {
    await _tryInApp();
  }

  Future<bool> _tryInApp() async {
    try {
      if (!await _platform.isAvailable()) return false;
      await _platform.requestReview();
      return true;
    } catch (e, st) {
      appLog('Play in-app review failed', error: e, stackTrace: st);
      return false;
    }
  }

  Future<void> openStoreListing() async {
    try {
      await _platform.openStoreListing();
      return;
    } catch (e, st) {
      appLog('Play store listing via plugin failed', error: e, stackTrace: st);
    }
    try {
      await _launch(playStoreListingUri);
    } catch (e, st) {
      appLog('Play store listing URL failed', error: e, stackTrace: st);
    }
  }
}

typedef UriLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchExternal(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

final playReviewProvider = Provider<PlayReview>((ref) => PlayReview());
