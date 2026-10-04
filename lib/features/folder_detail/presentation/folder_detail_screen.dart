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
import '../../../core/responsive/breakpoints.dart';
import '../../../core/responsive/detail_scaffold.dart';
import '../../../core/responsive/pulsr_layout_metrics.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/async_state_builder.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/folder_usecases.dart';
import '../../library/cubit/library_cubit.dart';
import '../../library/cubit/library_state.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/cubit/player_state.dart';
import '../../sheets/song_info_sheet.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';
import '../../../core/widgets/pulsr_toast.dart';

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
  late final Stream<Result<List<SongsTableData>>> _songsStream;
  late bool _isExcluded;
  bool _showCollapsedTitle = false;

  @override
  void initState() {
    super.initState();
    _useCase = widget.folderUseCases ?? getIt<FolderUseCases>();
    // Memoized so rebuilds (scroll-collapse, exclusion toggle) do not
    // resubscribe to the folder's DB watch stream.
    _songsStream = _useCase.watchFolderSongs(widget.folder.path).distinct();
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
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final show = offset > 160;
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

  Future<void> _toggleFavoriteFolder(List<SongsTableData> songs) async {
    if (songs.isEmpty) return;
    HapticFeedback.lightImpact();
    LibraryCubit? libraryCubit;
    try {
      libraryCubit = context.read<LibraryCubit>();
    } catch (_) {}
    if (libraryCubit == null) return;

    final currentFavIds = libraryCubit.state.favorites.map((s) => s.id).toSet();
    final allFavorited = songs.every((s) => currentFavIds.contains(s.id));

    if (allFavorited) {
      for (final s in songs) {
        if (currentFavIds.contains(s.id)) {
          await libraryCubit.toggleFavorite(s.id);
        }
      }
      if (mounted) {
        PulsrToast.show(
          context,
          message: context.l10n.removeFromFavorites,
          icon: Icons.favorite_border_rounded,
        );
      }
    } else {
      for (final s in songs) {
        if (!currentFavIds.contains(s.id)) {
          await libraryCubit.toggleFavorite(s.id);
        }
      }
      if (mounted) {
        PulsrToast.show(
          context,
          message: context.l10n.favorite,
          icon: Icons.favorite_rounded,
        );
      }
    }
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
    final surface =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.14);
    final border =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.18);

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.full,
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
                color: AppColors.scrimAt(0.2),
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

  Widget _buildBigWhitePlayButton(
    BuildContext context,
    PulsrPalette p,
    List<SongsTableData> songs, {
    double size = 56,
    double iconSize = 34,
  }) {
    final isEnabled = songs.isNotEmpty;

    return Material(
      color: isEnabled ? Colors.white : AppColors.specularAt(0.45),
      shape: const CircleBorder(),
      elevation: isEnabled ? 8 : 0,
      shadowColor: AppColors.scrimAt(0.4),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: isEnabled
            ? () {
                HapticFeedback.mediumImpact();
                context.read<PlayerCubit>().playSong(songs.first, queue: songs);
              }
            : null,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 3),
            child: Icon(
              Icons.play_arrow_rounded,
              color: Colors.black,
              size: iconSize,
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

      final artworkWidget = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: CachedArtwork(
            id: featuredSong.id,
            albumId: featuredSong.albumId,
            remoteUrl: featuredSong.remoteArtworkUrl ?? featuredSong.artworkUri,
            size: 600,
            borderRadius: 0,
            highQuality: true,
          ),
        ),
      );

      if (!_isExcluded) return artworkWidget;

      return Stack(
        fit: StackFit.expand,
        children: [
          artworkWidget,
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + 12,
            end: AppSpacing.md,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: p.error.withValues(alpha: 0.92),
                borderRadius: AppRadii.r10All,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.visibility_off_rounded,
                      size: 14, color: Colors.white),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    context.l10n.folderPersistentExcludedBadge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

  Widget _buildCoverArt(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
    double size,
  ) {
    final List<({int id, int? albumId, String? remoteUrl})> distinctArts = [];
    final Set<String> seen = {};
    for (final s in songs) {
      final key = s.artworkUri ?? '${s.albumId ?? s.id}';
      if (!seen.contains(key)) {
        seen.add(key);
        distinctArts.add((
          id: s.id,
          albumId: s.albumId,
          remoteUrl: s.remoteArtworkUrl ?? s.artworkUri,
        ));
        if (distinctArts.length == 4) break;
      }
    }

    Widget content;
    if (distinctArts.length >= 4) {
      final half = size / 2;
      content = SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Row(
              children: [
                CachedArtwork(
                  id: distinctArts[0].id,
                  albumId: distinctArts[0].albumId,
                  remoteUrl: distinctArts[0].remoteUrl,
                  size: half,
                  borderRadius: 0,
                ),
                CachedArtwork(
                  id: distinctArts[1].id,
                  albumId: distinctArts[1].albumId,
                  remoteUrl: distinctArts[1].remoteUrl,
                  size: half,
                  borderRadius: 0,
                ),
              ],
            ),
            Row(
              children: [
                CachedArtwork(
                  id: distinctArts[2].id,
                  albumId: distinctArts[2].albumId,
                  remoteUrl: distinctArts[2].remoteUrl,
                  size: half,
                  borderRadius: 0,
                ),
                CachedArtwork(
                  id: distinctArts[3].id,
                  albumId: distinctArts[3].albumId,
                  remoteUrl: distinctArts[3].remoteUrl,
                  size: half,
                  borderRadius: 0,
                ),
              ],
            ),
          ],
        ),
      );
    } else if (distinctArts.isNotEmpty) {
      content = CachedArtwork(
        id: distinctArts.first.id,
        albumId: distinctArts.first.albumId,
        remoteUrl: distinctArts.first.remoteUrl,
        size: size,
        borderRadius: AppRadii.r20,
        highQuality: true,
      );
    } else {
      content = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              p.accentContainer,
              p.surfaceContainer,
            ],
          ),
        ),
        child: Center(
          child: Icon(
            _isExcluded ? Icons.folder_off_rounded : Icons.folder_rounded,
            size: size * 0.42,
            color: _isExcluded ? p.error : p.accent,
          ),
        ),
      );
    }

    return Semantics(
      image: true,
      label: widget.folder.name,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: AppRadii.r20All,
          border: Border.all(
            color:
                (p.isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.scrimAt(0.35),
              blurRadius: 28,
              spreadRadius: -4,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: p.accent.withValues(alpha: 0.14),
              blurRadius: 40,
              spreadRadius: -6,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadii.r20All,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              if (_isExcluded)
                Container(
                  color: AppColors.scrimAt(0.55),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: p.error.withValues(alpha: 0.92),
                        borderRadius: AppRadii.r8All,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility_off_rounded,
                              size: 14, color: Colors.white),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            context.l10n.folderPersistentExcludedBadge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedCard(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
    int totalDurationMs, {
    bool compact = false,
  }) {
    if (songs.isEmpty) return const SizedBox.shrink();

    final featuredSong = songs.firstWhere(
      (s) =>
          s.artworkUri != null ||
          s.remoteArtworkUrl != null ||
          s.albumId != null,
      orElse: () => songs.first,
    );

    final hPadding = compact ? AppSpacing.sm : AppSpacing.sm;
    final vPadding = compact ? AppSpacing.xs : AppSpacing.sm;
    final artSize = compact ? 46.0 : 54.0;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : Adaptive.pagePadding(context),
        vertical: compact ? AppSpacing.xxs : AppSpacing.xs,
      ),
      padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
      decoration: BoxDecoration(
        color: (p.isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        borderRadius: AppRadii.r16All,
        border: Border.all(
          color:
              (p.isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          CachedArtwork(
            id: featuredSong.id,
            albumId: featuredSong.albumId,
            remoteUrl: featuredSong.remoteArtworkUrl ?? featuredSong.artworkUri,
            size: artSize,
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
                    fontSize: AppFontSize.tiny,
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
                    fontSize: AppFontSize.body,
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
                    fontSize: AppFontSize.label,
                    color: p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Material(
            color:
                (p.isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                HapticFeedback.lightImpact();
                final shuffled = List<SongsTableData>.from(songs)..shuffle();
                context
                    .read<PlayerCubit>()
                    .playSong(shuffled.first, queue: shuffled);
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.shuffle_rounded,
                  size: 18,
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
    String fullPath, {
    bool compact = false,
  }) {
    final cleanPath = fullPath.replaceAll('\\', '/');
    final parts = cleanPath.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return const SizedBox.shrink();

    // Preserve the original root so breadcrumb taps navigate the *same* tree.
    // Previously every crumb was rebuilt as an absolute UNIX path ('/C:' for a
    // Windows drive), which dropped the drive/root and broke navigation.
    final isUnixAbsolute = cleanPath.startsWith('/');
    final isWindowsDrive = RegExp(r'^[A-Za-z]:$').hasMatch(parts.first);

    return Container(
      height: compact ? 28 : 32,
      margin: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : Adaptive.pagePadding(context),
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
          final joined = parts.sublist(0, index + 1).join('/');
          final subPath = isWindowsDrive && index == 0
              ? '$joined/'
              : isUnixAbsolute
                  ? '/$joined'
                  : joined;

          return Center(
            child: Material(
              color: isLast
                  ? p.accent.withValues(alpha: 0.16)
                  : (p.isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.05),
              borderRadius: AppRadii.r8All,
              child: InkWell(
                borderRadius: AppRadii.r8All,
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
                              color: AppColors.scrimAt(0.52),
                              borderRadius: AppRadii.r10All,
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
                            fontSize: AppFontSize.callout,
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
                            fontSize: AppFontSize.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget),
                    tooltip:
                        MaterialLocalizations.of(context).moreButtonTooltip,
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

  Widget _buildSplitHero(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
    int totalDurationMs,
  ) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isShort = screenHeight < 480;
    final coverSize = isShort
        ? (screenHeight * 0.28).clamp(96.0, 130.0)
        : (screenHeight * 0.28).clamp(130.0, 240.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCoverArt(context, songs, p, coverSize),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            widget.folder.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: isShort ? 17 : 20,
                  letterSpacing: -0.3,
                ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${Formatters.formatTrackCount(songs.length)} • ${_formatTotalDuration(totalDurationMs)}',
          style: TextStyle(
            color: p.textSecondary,
            fontSize: AppFontSize.caption,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Action Row: [ ( i ) ] [ ( ▶ ) ] [ ( ♥ ) ]
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildGlassCircleButton(
              icon: Icons.info_outline_rounded,
              size: isShort ? 36 : 40,
              iconSize: isShort ? 18 : 20,
              p: p,
              tooltip: 'Folder Details',
              onTap: () => _showFolderOptionsMenu(context, songs, p),
            ),
            const SizedBox(width: AppSpacing.md),
            _buildBigWhitePlayButton(
              context,
              p,
              songs,
              size: isShort ? 46 : 52,
              iconSize: isShort ? 26 : 30,
            ),
            const SizedBox(width: AppSpacing.md),
            BlocBuilder<LibraryCubit, LibraryState>(
              buildWhen: (prev, curr) => prev.favorites != curr.favorites,
              builder: (context, libState) {
                final allFavorited = songs.isNotEmpty &&
                    songs.every(
                        (s) => libState.favorites.any((fav) => fav.id == s.id));
                return _buildGlassCircleButton(
                  icon: allFavorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  iconColor: allFavorited ? p.favorite : Colors.white,
                  size: isShort ? 36 : 40,
                  iconSize: isShort ? 18 : 20,
                  p: p,
                  tooltip: allFavorited
                      ? context.l10n.removeFromFavorites
                      : context.l10n.favorite,
                  onTap: () => _toggleFavoriteFolder(songs),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildFeaturedCard(context, songs, p, totalDurationMs, compact: true),
        _buildBreadcrumbs(context, p, widget.folder.path, compact: true),
      ],
    );
  }

  Widget _buildSplitTrackList(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
  ) {
    if (songs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: PulsrEmptyState(
          icon: Icons.music_off_rounded,
          title: context.l10n.browseNoTracksFound,
          subtitle: context.l10n.browseNoTracksInFolder,
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: PulsrLayoutMetrics.contentMaxWidth(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Text(
                    context.l10n.browseTopTracks,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: AppFontSize.title,
                          letterSpacing: -0.3,
                        ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: p.textTertiary,
                  ),
                  const Spacer(),
                  Text(
                    Formatters.formatTrackCount(songs.length),
                    style: TextStyle(
                      color: p.textTertiary,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            for (int i = 0; i < songs.length; i++) ...[
              _buildSongRow(context, songs, i, p),
              if (i < songs.length - 1)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 64),
                  child: Divider(
                    height: 1,
                    thickness: 0.5,
                    color: p.hairline.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final folder = widget.folder;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLandscape = PulsrBreakpoint.isLandscape(context);
    final isTablet = Adaptive.isTablet(context);
    final isWide = screenWidth >= 800;

    // Responsive split threshold:
    // Any landscape mode, or any tablet in landscape, or wide tablet/desktop (>= 800dp)
    final shouldSplit = isLandscape || (isTablet && isWide);

    // Fluid height for portrait header based on screen dimensions and text scaler
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.3);
    final headerHeight = (screenHeight * (isTablet ? 0.34 : 0.38) * textScale)
        .clamp(280.0, isTablet ? 420.0 : 360.0);

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        body: StreamBuilder<Result<List<SongsTableData>>>(
          stream: _songsStream,
          builder: (context, snapshot) {
            Widget buildContent(List<SongsTableData> songs) {
              final totalDurationMs =
                  songs.fold<int>(0, (sum, s) => sum + s.durationMs);

              // Responsive Layout: Tablet / Landscape Master-Detail Split
              if (shouldSplit) {
                return DetailScaffold(
                  leading: const PulsrBackButton(),
                  leftPaneFlex: isLandscape ? 4.2 : 4.0,
                  rightPaneFlex: isLandscape ? 5.8 : 6.0,
                  hero: _buildSplitHero(context, songs, p, totalDurationMs),
                  body: _buildSplitTrackList(context, songs, p),
                );
              }

              // Portrait Phone / Narrow View: Collapsing Immersive Apple Music layout
              return CustomScrollView(
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
                    leading: const PulsrBackButton(),
                    title: AnimatedOpacity(
                      duration: PulsrMotion.state,
                      opacity: _showCollapsedTitle ? 1.0 : 0.0,
                      child: Text(
                        folder.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.subtitle,
                        ),
                      ),
                    ),
                    centerTitle: true,
                    flexibleSpace: LayoutBuilder(
                      builder: (context, constraints) {
                        final safeTop = MediaQuery.paddingOf(context).top;
                        final minExtent = kToolbarHeight + safeTop;
                        final maxExtent = headerHeight;
                        final delta = maxExtent - minExtent;
                        final currentExtent = constraints.maxHeight;
                        final t = delta > 0
                            ? ((maxExtent - currentExtent) / delta)
                                .clamp(0.0, 1.0)
                            : 0.0;
                        final heroContentOpacity =
                            (1.0 - (t * 2.2)).clamp(0.0, 1.0);

                        return FlexibleSpaceBar(
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
                                        AppColors.scrimLight,
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
                              PositionedDirectional(
                                start: AppSpacing.lg,
                                end: AppSpacing.lg,
                                bottom: AppSpacing.md,
                                child: Opacity(
                                  opacity: heroContentOpacity,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        folder.name,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: screenWidth < 360
                                              ? 22.0
                                              : (isTablet ? 30.0 : 26.0),
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5,
                                          color: Colors.white,
                                          shadows: const [
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
                                          SizedBox(
                                            width: screenWidth < 360
                                                ? AppSpacing.md
                                                : AppSpacing.xl,
                                          ),
                                          _buildBigWhitePlayButton(
                                              context, p, songs),
                                          SizedBox(
                                            width: screenWidth < 360
                                                ? AppSpacing.md
                                                : AppSpacing.xl,
                                          ),
                                          BlocBuilder<LibraryCubit,
                                              LibraryState>(
                                            buildWhen: (prev, curr) =>
                                                prev.favorites !=
                                                curr.favorites,
                                            builder: (context, libState) {
                                              final allFavorited = songs
                                                      .isNotEmpty &&
                                                  songs.every((s) => libState
                                                      .favorites
                                                      .any((fav) =>
                                                          fav.id == s.id));
                                              return _buildGlassCircleButton(
                                                icon: allFavorited
                                                    ? Icons.favorite_rounded
                                                    : Icons
                                                        .favorite_border_rounded,
                                                iconColor: allFavorited
                                                    ? p.favorite
                                                    : Colors.white,
                                                size: 40,
                                                iconSize: 22,
                                                p: p,
                                                tooltip: allFavorited
                                                    ? context.l10n
                                                        .removeFromFavorites
                                                    : context.l10n.favorite,
                                                onTap: () =>
                                                    _toggleFavoriteFolder(
                                                        songs),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Featured Card & Breadcrumbs & Section Header (Centered with content constraints)
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints:
                            PulsrLayoutMetrics.contentConstraints(context),
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
                              padding: EdgeInsetsDirectional.fromSTEB(
                                Adaptive.pagePadding(context),
                                AppSpacing.sm,
                                Adaptive.pagePadding(context),
                                AppSpacing.xs,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    context.l10n.browseTopTracks,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          fontSize: AppFontSize.title,
                                          letterSpacing: -0.3,
                                        ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                    color: p.textTertiary,
                                  ),
                                  const Spacer(),
                                  Text(
                                    Formatters.formatTrackCount(songs.length),
                                    style: TextStyle(
                                      color: p.textTertiary,
                                      fontSize: AppFontSize.caption,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Song List Items
                  if (songs.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: PulsrEmptyState(
                          icon: Icons.music_off_rounded,
                          title: context.l10n.browseNoTracksFound,
                          subtitle: context.l10n.browseNoTracksInFolder,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.only(
                        bottom: PulsrLayoutMetrics.scrollBottom(context),
                      ),
                      sliver: SliverList.separated(
                        itemCount: songs.length,
                        separatorBuilder: (_, __) => Center(
                          child: ConstrainedBox(
                            constraints:
                                PulsrLayoutMetrics.contentConstraints(context),
                            child: Padding(
                              padding: EdgeInsetsDirectional.only(
                                start: 64 + Adaptive.pagePadding(context),
                              ),
                              child: Divider(
                                height: 1,
                                thickness: 0.5,
                                color: p.hairline.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ),
                        itemBuilder: (context, index) => Center(
                          child: ConstrainedBox(
                            constraints:
                                PulsrLayoutMetrics.contentConstraints(context),
                            child: _buildSongRow(context, songs, index, p),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }

            final errorView = PulsrEmptyState(
              icon: Icons.error_outline_rounded,
              iconColor: p.error,
              title: context.l10n.couldNotLoadFolderSongs,
              subtitle: context.l10n.libraryReadError,
              primaryActionLabel: context.l10n.retry,
              primaryActionIcon: Icons.refresh_rounded,
              onPrimaryAction: () => setState(() {}),
            );

            return AsyncStateBuilder<Result<List<SongsTableData>>>(
              snapshot: snapshot,
              loadingWidget: const SkeletonList(
                padding: EdgeInsets.only(top: AppSpacing.xl),
              ),
              emptyWidget: buildContent(const []),
              onError: (_) => errorView,
              onData: (result) => result.fold(
                (_) => errorView,
                buildContent,
              ),
            );
          },
        ),
      ),
    );
  }
}
