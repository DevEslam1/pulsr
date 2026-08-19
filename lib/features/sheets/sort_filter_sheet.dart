// lib/features/sheets/sort_filter_sheet.dart
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';

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
    final sortOptions = [
      {'key': 'title', 'label': 'Title'},
      {'key': 'artist', 'label': 'Artist'},
      {'key': 'dateAdded', 'label': 'Recently Added'},
      {'key': 'duration', 'label': 'Duration'},
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.bottomSheetRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Sort & Filter',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 16),
          ...sortOptions.map((option) {
            final isSelected = currentSort == option['key'];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                option['label']!,
                style: TextStyle(
                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              trailing: isSelected
                  ? Icon(
                      ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      color: AppColors.primary,
                      size: 20,
                    )
                  : null,
              onTap: () {
                final newAsc = isSelected ? !ascending : true;
                onApply(option['key']!, newAsc);
                Navigator.pop(context);
              },
            );
          }),
        ],
      ),
    );
  }
}
