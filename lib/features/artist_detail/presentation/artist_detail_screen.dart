// lib/features/artist_detail/presentation/artist_detail_screen.dart
import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_artists_usecase.dart';
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
  late GetArtistsUseCase _useCase;
  late final ArtistBioService _bioService;
  // Resolved once per artist so widget rebuilds (scroll, theme, selection)
  // never re-fire the Deezer/Wikipedia lookups (the service's cache is
  // instance-level, so a per-build `ArtistBioService()` defeated it).
  late Future<ArtistInfo?> _bioFuture;

  @override
  void initState() {
    super.initState();
    _useCase = widget.getArtistsUseCase ?? getIt<GetArtistsUseCase>();
    _bioService = getIt.isRegistered<ArtistBioService>()
        ? getIt<ArtistBioService>()
        : ArtistBioService();
    _bioFuture = _bioService.getArtistInfo(widget.artist.name);
  }

  @override
  void didUpdateWidget(ArtistDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.artist.id != oldWidget.artist.id) {
      setState(() {
        _bioFuture = _bioService.getArtistInfo(widget.artist.name);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);
    final artist = widget.artist;

    return PulsrPagePopScope(
      child: Scaffold(
        appBar: AppBar(
          leading: const PulsrBackButton(),
          title: Text(artist.name),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.scrollBottom),
              children: [
                const SizedBox(height: AppSpacing.md),
                Center(
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
                    style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Artist Biography & HD Info
                FutureBuilder(
                  future: _bioFuture,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data?.bio != null) {
                      final bio = snapshot.data!.bio!;
                      return Container(
                        margin: const EdgeInsets.symmetric(

                            horizontal: AppSpacing.s20, vertical: AppSpacing.xs),
                        padding: const EdgeInsets.all(AppSpacing.s14),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(AppRadii.r16),
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
                                Text(context.l10n.aboutArtist,
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
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // Discography (Albums)
                StreamBuilder<Result<List<AlbumsTableData>>>(
                  stream: _useCase.watchArtistAlbums(artist.id).distinct(),
                  builder: (context, snapshot) {
                    final loadFailed = snapshot.hasError ||
                        (snapshot.data?.fold((l) => true, (_) => false) ??
                            false);
                    if (loadFailed) {
                      return _ErrorSection(
                        title: context.l10n.albums,
                        message: context.l10n.browseCouldNotLoadAlbums,
                        onRetry: () => setState(() {}),
                      );
                    }
                    final albums = snapshot.data
                            ?.fold((l) => <AlbumsTableData>[], (r) => r) ??
                        [];
                    if (albums.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader(title: context.l10n.albums),
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
                                margin: const EdgeInsetsDirectional.only(end: AppSpacing.s14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(AppRadii.r16),
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
                    );
                  },
                ),

                // Top Tracks
                StreamBuilder<Result<List<SongsTableData>>>(
                  stream: _useCase.watchArtistSongs(artist.id).distinct(),
                  builder: (context, snapshot) {
                    final loadFailed = snapshot.hasError ||
                        (snapshot.data?.fold((l) => true, (_) => false) ??
                            false);
                    if (loadFailed) {
                      return _ErrorSection(
                        title: context.l10n.browseTopTracks,
                        message: context.l10n.browseCouldNotLoadTopTracks,
                        onRetry: () => setState(() {}),
                      );
                    }
                    final songs = snapshot.data
                            ?.fold((l) => <SongsTableData>[], (r) => r) ??
                        [];
                    if (songs.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader(title: context.l10n.browseTopTracks),
                        for (int i = 0; i < songs.length; i++)
                          SongTile(
                            song: songs[i],
                            index: i,
                            subtitleOverride: songs[i].album,
                            onTap: () => context
                                .read<PlayerCubit>()
                                .playSong(songs[i], queue: songs),
                            onMorePressed: () => SongInfoSheet.show(context, song: songs[i]),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title),
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s14),
            decoration: BoxDecoration(
              color: p.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadii.r14),
              border: Border.all(color: p.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: p.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
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
