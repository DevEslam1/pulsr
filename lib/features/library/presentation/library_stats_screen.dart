// lib/features/library/presentation/library_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../player/cubit/player_cubit.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';

class LibraryStatsScreen extends StatelessWidget {
  const LibraryStatsScreen({super.key});

  Future<void> _confirmClearHistory(BuildContext context) async {
    final p = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
        title: Text(
          'Clear Play History?',
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will reset your recently played list and listening history. Your song files and playlists will not be affected.',
          style: TextStyle(color: p.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: p.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: p.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.buttonRadius,
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear History'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      if (getIt.isRegistered<IMusicRepository>()) {
        final repo = getIt<IMusicRepository>();
        final res = await repo.clearRecentlyPlayed();
        if (context.mounted) {
          res.fold(
            (err) => PulsrToast.show(
              context,
              message: 'Failed to clear history: ${err.message}',
              isError: true,
            ),
            (_) => PulsrToast.show(
              context,
              message: 'Listening history cleared',
              icon: Icons.history_rounded,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          backgroundColor: p.surface,
          elevation: 0,
          leading: const PulsrBackButton(),
          title: Text(
            'Listening & Library Stats',
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.delete_sweep_rounded, color: p.textSecondary),
              tooltip: 'Clear Play History',
              onPressed: () => _confirmClearHistory(context),
            ),
          ],
        ),
        body: BlocBuilder<LibraryCubit, LibraryState>(
          builder: (context, state) {
            final songs = state.songs;
            final artists = state.artists;
            final albums = state.albums;

            final totalDurationMs =
                songs.fold<int>(0, (sum, s) => sum + s.durationMs);
            final totalSizeBytes =
                songs.fold<int>(0, (sum, s) => sum + (s.fileSize ?? 0));
            final totalPlays =
                songs.fold<int>(0, (sum, s) => sum + s.playCount);

            final losslessCount = songs
                .where((s) =>
                    s.codec == 'FLAC' ||
                    s.codec == 'ALAC' ||
                    (s.bitDepth != null && s.bitDepth! > 16))
                .length;
            final lossyCount = songs.length - losslessCount;

            final totalHours =
                (totalDurationMs / (1000 * 60 * 60)).toStringAsFixed(1);
            final totalGb =
                (totalSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2);

            // Most played songs
            final topPlayed = List<SongsTableData>.from(songs)
              ..sort((a, b) => b.playCount.compareTo(a.playCount));
            final topSongs =
                topPlayed.where((s) => s.playCount > 0).take(10).toList();

            // Top artists by total song plays
            final Map<String, int> artistPlayCounts = {};
            final Map<String, int> artistTrackCounts = {};
            for (final s in songs) {
              final artistName = s.artist.trim();
              if (artistName.isEmpty || artistName == 'Unknown Artist') continue;
              artistPlayCounts[artistName] =
                  (artistPlayCounts[artistName] ?? 0) + s.playCount;
              artistTrackCounts[artistName] =
                  (artistTrackCounts[artistName] ?? 0) + 1;
            }
            final sortedArtists = artistPlayCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final topArtists = sortedArtists.take(5).toList();

            // Recently played
            final recentSongs = List<SongsTableData>.from(songs)
              ..sort((a, b) =>
                  (b.lastPlayed ?? 0).compareTo(a.lastPlayed ?? 0));
            final recentlyPlayed = recentSongs
                .where((s) => (s.lastPlayed ?? 0) > 0)
                .take(5)
                .toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
              children: [
                // Top Metrics Grid
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
                        icon: Icons.play_circle_filled_rounded,
                        title: 'Total Plays',
                        value: totalPlays.toString(),
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
                        icon: Icons.access_time_filled_rounded,
                        title: 'Listening Time',
                        value: '$totalHours h',
                        color: Colors.amber,
                        p: p,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        context,
                        icon: Icons.storage_rounded,
                        title: 'Disk Storage',
                        value: '$totalGb GB',
                        color: Colors.tealAccent,
                        p: p,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Audio Quality & Library Breakdown
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: p.surfaceCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.high_quality_rounded,
                              color: p.primary, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Audio Quality Tiers',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: p.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${albums.length} Albums · ${artists.length} Artists',
                            style:
                                TextStyle(fontSize: 12, color: p.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
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
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Lossless / Hi-Res: $losslessCount tracks',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64D2FF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Standard Lossy: $lossyCount tracks',
                            style: TextStyle(
                                fontSize: 12, color: p.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Top Played Songs Section
                _buildSectionHeader(
                  title: 'Most Played Tracks',
                  subtitle: 'Your all-time favorites leaderboard',
                  icon: Icons.leaderboard_rounded,
                  p: p,
                ),
                const SizedBox(height: 12),
                if (topSongs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: p.surfaceCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Center(
                      child: Text(
                        'No play history recorded yet. Listen to tracks to track your top hits!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.textSecondary, fontSize: 13),
                      ),
                    ),
                  )
                else
                  ...List.generate(topSongs.length, (index) {
                    final song = topSongs[index];
                    return _buildSongLeaderboardTile(
                      context,
                      rank: index + 1,
                      song: song,
                      queue: topSongs,
                      p: p,
                    );
                  }),
                const SizedBox(height: 24),

                // Top Artists Section
                if (topArtists.isNotEmpty) ...[
                  _buildSectionHeader(
                    title: 'Top Artists',
                    subtitle: 'Ranked by total listening plays',
                    icon: Icons.person_search_rounded,
                    p: p,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: p.surfaceCard,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Column(
                      children: List.generate(topArtists.length, (idx) {
                        final entry = topArtists[idx];
                        final artistName = entry.key;
                        final plays = entry.value;
                        final trackCount = artistTrackCounts[artistName] ?? 0;
                        final isLast = idx == topArtists.length - 1;

                        return Column(
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: _getRankColor(idx + 1, p)
                                    .withValues(alpha: 0.15),
                                child: Text(
                                  '#${idx + 1}',
                                  style: TextStyle(
                                    color: _getRankColor(idx + 1, p),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                artistName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                '$trackCount tracks in library',
                                style: TextStyle(
                                    color: p.textSecondary, fontSize: 12),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: p.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$plays plays',
                                  style: TextStyle(
                                    color: p.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            if (!isLast)
                              Divider(
                                color: p.hairline.withValues(alpha: 0.5),
                                height: 1,
                                indent: 56,
                              ),
                          ],
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Recently Played Section
                if (recentlyPlayed.isNotEmpty) ...[
                  _buildSectionHeader(
                    title: 'Recently Played',
                    subtitle: 'Latest tracks played on this device',
                    icon: Icons.history_rounded,
                    p: p,
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(recentlyPlayed.length, (index) {
                    final song = recentlyPlayed[index];
                    return _buildSongLeaderboardTile(
                      context,
                      rank: null,
                      song: song,
                      queue: recentlyPlayed,
                      p: p,
                    );
                  }),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required PulsrPalette p,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: p.accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: p.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getRankColor(int rank, PulsrPalette p) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // Gold
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return p.accent;
    }
  }

  Widget _buildSongLeaderboardTile(
    BuildContext context, {
    required int? rank,
    required SongsTableData song,
    required List<SongsTableData> queue,
    required PulsrPalette p,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            context.read<PlayerCubit>().playSong(song, queue: queue);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: p.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                if (rank != null) ...[
                  SizedBox(
                    width: 28,
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _getRankColor(rank, p),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                CachedArtwork(
                  id: song.id,
                  remoteUrl: song.remoteArtworkUrl,
                  type: ArtworkType.AUDIO,
                  size: 44,
                  borderRadius: 10,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (song.playCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${song.playCount} plays',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: p.accent,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Icon(Icons.play_circle_outline_rounded,
                    color: p.accent, size: 22),
              ],
            ),
          ),
        ),
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
}
