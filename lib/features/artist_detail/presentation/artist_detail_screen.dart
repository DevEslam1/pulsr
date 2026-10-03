// lib/features/artist_detail/presentation/artist_detail_screen.dart
import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/responsive/detail_scaffold.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_state_builder.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_section_header.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_artists_usecase.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/artist_bio_service.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class ArtistDetailScreen extends StatefulWidget {
  final ArtistsTableData artist;
  final GetArtistsUseCase? getArtistsUseCase;

  const ArtistDetailScreen(
      {super.key, required this.artist, this.getArtistsUseCase});

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  static const _bioUnavailableText = 'Bio unavailable';
  late GetArtistsUseCase _useCase;
  late final ArtistBioService _bioService;
  // Resolved once per artist so widget rebuilds (scroll, theme, selection)
  // never re-fire the Deezer/Wikipedia lookups (the service's cache is
  // instance-level, so a per-build `ArtistBioService()` defeated it).
  late Future<ArtistInfo?> _bioFuture;

  // Memoized watch streams: recreating them in build() resubscribed to the DB
  // on every rebuild and reset the StreamBuilder's snapshot.
  late Stream<Result<List<AlbumsTableData>>> _albumsStream;
  late Stream<Result<List<SongsTableData>>> _songsStream;

  @override
  void initState() {
    super.initState();
    _useCase = widget.getArtistsUseCase ?? getIt<GetArtistsUseCase>();
    _bioService = getIt.isRegistered<ArtistBioService>()
        ? getIt<ArtistBioService>()
        : ArtistBioService();
    _bioFuture = _bioService.getArtistInfo(widget.artist.name);
    _rebuildStreams();
  }

  void _rebuildStreams() {
    _albumsStream = _useCase.watchArtistAlbums(widget.artist.id).distinct();
    _songsStream = _useCase.watchArtistSongs(widget.artist.id).distinct();
  }

  @override
  void didUpdateWidget(ArtistDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.artist.id != oldWidget.artist.id) {
      setState(() {
        _bioFuture = _bioService.getArtistInfo(widget.artist.name);
        _rebuildStreams();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);
    final artist = widget.artist;

    return DetailScaffold(
      titleText: artist.name,
      onRefresh: () async {
        if (mounted) setState(() {});
      },
      hero: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Semantics(
              image: true,
              label: artist.name,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: p.accent.withValues(alpha: 0.3), width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: p.glow,
                        blurRadius: 28,
                        spreadRadius: -4,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: CachedArtwork(
                  id: artist.id,
                  type: ArtworkType.ARTIST,
                  size: isTablet ? 160 : 130,
                  borderRadius: 999,
                  fallbackIcon: Icons.person_rounded,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s14),
          Center(
            child: Text(
              artist.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Center(
            child: Text(
              Formatters.formatTrackCount(artist.songCount),
              style: TextStyle(
                  color: p.textSecondary, fontSize: AppFontSize.bodySmall),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Artist Biography & HD Info
          FutureBuilder<ArtistInfo?>(
            key: ValueKey('artist_bio_${artist.id}'),
            future: _bioFuture,
            builder: (context, snapshot) {
              return AsyncStateBuilder<ArtistInfo?>(
                snapshot: snapshot,
                loadingWidget: Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s20, vertical: AppSpacing.xs),
                  height: 56,
                  decoration: BoxDecoration(
                    color: p.surfaceContainer.withValues(alpha: 0.4),
                    borderRadius: AppRadii.r16All,
                  ),
                  child: Center(
                    child: SkeletonBox(
                      width: double.infinity,
                      height: 40,
                      radius: AppRadii.r12,
                    ),
                  ),
                ),
                onError: (_) => Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s20, vertical: AppSpacing.xs),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer.withValues(alpha: 0.4),
                    borderRadius: AppRadii.r16All,
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: p.textTertiary),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        _bioUnavailableText,
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          color: p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                emptyWidget: const SizedBox.shrink(),
                isEmpty: (info) => info?.bio == null,
                onData: (info) {
                  final bio = info!.bio!;
                  return Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s20, vertical: AppSpacing.xs),
                    padding: const EdgeInsets.all(AppSpacing.s14),
                    decoration: BoxDecoration(
                      color: p.surfaceContainer.withValues(alpha: 0.6),
                      borderRadius: AppRadii.r16All,
                      border: Border.all(color: p.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 16, color: p.accent),
                            const SizedBox(width: AppSpacing.s6),
                            Text(
                              context.l10n.aboutArtist,
                              style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w700,
                                color: p.accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s6),
                        Text(
                          bio,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            color: p.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Discography (Albums)
          StreamBuilder<Result<List<AlbumsTableData>>>(
            stream: _albumsStream,
            builder: (context, snapshot) {
              Widget buildErrorSection() => _ErrorSection(
                    title: context.l10n.albums,
                    message: context.l10n.browseCouldNotLoadAlbums,
                    onRetry: () => setState(() {}),
                  );

              return AsyncStateBuilder<Result<List<AlbumsTableData>>>(
                snapshot: snapshot,
                loadingWidget: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: Adaptive.pagePadding(context)),
                  child: const SkeletonList(itemCount: 2),
                ),
                onError: (_) => buildErrorSection(),
                emptyWidget: const SizedBox.shrink(),
                isEmpty: (result) =>
                    result.fold((_) => false, (albums) => albums.isEmpty),
                onData: (result) => result.fold(
                  (_) => buildErrorSection(),
                  (albums) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PulsrSectionHeader(title: context.l10n.albums),
                      SizedBox(
                        height: 175,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: true,
                          padding: EdgeInsets.symmetric(
                              horizontal: Adaptive.pagePadding(context)),
                          itemCount: albums.length,
                          itemBuilder: (context, index) {
                            final album = albums[index];
                            return Container(
                              width: 120,
                              margin: const EdgeInsetsDirectional.only(
                                  end: AppSpacing.s14),
                              child: InkWell(
                                borderRadius: AppRadii.r16All,
                                onTap: () =>
                                    context.push('/album', extra: album),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CachedArtwork(
                                        id: album.id,
                                        type: ArtworkType.ALBUM,
                                        size: 120,
                                        borderRadius: 16),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(album.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: p.textPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: AppFontSize.bodySmall)),
                                    const SizedBox(height: AppSpacing.s2),
                                    Text(
                                        Formatters.formatTrackCount(
                                            album.songCount),
                                        style: TextStyle(
                                            color: p.textSecondary,
                                            fontSize: AppFontSize.caption)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              );
            },
          ),

          // Top Tracks
          StreamBuilder<Result<List<SongsTableData>>>(
            stream: _songsStream,
            builder: (context, snapshot) {
              Widget buildErrorSection() => _ErrorSection(
                    title: context.l10n.browseTopTracks,
                    message: context.l10n.browseCouldNotLoadTopTracks,
                    onRetry: () => setState(() {}),
                  );

              return AsyncStateBuilder<Result<List<SongsTableData>>>(
                snapshot: snapshot,
                loadingWidget: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: Adaptive.pagePadding(context)),
                  child: const SkeletonList(itemCount: 4),
                ),
                onError: (_) => buildErrorSection(),
                emptyWidget: const SizedBox.shrink(),
                isEmpty: (result) =>
                    result.fold((_) => false, (songs) => songs.isEmpty),
                onData: (result) => result.fold(
                  (_) => buildErrorSection(),
                  (songs) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PulsrSectionHeader(title: context.l10n.browseTopTracks),
                      for (int i = 0; i < songs.length; i++)
                        SongTile(
                          song: songs[i],
                          index: i,
                          subtitleOverride: songs[i].album,
                          onTap: () => context
                              .read<PlayerCubit>()
                              .playSong(songs[i], queue: songs),
                          onMorePressed: () =>
                              SongInfoSheet.show(context, song: songs[i]),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ErrorSection extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _ErrorSection(
      {required this.title, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PulsrSectionHeader(title: title),
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.s14),
            decoration: BoxDecoration(
              color: p.error.withValues(alpha: 0.08),
              borderRadius: AppRadii.r14All,
              border: Border.all(color: p.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: p.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.bodySmall),
                  ),
                ),
                TextButton(
                  onPressed: onRetry,
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
