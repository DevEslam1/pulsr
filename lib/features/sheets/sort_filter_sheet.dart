// lib/features/sheets/sort_filter_sheet.dart
import 'package:flutter/material.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/adaptive.dart';
import '../../core/utils/l10n_extensions.dart';

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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Adaptive.maxSheetWidth,
              maxHeight: screenHeight * 0.80,
            ),
            child: Material(
              color: p.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: p.hairline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        context.l10n.sortAndFilter,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: p.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: sortOptions.length,
                          separatorBuilder: (_, __) => Divider(
                            color: p.hairline.withValues(alpha: 0.5),
                            height: 1,
                          ),
                          itemBuilder: (context, index) {
                            final option = sortOptions[index];
                            final isSelected = currentSort == option['key'];
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 2, horizontal: 4),
                              title: Text(
                                option['label']!,
                                style: TextStyle(
                                  color: isSelected ? p.accent : p.textPrimary,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  fontSize: 14.5,
                                ),
                              ),
                              trailing: isSelected
                                  ? Icon(
                                      ascending
                                          ? Icons.arrow_upward_rounded
                                          : Icons.arrow_downward_rounded,
                                      color: p.accent,
                                      size: 20,
                                    )
                                  : null,
                              onTap: () {
                                final newAsc = isSelected ? !ascending : true;
                                onApply(option['key']!, newAsc);
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
