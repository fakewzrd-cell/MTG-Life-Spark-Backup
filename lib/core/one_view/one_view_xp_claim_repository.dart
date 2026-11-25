import 'package:hive_flutter/hive_flutter.dart';

/// Dedupes claimed One View XP handoffs on this device (`matchId:playerId`).
class OneViewXpClaimRepository {
  static const _boxName = 'oneViewXpClaims';

  Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<String>(_boxName);
    }
  }

  Box<String> get _box => Hive.box<String>(_boxName);

  bool hasClaimed(String claimKey) => _box.containsKey(claimKey);

  Future<void> markClaimed(String claimKey) async {
    await _box.put(claimKey, claimKey);
  }
}
