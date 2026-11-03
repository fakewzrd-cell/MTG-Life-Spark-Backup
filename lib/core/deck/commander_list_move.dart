import 'bracket_names.dart';

/// How the main deck changes when the command zone changes.
///
/// A card that becomes the commander leaves the list. A commander that steps
/// down goes back into the list. Cards that stay in the command zone do not move.
class CommanderListMove {
  const CommanderListMove({
    required this.removeFromMain,
    required this.addToMain,
  });

  final List<String> removeFromMain;
  final List<String> addToMain;
}

CommanderListMove planCommanderListMove({
  required String oldCommander,
  String? oldPartner,
  required String newCommander,
  String? newPartner,
}) {
  final oldNames = _zoneNames(oldCommander, oldPartner);
  final newNames = _zoneNames(newCommander, newPartner);
  bool stayed(String name) => oldNames.any((old) => _same(old, name));
  bool remains(String name) => newNames.any((next) => _same(next, name));
  return CommanderListMove(
    removeFromMain: [
      for (final name in newNames)
        if (!stayed(name)) name,
    ],
    addToMain: [
      for (final name in oldNames)
        if (!remains(name)) name,
    ],
  );
}

List<String> _zoneNames(String primary, String? partner) {
  final names = <String>[];
  final first = primary.trim();
  if (first.isNotEmpty) names.add(first);
  final second = partner?.trim() ?? '';
  if (second.isNotEmpty && !names.any((name) => _same(name, second))) {
    names.add(second);
  }
  return names;
}

bool _same(String a, String b) => bracketNameKey(a) == bracketNameKey(b);
