import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';

enum LibraryDestination { decks, collection }

final libraryDestinationProvider = StateProvider<LibraryDestination>(
  (ref) => LibraryDestination.decks,
);

/// Swaps the library contents in place. It does not open another route.
class LibraryDestinationSwitch extends ConsumerWidget {
  const LibraryDestinationSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(libraryDestinationProvider);
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LayoutTokens.gr4,
        LayoutTokens.gr2,
        LayoutTokens.gr4,
        LayoutTokens.gr2,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(RadiusTokens.pill),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: _LibrarySegment(
                  label: l10n.decksTitle,
                  selected: selected == LibraryDestination.decks,
                  colors: colors,
                  onTap: () {
                    ref.read(libraryDestinationProvider.notifier).state =
                        LibraryDestination.decks;
                  },
                ),
              ),
              Expanded(
                child: _LibrarySegment(
                  label: l10n.collectionTitle,
                  selected: selected == LibraryDestination.collection,
                  colors: colors,
                  onTap: () {
                    ref.read(libraryDestinationProvider.notifier).state =
                        LibraryDestination.collection;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibrarySegment extends StatelessWidget {
  const _LibrarySegment({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppColorTokens colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.pill);
    return Material(
      color: selected ? colors.primaryAccent : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : colors.textPrimary,
              fontSize: FontTokens.body,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
