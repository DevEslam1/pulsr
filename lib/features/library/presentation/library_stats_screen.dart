// lib/features/library/presentation/library_stats_screen.dart
import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../player/cubit/player_cubit.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

class LibraryStatsScreen extends StatefulWidget {
  final IMusicRepository? musicRepository;

  const LibraryStatsScreen({super.key, this.musicRepository});

  @override
  State<LibraryStatsScreen> createState() => _LibraryStatsScreenState();
}

class _LibraryStatsScreenState extends State<LibraryStatsScreen>
    with WidgetsBindingObserver {
  late final IMusicRepository? _musicRepository;

  /// Full-library snapshot for accurate totals. The live `LibraryCubit.songs`
  /// list is a paginated window, so deriving stats from it under-counts large
  /// libraries. Falls back to the window until the query completes.
  List<SongsTableData>? _allSongs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _musicRepository = widget.musicRepository ??
        (getIt.isRegistered<IMusicRepository>()
            ? getIt<IMusicRepository>()
            : null);
    _loadAllSongs();
  }

  DateTime? _lastLoadedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_allSongs == null ||
          _allSongs!.isEmpty ||
          _lastLoadedAt == null ||
          now.difference(_lastLoadedAt!).inSeconds >= 60) {
        _loadAllSongs();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadAllSongs() async {
    final repo = _musicRepository;
    if (repo == null) return;
    final res = await repo.getAllSongs();
    if (!mounted) return;
    res.fold((_) {}, (songs) {
      if (mounted) {
        _lastLoadedAt = DateTime.now();
        setState(() => _allSongs = songs);
      }
    });
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: context.l10n.browseClearPlayHistoryTitle,
      message: context.l10n.browseClearPlayHistoryMessage,
      icon: Icons.history_rounded,
      confirmLabel: context.l10n.browseClearHistory,
      isDestructive: true,
    );

    if (confirmed == true && context.mounted) {
      final repo = _musicRepository;
      if (repo != null) {
        final res = await repo.clearRecentlyPlayed();
        if (context.mounted) {
          res.fold(
            (err) => PulsrToast.show(
              context,
              message:
                  '${context.l10n.browseClearHistoryFailed}: ${err.message}',
              isError: true,
            ),
            (_) => PulsrToast.show(
              context,
              message: context.l10n.browseHistoryCleared,
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
          title: Text(context.l10n.listeningStats,
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: p.textSecondary),
              tooltip: context.l10n.refresh,
              onPressed: _loadAllSongs,
            ),
            IconButton(
              icon: Icon(Icons.delete_sweep_rounded, color: p.textSecondary),
              tooltip: context.l10n.browseClearPlayHistory,
              onPressed: () => _confirmClearHistory(context),
            ),
          ],
        ),
        body: BlocBuilder<LibraryCubit, LibraryState>(
          builder: (context, state) {
            final songs = _allSongs ?? state.songs;
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
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, 120),
              children: [
                // Top Metrics Grid
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        context,
                        icon: Icons.music_note_rounded,
                        title: context.l10n.browseTotalTracks,
                        value: songs.length.toString(),
                        color: p.primary,
                        p: p,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _buildMetricCard(
                        context,
                        icon: Icons.play_circle_filled_rounded,
                        title: context.l10n.browseTotalPlays,
                        value: totalPlays.toString(),
                        color: p.accent,
                        p: p,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        context,
                        icon: Icons.access_time_filled_rounded,
                        title: context.l10n.browseListeningTime,
                        value: '$totalHours ${context.l10n.browseHoursShort}',
                        color: p.warning,
                        p: p,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _buildMetricCard(
                        context,
                        icon: Icons.storage_rounded,
                        title: context.l10n.browseDiskStorage,
                        value: '$totalGb GB',
                        color: p.success,
                        p: p,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s20),

                // Audio Quality & Library Breakdown
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s18),
                  decoration: BoxDecoration(
                    color: p.surfaceCard,
                    borderRadius: BorderRadius.circular(AppRadii.r20),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.high_quality_rounded,
                              color: p.primary, size: 22),
                          const SizedBox(width: AppSpacing.xs),
                          Text(context.l10n.audioQualityTiers,
                            style: TextStyle(
                              fontSize: AppFontSize.callout,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${albums.length} ${context.l10n.albums} · ${artists.length} ${context.l10n.artists}',
                            style:
                                TextStyle(fontSize: AppFontSize.label, color: p.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.r8),
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
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${context.l10n.browseLosslessHiRes} $losslessCount ${context.l10n.browseTracks}',
                            style: const TextStyle(
                              fontSize: AppFontSize.label,
                              color: Color(0xFF64D2FF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${context.l10n.browseStandardLossy} $lossyCount ${context.l10n.browseTracks}',
                            style: TextStyle(
                                fontSize: AppFontSize.label, color: p.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Top Played Songs Section
                _buildSectionHeader(
                  title: context.l10n.browseMostPlayedTracks,
                  subtitle: context.l10n.browseMostPlayedTracksSubtitle,
                  icon: Icons.leaderboard_rounded,
                  p: p,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (topSongs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s20),
                    decoration: BoxDecoration(
                      color: p.surfaceCard,
                      borderRadius: BorderRadius.circular(AppRadii.r16),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Center(
                      child: Text(context.l10n.noPlayHistory,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
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
                const SizedBox(height: AppSpacing.lg),

                // Top Artists Section
                if (topArtists.isNotEmpty) ...[
                  _buildSectionHeader(
                    title: context.l10n.browseTopArtists,
                    subtitle: context.l10n.browseTopArtistsSubtitle,
                    icon: Icons.person_search_rounded,
                    p: p,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    decoration: BoxDecoration(
                      color: p.surfaceCard,
                      borderRadius: BorderRadius.circular(AppRadii.r18),
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
                                    fontWeight: FontWeight.w700,
                                    fontSize: AppFontSize.label,
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
                                  fontSize: AppFontSize.body,
                                ),
                              ),
                              subtitle: Text(
                                '$trackCount ${context.l10n.browseTracksInLibrary}',
                                style: TextStyle(
                                    color: p.textSecondary, fontSize: AppFontSize.label),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(

                                    horizontal: AppSpacing.s10, vertical: AppSpacing.xxs),
                                decoration: BoxDecoration(
                                  color: p.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(AppRadii.r12),
                                ),
                                child: Text(
                                  '$plays ${context.l10n.browsePlays}',
                                  style: TextStyle(
                                    color: p.accent,
                                    fontSize: AppFontSize.label,
                                    fontWeight: FontWeight.w700,
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
                  const SizedBox(height: AppSpacing.lg),
                ],

                // Recently Played Section
                if (recentlyPlayed.isNotEmpty) ...[
                  _buildSectionHeader(
                    title: context.l10n.recentlyPlayed,
                    subtitle: context.l10n.browseLatestTracksSubtitle,
                    icon: Icons.history_rounded,
                    p: p,
                  ),
                  const SizedBox(height: AppSpacing.sm),
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
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadii.r10),
          ),
          child: Icon(icon, color: p.accent, size: 20),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: AppFontSize.bodyLarge,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: AppFontSize.label, color: p.textSecondary),
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
        return AppColors.dacGold; // Gold
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
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.r14),
          onTap: () {
            context.read<PlayerCubit>().playSong(song, queue: queue);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: p.surfaceCard,
              borderRadius: BorderRadius.circular(AppRadii.r14),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                if (rank != null) ...[
                  SizedBox(width: AppSpacing.s28,
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        fontSize: AppFontSize.bodySmall,
                        fontWeight: FontWeight.w700,
                        color: _getRankColor(rank, p),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s6),
                ],
                CachedArtwork(
                  id: song.id,
                  remoteUrl: song.remoteArtworkUrl,
                  type: ArtworkType.AUDIO,
                  size: 44,
                  borderRadius: 10,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.body,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppFontSize.label, color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (song.playCount > 0) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(

                        horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadii.r8),
                    ),
                    child: Text(
                      '${song.playCount} ${context.l10n.browsePlays}',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        color: p.accent,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.s6),
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadii.r18),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadii.r10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: TextStyle(
              fontSize: AppFontSize.titleLarge,
              fontWeight: FontWeight.w700,
              color: p.textPrimary,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: AppFontSize.label, color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}
