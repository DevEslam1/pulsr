// lib/features/artist_detail/presentation/artist_detail_screen.dart
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';
import '../../../core/widgets/pulsr_pressable.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/responsive/detail_scaffold.dart';
import '../../../core/widgets/async_state_builder.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_section_header.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_artists_usecase.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_options_sheet.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/artist_bio_service.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../core/utils/pulsr_haptics.dart';
class ArtistDetailScreen extends StatefulWidget {
  final ArtistsTableData artist;
  final GetArtistsUseCase? getArtistsUseCase;
  final String? heroTag;

  const ArtistDetailScreen(
      {super.key, required this.artist, this.getArtistsUseCase, this.heroTag});

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  bool _bioExpanded = false;
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
  Stream<Result<List<ArtistsTableData>>>? _artistsStream;

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
    _updateArtistsStream();
    _updateAlbumsStream();
    _updateSongsStream();
  }

  void _updateArtistsStream() {
    try {
      _artistsStream = _useCase.watchArtists().distinct();
    } catch (_) {
      // Unstubbed in isolated widget tests; falls back to widget.artist.
      _artistsStream = null;
    }
  }

  void _updateAlbumsStream() {
    _albumsStream = _useCase.watchArtistAlbums(widget.artist.id).distinct();
  }

  void _updateSongsStream() {
    _songsStream = _useCase.watchArtistSongs(widget.artist.id).distinct();
  }

  @override
  void didUpdateWidget(ArtistDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.artist.id != oldWidget.artist.id ||
        widget.getArtistsUseCase != oldWidget.getArtistsUseCase) {
      _useCase = widget.getArtistsUseCase ?? getIt<GetArtistsUseCase>();
      setState(() {
        _bioFuture = _bioService.getArtistInfo(widget.artist.name);
        _rebuildStreams();
      });
    }
  }

  Widget _actionButtons(BuildContext context, List<SongsTableData> songs) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.r14All,
              ),
            ),
            onPressed: songs.isEmpty
                ? null
                : () {
                    PulsrHaptics.mediumImpact();
                    context
                        .read<PlayerCubit>()
                        .playSong(songs.first, queue: songs);
                  },
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: Text(
              context.l10n.playAll,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: p.surfaceContainerHigh,
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.hairline),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.r14All,
              ),
            ),
            onPressed: songs.isEmpty
                ? null
                : () {
                    PulsrHaptics.mediumImpact();
                    final shuffled = List<SongsTableData>.from(songs)
                      ..shuffle();
                    context
                        .read<PlayerCubit>()
                        .playSong(shuffled.first, queue: shuffled);
                  },
            icon: Icon(Icons.shuffle_rounded, color: p.accent, size: 20),
            label: Text(
              context.l10n.shuffle,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);

    return StreamBuilder<Result<List<ArtistsTableData>>>(
      stream: _artistsStream,
      builder: (context, artistSnap) {
        final liveArtists = artistSnap.data?.fold(
              (_) => const <ArtistsTableData>[],
              (artists) => artists,
            ) ??
            const <ArtistsTableData>[];
        var artist = widget.artist;
        for (final candidate in liveArtists) {
          if (candidate.id == widget.artist.id) {
            artist = candidate;
            break;
          }
        }

        return StreamBuilder<Result<List<SongsTableData>>>(
          stream: _songsStream,
          builder: (context, songsSnapshot) {
            final hasSongs = songsSnapshot.hasData &&
                (songsSnapshot.data?.isRight() ?? false);
            final currentSongs = songsSnapshot.data?.fold(
                  (_) => const <SongsTableData>[],
                  (songs) => songs,
                ) ??
                const <SongsTableData>[];
            final trackCount = hasSongs ? currentSongs.length : artist.songCount;

            return DetailScaffold(
              titleText: artist.name,
              onRefresh: () async {
                if (mounted) {
                  setState(() {
                    _bioFuture = _bioService.getArtistInfo(artist.name);
                    _rebuildStreams();
                  });
                }
              },
          hero: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              (p.isHighContrast ||
                      (MediaQuery.maybeHighContrastOf(context) ?? false) ||
                      (p.isDark && p.bg.computeLuminance() < 0.001))
                  ? p.bg
                  : p.accent.withValues(
                      alpha: p.isDark ? 0.16 : 0.10,
                    ),
              p.bg,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
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
                    boxShadow: p.isCalmDensity ||
                            p.isHighContrast ||
                            (MediaQuery.maybeHighContrastOf(context) ?? false)
                        ? null
                        : [
                            BoxShadow(
                                color: p.glow,
                                blurRadius: 28,
                                spreadRadius: -4,
                                offset: const Offset(0, 8)),
                          ],
                  ),
                  child: Hero(
                    tag: widget.heroTag ?? 'artist_${artist.id}',
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
                context.l10n.tracksCount(trackCount),
                style: TextStyle(
                    color: p.textSecondary, fontSize: AppFontSize.bodySmall),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Primary Play / Shuffle action row
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.xs,
              ),
              child: _actionButtons(context, currentSongs),
            ),
            const SizedBox(height: AppSpacing.xs),

            // Artist Biography & HD Info
            FutureBuilder<ArtistInfo?>(
              key: ValueKey('artist_bio_${artist.id}'),
              future: _bioFuture,
              builder: (context, snapshot) {
                return AsyncStateBuilder<ArtistInfo?>(
                  snapshot: snapshot,
                  loadingWidget: Semantics(
                    liveRegion: true,
                    child: Container(
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
                  ),
                  onError: (_) => Semantics(
                    liveRegion: true,
                    child: Container(
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
                            context.l10n.bioUnavailable,
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              color: p.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  emptyWidget: const SizedBox.shrink(),
                  isEmpty: (info) => info?.bio == null,
                  onData: (info) {
                    final bio = info!.bio!;
                    return Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s20, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer.withValues(alpha: 0.6),
                        borderRadius: AppRadii.r16All,
                        border: Border.all(color: p.hairline),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: AppRadii.r16All,
                        child: InkWell(
                          borderRadius: AppRadii.r16All,
                          onTap: () {
                            PulsrHaptics.selectionClick();
                            setState(() => _bioExpanded = !_bioExpanded);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.s14),
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
                                    const Spacer(),
                                    AnimatedRotation(
                                      turns: _bioExpanded ? 0.5 : 0.0,
                                      duration: context.motionMs(200),
                                      child: Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: p.accent,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.s6),
                                AnimatedSize(
                                  duration: context.motionMs(200),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: Text(
                                    bio,
                                    maxLines: _bioExpanded ? null : 4,
                                    overflow: _bioExpanded
                                        ? TextOverflow.visible
                                        : TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: AppFontSize.label,
                                      color: p.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
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
                    onRetry: () => setState(_updateAlbumsStream),
                  );

              return AsyncStateBuilder<Result<List<AlbumsTableData>>>(
                snapshot: snapshot,
                loadingWidget: Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context)),
                    child: const SkeletonList(itemCount: 2),
                  ),
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
                        height: 175 +
                            (MediaQuery.textScalerOf(context)
                                        .scale(1.0)
                                        .clamp(1.0, 2.0) -
                                    1.0) *
                                35,
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
                              child: PulsrPressable(
                                pressedScale: 0.96,
                                hapticStyle: PulsrHapticStyle.selection,
                                focusBorderRadius: AppRadii.r16All,
                                onTap: () => context.push(
                                    '/album?id=${album.id}',
                                    extra: album),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Hero(
                                      tag: 'album_${album.id}',
                                      child: CachedArtwork(
                                          id: album.id,
                                          remoteUrl: album.artworkUri,
                                          type: ArtworkType.ALBUM,
                                          size: 120,
                                          borderRadius: 16),
                                    ),
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
                                        context.l10n
                                            .tracksCount(album.songCount),
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
          Builder(
            builder: (context) {
              Widget buildErrorSection() => _ErrorSection(
                    title: context.l10n.browseTopTracks,
                    message: context.l10n.browseCouldNotLoadTopTracks,
                    onRetry: () => setState(_updateSongsStream),
                  );

              return AsyncStateBuilder<Result<List<SongsTableData>>>(
                snapshot: songsSnapshot,
                loadingWidget: Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context)),
                    child: const SkeletonList(itemCount: 4),
                  ),
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
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: songs.length,
                        itemBuilder: (context, i) => SongTile(
                          song: songs[i],
                          index: i,
                          subtitleOverride: songs[i].album,
                          onTap: () {
                            PulsrHaptics.lightImpact();
                            context
                                .read<PlayerCubit>()
                                .playSong(songs[i], queue: songs);
                          },
                          onMorePressed: () {
                            PulsrHaptics.lightImpact();
                            SongOptionsSheet.show(context, song: songs[i]);
                          },
                        ),
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
          },
        );
      },
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
          Semantics(
            liveRegion: true,
            child: Container(
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
          ),
        ],
      ),
    );
  }
}
