// lib/features/library/presentation/library_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/aura_theme.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';

class LibraryStatsScreen extends StatelessWidget {
  const LibraryStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.surface,
        elevation: 0,
        title: Text(
          'Library Statistics',
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          final songs = state.songs;
          final artists = state.artists;
          final albums = state.albums;
          final genres = state.genres;

          final totalDurationMs = songs.fold<int>(0, (sum, s) => sum + s.durationMs);
          final totalSizeBytes = songs.fold<int>(0, (sum, s) => sum + (s.fileSize ?? 0));
          final losslessCount = songs.where((s) => s.codec == 'FLAC' || s.codec == 'ALAC' || s.bitDepth != null && s.bitDepth! > 16).length;
          final lossyCount = songs.length - losslessCount;

          final totalHours = (totalDurationMs / (1000 * 60 * 60)).toStringAsFixed(1);
          final totalGb = (totalSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            children: [
              // Hero Metrics Grid
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      icon: Icons.music_note_rounded,
                      title: 'Total Tracks',
                      value: songs.length.toString(),
                      color: p.primary,
                      p: p,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      icon: Icons.person_rounded,
                      title: 'Artists',
                      value: artists.length.toString(),
                      color: p.accent,
                      p: p,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      icon: Icons.album_rounded,
                      title: 'Albums',
                      value: albums.length.toString(),
                      color: Colors.amber,
                      p: p,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      icon: Icons.category_rounded,
                      title: 'Genres',
                      value: genres.length.toString(),
                      color: Colors.tealAccent,
                      p: p,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Audio Hours & Storage
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: p.surfaceCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSubMetric(
                          icon: Icons.access_time_filled_rounded,
                          title: 'Total Playback Time',
                          value: '$totalHours Hours',
                          p: p,
                        ),
                        _buildSubMetric(
                          icon: Icons.storage_rounded,
                          title: 'Disk Storage',
                          value: '$totalGb GB',
                          p: p,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: p.hairline),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.high_quality_rounded, color: p.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Quality Tier Distribution',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: p.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          if (songs.isNotEmpty) ...[
                            Expanded(
                              flex: losslessCount > 0 ? losslessCount : 1,
                              child: Container(
                                height: 12,
                                color: const Color(0xFF64D2FF),
                              ),
                            ),
                            Expanded(
                              flex: lossyCount > 0 ? lossyCount : 1,
                              child: Container(
                                height: 12,
                                color: p.surfaceContainer,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Lossless / Hi-Res: $losslessCount tracks',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64D2FF), fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Standard Lossy: $lossyCount tracks',
                          style: TextStyle(fontSize: 12, color: p.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required PulsrPalette p,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: p.textPrimary,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSubMetric({
    required IconData icon,
    required String title,
    required String value,
    required PulsrPalette p,
  }) {
    return Row(
      children: [
        Icon(icon, color: p.accent, size: 24),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 11, color: p.textSecondary)),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: p.textPrimary)),
          ],
        ),
      ],
    );
  }
}
