import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_logo.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../core/errors/failures.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return AppStrings.goodMorning;
    if (hour < 17) return AppStrings.goodAfternoon;
    return AppStrings.goodEvening;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final getSongsUseCase = getIt<GetSongsUseCase>();
    final playerCubit = context.read<PlayerCubit>();
    final isTablet = Adaptive.isTablet(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 160),
              children: [
                // ---------- Hero header ----------
                Padding(
                  padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16, Adaptive.pagePadding(context), 4),
                  child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            MaterialLocalizations.of(context).formatMediumDate(DateTime.now()),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: p.textTertiary),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _getGreeting(),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: p.accentContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.hairline),
                        boxShadow: [
                          BoxShadow(color: p.glow, blurRadius: 24, spreadRadius: -4, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: PulsrLogo(size: 26, color: p.accent, glowColor: p.glow, animate: false),
                    ),
                  ],
                ),
              ),

              // ---------- Quick actions ----------
              Padding(
                padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context), vertical: 20),
                child: Row(
                  children: [
                    _QuickCard(
                      title: AppStrings.favorites,
                      subtitle: 'Liked tracks',
                      icon: Icons.favorite_rounded,
                      color: p.favorite,
                      onTap: () async {
                        final songs = await getSongsUseCase.getAllSongs();
                        songs.fold((l) => null, (list) {
                          final favs = list.where((s) => s.isFavorite).toList();
                          if (favs.isNotEmpty) playerCubit.playSong(favs.first, queue: favs);
                        });
                      },
                    ),
                    const SizedBox(width: 12),
                    _QuickCard(
                      title: AppStrings.dailyDrive,
                      subtitle: 'Auto-mix',
                      icon: Icons.directions_car_rounded,
                      color: p.accent,
                      onTap: () async {
                        final songs = await getSongsUseCase.getAllSongs();
                        songs.fold((l) => null, (list) {
                          if (list.isNotEmpty) {
                            final shuffled = List<SongsTableData>.from(list)..shuffle();
                            playerCubit.playSong(shuffled.first, queue: shuffled);
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 12),
                    _QuickCard(
                      title: AppStrings.focusFlow,
                      subtitle: 'Top played',
                      icon: Icons.headphones_rounded,
                      color: const Color(0xFF1DE9B6),
                      onTap: () async {
                        final songs = await getSongsUseCase.getAllSongs();
                        songs.fold((l) => null, (list) {
                          final top = list.where((s) => s.playCount > 0).toList();
                          if (top.isNotEmpty) playerCubit.playSong(top.first, queue: top);
                        });
                      },
                    ),
                  ],
                ),
              ),

              // ---------- Recently played ----------
              StreamBuilder<Result<List<SongsTableData>>>(
                stream: getSongsUseCase.watchRecentlyPlayed(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _SectionError(onRetry: () => setState(() {}));
                  }
                  final songs = snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];
                  if (songs.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: AppStrings.recentlyPlayed),
                      SizedBox(
                        height: isTablet ? 214 : 196,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                          itemCount: songs.length,
                          itemBuilder: (context, index) {
                            final song = songs[index];
                            final size = isTablet ? 158.0 : 138.0;
                            return Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => playerCubit.playSong(song, queue: songs),
                                child: SizedBox(
                                  width: size,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Stack(
                                        children: [
                                          CachedArtwork(
                                            id: song.id,
                                            type: ArtworkType.AUDIO,
                                            size: size,
                                            borderRadius: 18,
                                          ),
                                          Positioned(
                                            right: 8,
                                            bottom: 8,
                                            child: Container(
                                              width: 34,
                                              height: 34,
                                              decoration: BoxDecoration(
                                                color: p.accent,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(color: p.glow, blurRadius: 14, spreadRadius: 1),
                                                ],
                                              ),
                                              child: Icon(Icons.play_arrow_rounded, color: p.onAccent, size: 22),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 9),
                                      Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                                      const SizedBox(height: 2),
                                      Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: p.textSecondary, fontSize: 11.5)),
                                    ],
                                  ),
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

              const SizedBox(height: 20),

              // ---------- Recently added ----------
              StreamBuilder<Result<List<SongsTableData>>>(
                stream: getSongsUseCase.watchRecentlyAdded(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _SectionError(onRetry: () => setState(() {}));
                  }
                  final songs = snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];
                  if (songs.isEmpty) return const _EmptyLibrary();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: AppStrings.recentlyAdded),
                      for (final song in songs.take(10))
                        SongTile(
                          song: song,
                          onTap: () => playerCubit.playSong(song, queue: songs),
                          onMorePressed: () => showModalBottomSheet(
                            context: context,
                            useRootNavigator: true,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => SongInfoSheet(song: song),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

class _QuickCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isCompact = MediaQuery.sizeOf(context).width < 360;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.all(isCompact ? 10 : 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.04)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            color: p.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(isCompact ? 6 : 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: isCompact ? 18 : 20),
              ),
              SizedBox(height: isCompact ? 10 : 14),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: isCompact ? 12 : 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: isCompact ? 10 : 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  final VoidCallback onRetry;

  const _SectionError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: p.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Could not load your library.',
                style: TextStyle(color: p.textSecondary, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatefulWidget {
  const _EmptyLibrary();

  @override
  State<_EmptyLibrary> createState() => _EmptyLibraryState();
}

class _EmptyLibraryState extends State<_EmptyLibrary> {
  bool _isScanning = false;

  Future<void> _scan() async {
    setState(() => _isScanning = true);
    try {
      final scanner = context.read<MediaScannerService>();
      final count = await scanner.scanDeviceLibrary();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Scan complete! $count tracks loaded.')));
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: p.accentContainer,
                shape: BoxShape.circle,
                border: Border.all(color: p.hairline),
              ),
              child: _isScanning
                  ? Padding(
                      padding: const EdgeInsets.all(22),
                      child: CircularProgressIndicator(strokeWidth: 3, color: p.accent),
                    )
                  : Icon(Icons.music_off_rounded, size: 38, color: p.accent),
            ),
            const SizedBox(height: 18),
            Text('No Music Loaded Yet',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Scan your device storage to load your audio tracks.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              icon: Icon(_isScanning ? Icons.hourglass_top_rounded : Icons.refresh_rounded),
              label: Text(_isScanning ? 'Scanning...' : 'Scan Device Storage'),
              onPressed: _isScanning ? null : _scan,
            ),
          ],
        ),
      ),
    );
  }
}
