// lib/features/folder_detail/presentation/folder_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/failures.dart';
import '../../../core/responsive/pulsr_layout_metrics.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/folder_usecases.dart';
import '../../library/cubit/library_cubit.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/cubit/player_state.dart';
import '../../sheets/song_info_sheet.dart';

class FolderDetailScreen extends StatefulWidget {
  final FolderItem folder;
  final FolderUseCases? folderUseCases;

  const FolderDetailScreen({
    super.key,
    required this.folder,
    this.folderUseCases,
  });

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  late final FolderUseCases _useCase;
  late final ScrollController _scrollController;
  late bool _isExcluded;
  bool _showCollapsedTitle = false;

  @override
  void initState() {
    super.initState();
    _useCase = widget.folderUseCases ?? getIt<FolderUseCases>();
    _isExcluded = widget.folder.isExcluded;
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final show = offset > 180;
    if (show != _showCollapsedTitle) {
      setState(() => _showCollapsedTitle = show);
    }
  }

  Future<void> _toggleExclusion() async {
    final prevExcluded = _isExcluded;
    final newExcluded = !prevExcluded;
    setState(() => _isExcluded = newExcluded);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    LibraryCubit? libraryCubit;
    try {
      libraryCubit = context.read<LibraryCubit>();
    } catch (_) {}

    Result<void> result;
    try {
      if (libraryCubit != null) {
        result = await libraryCubit.toggleFolderExclusion(widget.folder.path);
      } else {
        result = await _useCase.toggleExcludeFolder(widget.folder.path);
      }
    } catch (e) {
      result = Left(DatabaseFailure(e.toString()));
    }

    if (!mounted) return;
    final failureMessage = result.fold<String?>((l) => l.message, (_) => null);
    if (failureMessage != null) {
      setState(() => _isExcluded = prevExcluded);
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(failureMessage)),
      );
      return;
    }

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          newExcluded ? l10n.folderExcluded : l10n.folderIncluded,
        ),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () async {
            if (mounted) setState(() => _isExcluded = prevExcluded);
            try {
              if (libraryCubit != null) {
                await libraryCubit.toggleFolderExclusion(widget.folder.path);
              } else {
                await _useCase.toggleExcludeFolder(widget.folder.path);
              }
            } catch (_) {
              if (mounted) setState(() => _isExcluded = newExcluded);
            }
          },
        ),
      ),
    );
  }

  String _formatTotalDuration(int totalMs) {
    final d = Duration(milliseconds: totalMs);
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) {
      return '$hours hr $minutes min';
    }
    return '$minutes min';
  }

  void _showFolderOptionsMenu(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
  ) {
    HapticFeedback.lightImpact();
    PulsrSheetHelper.showPulsrSheet(
      context: context,
      builder: (ctx) => PulsrBottomSheet(
        title: Text(
          widget.folder.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          widget.folder.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (songs.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: Text(context.l10n.playNext),
                onTap: () {
                  Navigator.pop(ctx);
                  for (final s in songs.reversed) {
                    context.read<PlayerCubit>().playNext(s);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(context.l10n.addToQueue),
                onTap: () {
                  Navigator.pop(ctx);
                  context.read<PlayerCubit>().addAllToQueue(songs);
                },
              ),
            ],
            ListTile(
              leading: Icon(
                _isExcluded
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: _isExcluded ? p.accent : p.error,
              ),
              title: Text(
                _isExcluded
                    ? context.l10n.browseIncludeInScan
                    : context.l10n.browseExcludeFromScan,
              ),
              onTap: () {
                Navigator.pop(ctx);
                _toggleExclusion();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(context.l10n.browseCopy),
              subtitle: Text(
                widget.folder.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: widget.folder.path));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '${context.l10n.browseCopy}: ${widget.folder.name}'),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCircleButton({
    required IconData icon,
    required VoidCallback? onTap,
    required PulsrPalette p,
    Color? iconColor,
    String? tooltip,
    double size = 42,
    double iconSize = 20,
  }) {
    final isDark = p.isDark;
    final surface = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.14);
    final border = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.18);

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999.0),
        onTap: onTap != null
            ? () {
                HapticFeedback.lightImpact();
                onTap();
              }
            : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: surface,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: iconColor ?? Colors.white,
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  Widget _buildTopActionPill(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
  ) {
    final isDark = p.isDark;
    final surface = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.14);
    final border = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.18);

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(999.0),
        border: Border.all(color: border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(999.0)),
              onTap: () {
                HapticFeedback.lightImpact();
                Clipboard.setData(ClipboardData(text: widget.folder.path));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '${context.l10n.browseCopy}: ${widget.folder.name}'),
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                child: Icon(
                  Icons.share_outlined,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Container(
            width: 0.5,
            height: 18,
            color: Colors.white.withValues(alpha: 0.25),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(999.0)),
              onTap: () => _showFolderOptionsMenu(context, songs, p),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                child: Icon(
                  Icons.more_horiz_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBigWhitePlayButton(
    BuildContext context,
    PulsrPalette p,
    List<SongsTableData> songs,
  ) {
    final isEnabled = songs.isNotEmpty;

    return Material(
      color: isEnabled ? Colors.white : Colors.white.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      elevation: isEnabled ? 8 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: isEnabled
            ? () {
                HapticFeedback.mediumImpact();
                context.read<PlayerCubit>().playSong(songs.first, queue: songs);
              }
            : null,
        child: Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          child: const Padding(
            padding: EdgeInsets.only(left: 3),
            child: Icon(
              Icons.play_arrow_rounded,
              color: Colors.black,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImmersiveCover(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
  ) {
    if (songs.isNotEmpty) {
      final featuredSong = songs.firstWhere(
        (s) =>
            s.artworkUri != null ||
            s.remoteArtworkUrl != null ||
            s.albumId != null,
        orElse: () => songs.first,
      );

      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: CachedArtwork(
            id: featuredSong.id,
            albumId: featuredSong.albumId,
            remoteUrl: featuredSong.remoteArtworkUrl ?? featuredSong.artworkUri,
            size: 400,
            borderRadius: 0,
            highQuality: true,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            p.accentContainer,
            p.surfaceContainer,
            p.bg,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.folder_rounded,
          size: 100,
          color: p.accent.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildFeaturedCard(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
    int totalDurationMs,
  ) {
    if (songs.isEmpty) return const SizedBox.shrink();

    final featuredSong = songs.firstWhere(
      (s) =>
          s.artworkUri != null ||
          s.remoteArtworkUrl != null ||
          s.albumId != null,
      orElse: () => songs.first,
    );

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: Adaptive.pagePadding(context),
        vertical: AppSpacing.xs,
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: (p.isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadii.r16),
        border: Border.all(
          color: (p.isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          CachedArtwork(
            id: featuredSong.id,
            albumId: featuredSong.albumId,
            remoteUrl: featuredSong.remoteArtworkUrl ?? featuredSong.artworkUri,
            size: 54,
            borderRadius: AppRadii.r12,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${Formatters.formatTrackCount(songs.length).toUpperCase()} • ${_formatTotalDuration(totalDurationMs).toUpperCase()}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: p.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  featuredSong.album.isNotEmpty
                      ? featuredSong.album
                      : featuredSong.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  featuredSong.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Material(
            color: (p.isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                HapticFeedback.lightImpact();
                final shuffled = List<SongsTableData>.from(songs)..shuffle();
                context.read<PlayerCubit>().playSong(shuffled.first, queue: shuffled);
              },
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Icon(
                  Icons.shuffle_rounded,
                  size: 19,
                  color: p.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs(
    BuildContext context,
    PulsrPalette p,
    String fullPath,
  ) {
    final cleanPath = fullPath.replaceAll('\\', '/');
    final parts = cleanPath.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 32,
      margin: EdgeInsets.symmetric(
        horizontal: Adaptive.pagePadding(context),
        vertical: AppSpacing.xxs,
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: parts.length,
        separatorBuilder: (_, __) => Icon(
          Icons.chevron_right_rounded,
          size: 13,
          color: p.textTertiary.withValues(alpha: 0.5),
        ),
        itemBuilder: (context, index) {
          final isLast = index == parts.length - 1;
          final name = parts[index];
          final subPath = '/${parts.sublist(0, index + 1).join('/')}';

          return Center(
            child: Material(
              color: isLast
                  ? p.accent.withValues(alpha: 0.16)
                  : (p.isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppRadii.r8),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.r8),
                onTap: isLast
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        context.push(
                          '/folder',
                          extra: FolderItem(
                            path: subPath,
                            name: name,
                            songCount: 0,
                            isExcluded: false,
                          ),
                        );
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                      color: isLast ? p.accent : p.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSongRow(
    BuildContext context,
    List<SongsTableData> songs,
    int index,
    PulsrPalette p,
  ) {
    final song = songs[index];
    return BlocSelector<PlayerCubit, PlayerState,
        ({bool isActive, bool isPlaying})>(
      selector: (state) {
        final isActive = state.currentSong?.id == song.id;
        return (isActive: isActive, isPlaying: isActive && state.isPlaying);
      },
      builder: (context, playback) {
        final isActive = playback.isActive;
        final isPlaying = playback.isPlaying;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              context.read<PlayerCubit>().playSong(song, queue: songs);
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              SongInfoSheet.show(context, song: song);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Adaptive.pagePadding(context),
                vertical: AppSpacing.s8,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedArtwork(
                          id: song.id,
                          albumId: song.albumId,
                          remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                          size: 48,
                          borderRadius: AppRadii.r10,
                        ),
                        if (isActive)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.52),
                              borderRadius:
                                  BorderRadius.circular(AppRadii.r10),
                            ),
                            child: Center(
                              child: NowPlayingIndicator(
                                color: p.accent,
                                isPlaying: isPlaying,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isActive ? p.accent : p.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${song.artist} • ${song.album.isNotEmpty ? song.album : 'Single'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: p.textTertiary,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      SongInfoSheet.show(context, song: song);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final folder = widget.folder;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final headerHeight = (screenHeight * 0.40).clamp(310.0, 370.0);

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        body: StreamBuilder<Result<List<SongsTableData>>>(
          stream: _useCase.watchFolderSongs(folder.path).distinct(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const SkeletonList(
                padding: EdgeInsets.only(top: AppSpacing.xl),
              );
            }
            final loadFailed = snapshot.hasError ||
                (snapshot.data?.fold((l) => true, (_) => false) ?? false);
            if (loadFailed) {
              return EmptyStateWidget(
                icon: Icons.error_outline_rounded,
                iconColor: p.error,
                title: context.l10n.couldNotLoadFolderSongs,
                subtitle: context.l10n.libraryReadError,
                primaryActionLabel: context.l10n.retry,
                primaryActionIcon: Icons.refresh_rounded,
                onPrimaryAction: () => setState(() {}),
              );
            }

            final songs =
                snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ??
                    [];
            final totalDurationMs =
                songs.fold<int>(0, (sum, s) => sum + s.durationMs);

            return Center(
              child: ConstrainedBox(
                constraints: PulsrLayoutMetrics.contentConstraints(context),
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    // Apple Music Immersive Header (Hero Artwork + Blur Fade + Title + Round Action Buttons)
                    SliverAppBar(
                      expandedHeight: headerHeight,
                      pinned: true,
                      elevation: 0,
                      backgroundColor: p.bg,
                      surfaceTintColor: Colors.transparent,
                      leading: Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: Center(
                          child: _buildGlassCircleButton(
                            icon: Icons.arrow_back_ios_new_rounded,
                            iconSize: 18,
                            size: 38,
                            p: p,
                            tooltip: MaterialLocalizations.of(context)
                                .backButtonTooltip,
                            onTap: () {
                              if (context.canPop()) {
                                context.pop();
                              } else {
                                context.go('/');
                              }
                            },
                          ),
                        ),
                      ),
                      title: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _showCollapsedTitle ? 1.0 : 0.0,
                        child: Text(
                          folder.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      centerTitle: true,
                      actions: [
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: Center(
                            child: _buildTopActionPill(context, songs, p),
                          ),
                        ),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        collapseMode: CollapseMode.parallax,
                        background: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 1. Full-bleed Artwork
                            _buildImmersiveCover(context, songs, p),

                            // 2. Multi-stop Apple Music gradient overlay
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    stops: const [
                                      0.0,
                                      0.30,
                                      0.55,
                                      0.82,
                                      1.0,
                                    ],
                                    colors: [
                                      Colors.black.withValues(alpha: 0.45),
                                      Colors.transparent,
                                      p.bg.withValues(alpha: 0.35),
                                      p.bg.withValues(alpha: 0.88),
                                      p.bg,
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // 3. Title & Apple Music Action Row [ (i) ] [ (▶) ] [ (★) ]
                            Positioned(
                              left: AppSpacing.lg,
                              right: AppSpacing.lg,
                              bottom: AppSpacing.md,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    folder.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 27,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black54,
                                          blurRadius: 14,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      _buildGlassCircleButton(
                                        icon: Icons.info_outline_rounded,
                                        size: 40,
                                        iconSize: 20,
                                        p: p,
                                        tooltip: 'Folder Details',
                                        onTap: () => _showFolderOptionsMenu(
                                            context, songs, p),
                                      ),
                                      const SizedBox(width: AppSpacing.xl),
                                      _buildBigWhitePlayButton(
                                          context, p, songs),
                                      const SizedBox(width: AppSpacing.xl),
                                      _buildGlassCircleButton(
                                        icon: _isExcluded
                                            ? Icons.visibility_off_rounded
                                            : Icons.star_rounded,
                                        iconColor: _isExcluded
                                            ? p.error
                                            : Colors.white,
                                        size: 40,
                                        iconSize: 22,
                                        p: p,
                                        tooltip: _isExcluded
                                            ? context.l10n.browseIncludeInScan
                                            : context.l10n.browseExcludeFromScan,
                                        onTap: _toggleExclusion,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Featured Card & Breadcrumbs
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: AppSpacing.xs),
                          _buildFeaturedCard(
                              context, songs, p, totalDurationMs),
                          _buildBreadcrumbs(context, p, folder.path),
                          const SizedBox(height: AppSpacing.xs),

                          // Top Songs > Header
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              Adaptive.pagePadding(context),
                              AppSpacing.sm,
                              Adaptive.pagePadding(context),
                              AppSpacing.xs,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Top Songs',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                        letterSpacing: -0.3,
                                      ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20,
                                  color: p.textTertiary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Song List Items
                    if (songs.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: EmptyStateWidget(
                            icon: Icons.music_off_rounded,
                            title: context.l10n.browseNoTracksFound,
                            subtitle: context.l10n.browseNoTracksInFolder,
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.scrollBottom,
                        ),
                        sliver: SliverList.separated(
                          itemCount: songs.length,
                          separatorBuilder: (_, __) => Padding(
                            padding: EdgeInsets.only(
                              left: 64 + Adaptive.pagePadding(context),
                            ),
                            child: Divider(
                              height: 1,
                              thickness: 0.5,
                              color: p.hairline.withValues(alpha: 0.35),
                            ),
                          ),
                          itemBuilder: (context, index) =>
                              _buildSongRow(context, songs, index, p),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
