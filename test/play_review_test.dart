import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/play/play_review.dart';

class _FakePlatform implements PlayReviewPlatform {
  _FakePlatform({this.available = true, this.throwOnRequest = false});

  bool available;
  bool throwOnRequest;
  var requestCount = 0;
  var openListingCount = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async {
    if (throwOnRequest) throw StateError('unavailable');
    requestCount++;
  }

  @override
  Future<void> openStoreListing() async {
    openListingCount++;
  }
}

void main() {
  test(
    'requestOrOpenStore shows the in-app sheet when Play allows it',
    () async {
      final platform = _FakePlatform();
      var launched = 0;
      final review = PlayReview(
        platform: platform,
        launch: (_) async {
          launched++;
          return true;
        },
      );

      await review.requestOrOpenStore();

      expect(platform.requestCount, 1);
      expect(platform.openListingCount, 0);
      expect(launched, 0);
    },
  );

  test(
    'requestOrOpenStore opens the listing when the sheet is unavailable',
    () async {
      final platform = _FakePlatform(available: false);
      final review = PlayReview(platform: platform);

      await review.requestOrOpenStore();

      expect(platform.requestCount, 0);
      expect(platform.openListingCount, 1);
    },
  );

  test('requestOrOpenStore opens the listing when requestReview throws',
      () async {
    final platform = _FakePlatform(throwOnRequest: true);
    final review = PlayReview(platform: platform);

    await review.requestOrOpenStore();

    expect(platform.requestCount, 0);
    expect(platform.openListingCount, 1);
  });

  test('requestInAppOnly does not leave the app', () async {
    final platform = _FakePlatform(available: false);
    var launched = 0;
    final review = PlayReview(
      platform: platform,
      launch: (_) async {
        launched++;
        return true;
      },
    );

    await review.requestInAppOnly();

    expect(platform.requestCount, 0);
    expect(platform.openListingCount, 0);
    expect(launched, 0);
  });
}
