// lib/features/home/presentation/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/waveform_logo.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return AppStrings.goodMorning;
    if (hour < 17) return AppStrings.goodAfternoon;
    return AppStrings.goodEvening;
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MusicRepository>();
    final playerCubit = context.read<PlayerCubit>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const WaveformLogo(size: 28),
            const SizedBox(width: 12),
            Text(
              AppStrings.appName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // Greeting Header with w900
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              _getGreeting(),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
            ),
          ),

          // Smart Cards Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _buildSmartCard(
                  context,
                  title: AppStrings.favorites,
                  icon: Icons.favorite_rounded,
                  color: AppColors.favorite,
                  subtitle: 'Liked tracks',
                  onTap: () async {
                    final songs = await repository.getAllSongs();
                    songs.fold((l) => null, (list) {
                      final favs = list.where((s) => s.isFavorite).toList();
                      if (favs.isNotEmpty) {
                        playerCubit.playSong(favs.first, queue: favs);
                      }
                    });
                  },
                ),
                const SizedBox(width: 12),
                _buildSmartCard(
                  context,
                  title: AppStrings.dailyDrive,
                  icon: Icons.directions_car_rounded,
                  color: AppColors.primary,
                  subtitle: 'Auto-mix',
                  onTap: () async {
                    final songs = await repository.getAllSongs();
                    songs.fold((l) => null, (list) {
                      if (list.isNotEmpty) {
                        final shuffled = List<SongsTableData>.from(list)..shuffle();
                        playerCubit.playSong(shuffled.first, queue: shuffled);
                      }
                    });
                  },
                ),
                const SizedBox(width: 12),
                _buildSmartCard(
                  context,
                  title: AppStrings.focusFlow,
                  icon: Icons.headphones_rounded,
                  color: AppColors.ctaLavender,
                  subtitle: 'Top Played',
                  onTap: () async {
                    final songs = await repository.getAllSongs();
                    songs.fold((l) => null, (list) {
                      final top = list.where((s) => s.playCount > 0).toList();
                      if (top.isNotEmpty) {
                        playerCubit.playSong(top.first, queue: top);
                      }
                    });
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Recently Played Section
          StreamBuilder<List<SongsTableData>>(
            stream: repository.watchRecentlyPlayed(),
            builder: (context, snapshot) {
              final recentSongs = snapshot.data ?? [];
              if (recentSongs.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(context, title: AppStrings.recentlyPlayed),
                  SizedBox(
                    height: 190,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: recentSongs.length,
                      itemBuilder: (context, index) {
                        final song = recentSongs[index];
                        return GestureDetector(
                          onTap: () {
                            playerCubit.playSong(song, queue: recentSongs);
                          },
                          child: Container(
                            width: 130,
                            margin: const EdgeInsets.only(right: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CachedArtwork(
                                  id: song.id,
                                  type: ArtworkType.AUDIO,
                                  size: 130,
                                  borderRadius: 16,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // Recently Added Section / Actionable Empty State
          StreamBuilder<List<SongsTableData>>(
            stream: repository.watchRecentlyAdded(),
            builder: (context, snapshot) {
              final songs = snapshot.data ?? [];
              if (songs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                  child: Center(
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.music_off_rounded, size: 36, color: AppColors.primary),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Music Loaded Yet',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Scan your device storage to load your audio tracks.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Scan Device Storage', style: TextStyle(fontWeight: FontWeight.w700)),
                          onPressed: () async {
                            final scanner = context.read<MediaScannerService>();
                            final count = await scanner.scanDeviceLibrary();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Scan complete! $count tracks loaded.')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(context, title: AppStrings.recentlyAdded),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: songs.length > 10 ? 10 : songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 2),
                        leading: CachedArtwork(id: song.id, type: ArtworkType.AUDIO, size: 52, borderRadius: 12),
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        subtitle: Text(
                          '${song.artist} • ${song.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.more_vert_rounded, size: 22),
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              builder: (_) => SongInfoSheet(song: song),
                            );
                          },
                        ),
                        onTap: () {
                          playerCubit.playSong(song, queue: songs);
                        },
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, {required String title}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _buildSmartCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadii.cardRadius,
            border: Border.all(color: AppColors.outline, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
