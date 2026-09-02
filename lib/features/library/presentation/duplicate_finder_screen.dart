// lib/features/library/presentation/duplicate_finder_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/services/duplicate_finder_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/widgets/song_tile.dart';
import '../cubit/library_cubit.dart';
import '../../player/cubit/player_cubit.dart';

class DuplicateFinderScreen extends StatefulWidget {
  const DuplicateFinderScreen({super.key});

  @override
  State<DuplicateFinderScreen> createState() => _DuplicateFinderScreenState();
}

class _DuplicateFinderScreenState extends State<DuplicateFinderScreen> {
  final DuplicateFinderService _finder = DuplicateFinderService();
  List<DuplicateGroup> _duplicateGroups = [];
  bool _isScanning = true;
  int _scanGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final generation = ++_scanGeneration;
    setState(() => _isScanning = true);
    final songs = context.read<LibraryCubit>().state.songs;
    // F-08: the regex-heavy scan runs on a background isolate so the first
    // open / refresh does not freeze the UI isolate.
    final duplicates = await _finder.findDuplicatesAsync(songs);
    if (!mounted || generation != _scanGeneration) return;
    setState(() {
      _duplicateGroups = duplicates;
      _isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.surface,
        elevation: 0,
        title: Text(
          'Duplicate Cleaner',
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: p.textPrimary),
            onPressed: _scan,
          ),
        ],
      ),
      body: _isScanning
          ? Center(child: CircularProgressIndicator(color: p.primary))
          : _duplicateGroups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 64, color: p.accent),
                      const SizedBox(height: 16),
                      Text(
                        'No Duplicates Found!',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: p.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your library is cleanly organized.',
                        style: TextStyle(color: p.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  itemCount: _duplicateGroups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final group = _duplicateGroups[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: p.surfaceCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                group.reason,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: p.primary,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: p.surfaceContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${group.songs.length} Tracks',
                                  style: TextStyle(
                                      fontSize: 11, color: p.textSecondary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (final song in group.songs)
                            SongTile(
                              song: song,
                              onTap: () =>
                                  context.read<PlayerCubit>().playSong(song),
                            ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
