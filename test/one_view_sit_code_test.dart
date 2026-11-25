import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/one_view/one_view_sit_code.dart';

void main() {
  test('sit code round-trips player id, name, and avatar', () {
    final raw = OneViewSitCode.build(
      playerId: 'pid-1',
      username: 'Wizard',
      avatarUrl: 'https://example.com/a.png',
    );
    expect(raw.startsWith(OneViewSitCode.schemePrefix), isTrue);
    final parsed = OneViewSitCode.parse(raw);
    expect(parsed, isNotNull);
    expect(parsed!.playerId, 'pid-1');
    expect(parsed.username, 'Wizard');
    expect(parsed.avatarUrl, 'https://example.com/a.png');
  });

  test('sit code parse rejects host join payloads', () {
    expect(OneViewSitCode.parse('https://example.com/join?t=abc'), isNull);
    expect(OneViewSitCode.parse('not-a-code'), isNull);
  });
}
