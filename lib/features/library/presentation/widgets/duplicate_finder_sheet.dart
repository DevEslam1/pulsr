// lib/features/library/presentation/widgets/duplicate_finder_sheet.dart
import 'package:flutter/material.dart';
import '../../../../data/db/app_database.dart';
import '../duplicate_finder_screen.dart';

/// Legacy sheet entry point reduced to a launcher for [DuplicateFinderScreen]
/// to ensure a single, consistent deduplication experience across the app.
class DuplicateFinderSheet extends StatelessWidget {
  final List<SongsTableData>? allSongs;
  final ValueChanged<List<SongsTableData>>? onDeleteSelected;

  const DuplicateFinderSheet({
    super.key,
    this.allSongs,
    this.onDeleteSelected,
  });

  static Future<void> show(
    BuildContext context, {
    List<SongsTableData>? allSongs,
    ValueChanged<List<SongsTableData>>? onDeleteSelected,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const DuplicateFinderScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const DuplicateFinderScreen();
  }
}
