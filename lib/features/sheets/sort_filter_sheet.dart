// lib/features/sheets/sort_filter_sheet.dart
import 'package:flutter/material.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/widgets/pulsr_bottom_sheet.dart';
import '../../core/widgets/pulsr_pressable.dart';

class SortFilterSheet extends StatelessWidget {
  final String currentSort;
  final bool ascending;
  final Function(String sortBy, bool ascending) onApply;

  const SortFilterSheet({
    super.key,
    required this.currentSort,
    required this.ascending,
    required this.onApply,
  });

  static Future<void> show(
    BuildContext context, {
    required String currentSort,
    required bool ascending,
    required Function(String sortBy, bool ascending) onApply,
  }) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => SortFilterSheet(
        currentSort: currentSort,
        ascending: ascending,
        onApply: onApply,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final sortOptions = [
      {'key': 'title', 'label': context.l10n.title},
      {'key': 'artist', 'label': context.l10n.artist},
      {'key': 'album', 'label': context.l10n.albums},
      {'key': 'dateAdded', 'label': context.l10n.recentlyAdded},
      {'key': 'duration', 'label': context.l10n.duration},
      {'key': 'playCount', 'label': context.l10n.mostPlayed},
      {'key': 'rating', 'label': context.l10n.browseTopRated},
      {'key': 'lastPlayed', 'label': context.l10n.recentlyPlayed},
      {'key': 'fileSize', 'label': context.l10n.fileSize},
      {'key': 'year', 'label': context.l10n.browseReleaseYear},
    ];

    return PulsrBottomSheetContainer(
      title: Text(context.l10n.sortAndFilter),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.65),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          itemCount: sortOptions.length,
          separatorBuilder: (_, __) => Divider(
            color: p.hairline.withValues(alpha: 0.5),
            height: 1,
          ),
          itemBuilder: (context, index) {
            final option = sortOptions[index];
            final isSelected = currentSort == option['key'];
            return PulsrPressable(
              pressedScale: 0.985,
              onTap: () {
                final newAsc = isSelected ? !ascending : true;
                onApply(option['key']!, newAsc);
                Navigator.pop(context);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option['label']!,
                        style: TextStyle(
                          color: isSelected ? p.accent : p.textPrimary,
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: p.accentContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          ascending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          color: p.accent,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
