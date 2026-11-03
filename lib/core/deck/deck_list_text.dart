import '../models/deck_card_entry.dart';

/// Album sections, in display order.
enum DeckCardGroup {
  creature,
  instant,
  sorcery,
  artifact,
  enchantment,
  planeswalker,
  land,
  other,
}

/// One parsed line before it is stored.
class ParsedDeckCard {
  const ParsedDeckCard({
    required this.name,
    required this.count,
    required this.board,
  });

  final String name;
  final int count;
  final DeckBoard board;
}

class DeckListParseResult {
  const DeckListParseResult({required this.cards, required this.skippedLines});

  final List<ParsedDeckCard> cards;
  final int skippedLines;

  int get totalCards => cards.fold<int>(0, (sum, card) => sum + card.count);
}

/// Groups a Scryfall type line into an album section.
///
/// Lands win over other types so an artifact land stays with lands.
DeckCardGroup deckCardGroupForTypeLine(String? typeLine) {
  final line = typeLine?.toLowerCase() ?? '';
  if (line.isEmpty) return DeckCardGroup.other;
  bool has(String type) => RegExp('\\b$type\\b').hasMatch(line);
  if (has('land')) return DeckCardGroup.land;
  if (has('planeswalker')) return DeckCardGroup.planeswalker;
  if (has('creature')) return DeckCardGroup.creature;
  if (has('instant')) return DeckCardGroup.instant;
  if (has('sorcery')) return DeckCardGroup.sorcery;
  if (has('enchantment')) return DeckCardGroup.enchantment;
  if (has('artifact')) return DeckCardGroup.artifact;
  return DeckCardGroup.other;
}

/// Reads a pasted list.
///
/// A line is `1 Sol Ring` or `1x Sol Ring`. A blank line splits sections.
/// For a Commander deck, lines that match the commander or partner are the
/// cover, not extra cards, and a sideboard heading is ignored. A `Sideboard`
/// heading starts the sideboard on a constructed list.
DeckListParseResult parseDeckList(
  String raw, {
  String? commanderName,
  String? partnerName,
  bool identifyCommander = false,
}) {
  final commanderKeys = <String>{};
  if (identifyCommander) {
    final commander = _normalizeName(commanderName);
    final partner = _normalizeName(partnerName);
    if (commander.isNotEmpty) commanderKeys.add(commander);
    if (partner.isNotEmpty) commanderKeys.add(partner);
  }

  final blocks = _blocks(raw);
  if (blocks.isEmpty) {
    return const DeckListParseResult(cards: [], skippedLines: 0);
  }

  final merged = <String, ParsedDeckCard>{};
  var skipped = 0;

  for (final block in blocks) {
    var board = DeckBoard.main;
    for (final line in block) {
      if (_isSideboardHeading(line)) {
        board = identifyCommander ? DeckBoard.main : DeckBoard.sideboard;
        continue;
      }
      if (_isIgnorableHeading(line)) continue;
      final parsed = _parseLine(line);
      if (parsed == null) {
        skipped++;
        continue;
      }
      if (board == DeckBoard.main && commanderKeys.contains(parsed.key)) {
        continue;
      }
      final existing = merged[parsed.mergeKey(board)];
      if (existing == null) {
        merged[parsed.mergeKey(board)] = ParsedDeckCard(
          name: parsed.name,
          count: parsed.count,
          board: board,
        );
      } else {
        merged[parsed.mergeKey(board)] = ParsedDeckCard(
          name: existing.name,
          count: existing.count + parsed.count,
          board: board,
        );
      }
    }
  }

  final cards =
      merged.values.toList()..sort((a, b) {
        final boardOrder = a.board.index.compareTo(b.board.index);
        if (boardOrder != 0) return boardOrder;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  return DeckListParseResult(cards: cards, skippedLines: skipped);
}

/// Writes the list in the same shape [parseDeckList] reads.
String exportDeckList({
  required List<DeckCardEntry> entries,
  String? commanderName,
  String? partnerName,
  bool identifyCommander = false,
}) {
  final buffer = StringBuffer();
  if (identifyCommander) {
    final commander = commanderName?.trim() ?? '';
    final partner = partnerName?.trim() ?? '';
    if (commander.isNotEmpty) buffer.writeln('1 $commander');
    if (partner.isNotEmpty) buffer.writeln('1 $partner');
    if (buffer.isNotEmpty) buffer.writeln();
  }

  void writeBoard(DeckBoard board) {
    final lines =
        entries.where((entry) => entry.deckBoard == board).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    for (final entry in lines) {
      if (entry.count <= 0 || entry.name.trim().isEmpty) continue;
      buffer.writeln('${entry.count} ${entry.name.trim()}');
    }
  }

  writeBoard(DeckBoard.main);
  final sideboard = entries.where(
    (entry) => entry.deckBoard == DeckBoard.sideboard,
  );
  if (sideboard.any(
    (entry) => entry.count > 0 && entry.name.trim().isNotEmpty,
  )) {
    if (buffer.isNotEmpty) buffer.writeln();
    buffer.writeln('Sideboard');
    writeBoard(DeckBoard.sideboard);
  }
  return buffer.toString().trimRight();
}

List<List<String>> _blocks(String raw) {
  final blocks = <List<String>>[];
  var current = <String>[];
  for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) {
      if (current.isNotEmpty) {
        blocks.add(current);
        current = <String>[];
      }
      continue;
    }
    current.add(line);
  }
  if (current.isNotEmpty) blocks.add(current);
  return blocks;
}

bool _isSideboardHeading(String line) {
  final key = line.toLowerCase().replaceAll(':', '').trim();
  return key == 'sideboard' || key == 'sb';
}

bool _isIgnorableHeading(String line) {
  final key = line.toLowerCase().replaceAll(':', '').trim();
  return key == 'commander' ||
      key == 'commanders' ||
      key == 'deck' ||
      key == 'main' ||
      key == 'mainboard' ||
      key == 'maybeboard';
}

class _Line {
  const _Line({required this.name, required this.count, required this.key});

  final String name;
  final int count;
  final String key;

  String mergeKey(DeckBoard board) => '${board.name}::$key';
}

_Line? _parseLine(String line) {
  final match = RegExp(r'^(\d+)\s*[xX]?\s+(.+)$').firstMatch(line.trim());
  if (match == null) return null;
  final count = int.tryParse(match.group(1)!);
  if (count == null || count <= 0 || count > 999) return null;
  final name = _cleanCardName(match.group(2)!);
  if (name.isEmpty) return null;
  return _Line(name: name, count: count, key: _normalizeName(name));
}

String _cleanCardName(String raw) {
  var name = raw.trim();
  name = name.replaceFirst(
    RegExp(r'\s+\([A-Za-z0-9]{2,8}\)\s+\d+[a-zA-Z]?\s*$'),
    '',
  );
  name = name.replaceFirst(RegExp(r'\s+\([A-Za-z0-9]{2,8}\)\s*$'), '');
  return name.trim();
}

String _normalizeName(String? raw) =>
    (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
