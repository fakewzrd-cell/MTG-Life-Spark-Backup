/// Shared name key for bracket lists, combos, and collection matching.
String bracketNameKey(String name) =>
    name
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
