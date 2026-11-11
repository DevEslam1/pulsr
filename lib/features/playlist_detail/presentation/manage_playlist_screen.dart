// lib/features/playlist_detail/presentation/manage_playlist_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../core/constants/app_radii.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/failures.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/search_algorithm_utils.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/highlighted_text.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_progress.dart';
import '../../../core/widgets/pulsr_search_field.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../domain/usecases/playlist_usecases.dart';

class ManagePlaylistScreen extends StatefulWidget {
  final PlaylistsTableData playlist;

  const ManagePlaylistScreen({super.key, required this.playlist});

  @override
  State<ManagePlaylistScreen> createState() => _ManagePlaylistScreenState();
}

class _ManagePlaylistScreenState extends State<ManagePlaylistScreen> {
  final Set<int> _selectedSongIds = {};
  final Set<int> _initialSongIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSelectedOnly = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  late final PlaylistUseCases _playlistUseCases;
  late final GetSongsUseCase _getSongsUseCase;
  late final Stream<Result<List<SongsTableData>>> _songsStream;

  @override
  void initState() {
    super.initState();
    _playlistUseCases = getIt<PlaylistUseCases>();
    _getSongsUseCase = getIt<GetSongsUseCase>();
    _songsStream = _getSongsUseCase
        .watchSongs()
        .distinct()
        .asBroadcastStream(onCancel: (sub) => sub.cancel());
    _loadInitialPlaylistSongs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialPlaylistSongs() async {
    final stream = _playlistUseCases.watchPlaylistSongs(widget.playlist.id);
    Result<List<SongsTableData>> firstBatch;
    try {
      firstBatch = await stream.first.timeout(const Duration(seconds: 4));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e is TimeoutException
            ? 'Loading the playlist took too long. Please retry.'
            : e.toString();
      });
      return;
    }
    if (!mounted) return;
    firstBatch.fold(
      (failure) {
        setState(() {
          _isLoading = false;
          _loadError = failure.message;
        });
      },
      (songs) {
        setState(() {
          _initialSongIds
            ..clear()
            ..addAll(songs.map((s) => s.id));
          _selectedSongIds
            ..clear()
            ..addAll(_initialSongIds);
          _isLoading = false;
          _loadError = null;
        });
      },
    );
  }

  List<SongsTableData> _filterSongs(List<SongsTableData> songs) {
    Iterable<SongsTableData> filtered = songs;
    if (_showSelectedOnly) {
      filtered = filtered.where(
        (s) =>
            _selectedSongIds.contains(s.id) || _initialSongIds.contains(s.id),
      );
    }
    if (_searchQuery.trim().isEmpty) return filtered.toList();
    final query = SearchAlgorithmUtils.normalize(_searchQuery);
    return filtered.where((s) {
      return SearchAlgorithmUtils.normalize(s.title).contains(query) ||
          SearchAlgorithmUtils.normalize(s.artist).contains(query) ||
          SearchAlgorithmUtils.normalize(s.album).contains(query);
    }).toList();
  }

  void _toggleSong(int id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedSongIds.remove(id)) {
        _selectedSongIds.add(id);
      }
    });
  }

  void _resetSelection() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedSongIds
        ..clear()
        ..addAll(_initialSongIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return StreamBuilder<Result<List<SongsTableData>>>(
      stream: _songsStream,
      builder: (context, snapshot) {
        final allSongs =
            snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];
        final visibleSongs = _filterSongs(allSongs);
        final isAllSelected = visibleSongs.isNotEmpty &&
            visibleSongs.every((s) => _selectedSongIds.contains(s.id));

        return PulsrPagePopScope(
          child: Scaffold(
            backgroundColor: p.bg,
            appBar: AppBar(
              backgroundColor: p.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: const PulsrBackButton(),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.managePlaylist,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600,
                      color: p.textSecondary,
                    ),
                  ),
                  Text(
                    widget.playlist.name,
                    style: TextStyle(
                      fontSize: AppFontSize.bodyLarge,
                      fontWeight: FontWeight.w800,
                      color: p.accent,
                      letterSpacing: -0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              actions: [
                if (allSongs.isNotEmpty)
                  IconButton(
                    tooltip:
                        context.l10n.selectedCount(_selectedSongIds.length),
                    icon: Icon(
                      _showSelectedOnly
                          ? Icons.filter_alt_rounded
                          : Icons.filter_alt_outlined,
                      color: _showSelectedOnly ? p.accent : p.textSecondary,
                      size: 20,
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _showSelectedOnly = !_showSelectedOnly);
                    },
                  ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                  child: TextButton.icon(
                    onPressed: visibleSongs.isEmpty
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              if (isAllSelected) {
                                for (final s in visibleSongs) {
                                  _selectedSongIds.remove(s.id);
                                }
                              } else {
                                for (final s in visibleSongs) {
                                  _selectedSongIds.add(s.id);
                                }
                              }
                            });
                          },
                    icon: Icon(
                      isAllSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      color: p.accent,
                      size: 18,
                    ),
                    label: Text(
                      isAllSelected
                          ? context.l10n.browseDeselect
                          : context.l10n.selectAllAction,
                      style: TextStyle(
                        color: p.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.bodySmall,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: Adaptive.contentConstraints(context),
                child: _isLoading
                    ? const SkeletonList(
                        padding: EdgeInsets.only(top: AppSpacing.xs),
                      )
                    : _loadError != null
                        ? PulsrEmptyState(
                            icon: Icons.error_outline_rounded,
                            title: context.l10n.playlistLoadFailed,
                            subtitle: _loadError!,
                            primaryActionLabel: context.l10n.retry,
                            onPrimaryAction: () {
                              setState(() {
                                _isLoading = true;
                                _loadError = null;
                              });
                              _loadInitialPlaylistSongs();
                            },
                          )
                        : Column(
                            children: [
                              PulsrSearchField(
                                controller: _searchController,
                                hintText: context.l10n.browseSearchSongsHint,
                                margin: EdgeInsetsDirectional.fromSTEB(
                                  Adaptive.pagePadding(context),
                                  AppSpacing.sm,
                                  Adaptive.pagePadding(context),
                                  AppSpacing.xs,
                                ),
                                onChanged: (val) {
                                  if (mounted) {
                                    setState(() => _searchQuery = val);
                                  }
                                },
                                onClear: () {
                                  if (mounted) {
                                    setState(() => _searchQuery = '');
                                  }
                                },
                              ),
                              _buildCountBanner(p),
                              Expanded(
                                child: visibleSongs.isEmpty
                                    ? PulsrEmptyState(
                                        icon: Icons.search_off_rounded,
                                        title: _searchQuery.isEmpty
                                            ? context
                                                .l10n.browseNoSongsInLibrary
                                            : '${context.l10n.browseNoSongsMatch} "$_searchQuery"',
                                      )
                                    : ListView.builder(
                                        physics: const BouncingScrollPhysics(),
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior
                                                .onDrag,
                                        addAutomaticKeepAlives: false,
                                        addRepaintBoundaries: true,
                                        padding: EdgeInsetsDirectional.only(
                                          top: AppSpacing.xxs,
                                          bottom: 100,
                                          start: Adaptive.pagePadding(context),
                                          end: Adaptive.pagePadding(context),
                                        ),
                                        itemCount: visibleSongs.length,
                                        itemBuilder: (context, index) {
                                          final song = visibleSongs[index];
                                          final isSelected = _selectedSongIds
                                              .contains(song.id);
                                          final wasInPlaylist =
                                              _initialSongIds.contains(song.id);
                                          final isNewlyAdded =
                                              isSelected && !wasInPlaylist;
                                          final isMarkedRemoved =
                                              !isSelected && wasInPlaylist;

                                          return StaggeredListItem(
                                            index: index,
                                            child: _ManageSongRow(
                                              song: song,
                                              query: _searchQuery,
                                              isSelected: isSelected,
                                              isNewlyAdded: isNewlyAdded,
                                              isMarkedRemoved: isMarkedRemoved,
                                              palette: p,
                                              onTap: () => _toggleSong(song.id),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
              ),
            ),
            bottomNavigationBar: _buildBottomActionBar(p),
          ),
        );
      },
    );
  }

  Widget _buildCountBanner(PulsrPalette p) {
    final toAdd = _selectedSongIds.difference(_initialSongIds).length;
    final toRemove = _initialSongIds.difference(_selectedSongIds).length;
    final hasChanges = toAdd > 0 || toRemove > 0;

    if (!hasChanges) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        Adaptive.pagePadding(context),
        AppSpacing.xxs,
        Adaptive.pagePadding(context),
        AppSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: p.accent.withValues(alpha: p.isDark ? 0.14 : 0.08),
          borderRadius: AppRadii.r14All,
          border: Border.all(
            color: p.accent.withValues(alpha: 0.32),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_mosaic_rounded, color: p.accent, size: 16),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                '${context.l10n.browseWillAdd}:$toAdd ${context.l10n.browseTracks} •${context.l10n.browseWillRemove}: $toRemove${context.l10n.browseTracks}',
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            InkWell(
              borderRadius: AppRadii.r8All,
              onTap: _resetSelection,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 2,
                ),
                child: Icon(
                  Icons.restart_alt_rounded,
                  size: 18,
                  color: p.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(PulsrPalette p) {
    final toAdd = _selectedSongIds.difference(_initialSongIds).length;
    final toRemove = _initialSongIds.difference(_selectedSongIds).length;
    final hasChanges = toAdd > 0 || toRemove > 0;

    return Container(
      padding: EdgeInsetsDirectional.fromSTEB(
        Adaptive.pagePadding(context),
        AppSpacing.sm,
        Adaptive.pagePadding(context),
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.hairline, width: 1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.scrimAt(0.22),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: Adaptive.contentConstraints(context),
          child: FilledButton.icon(
            onPressed: hasChanges && !_isSaving ? _applyChanges : null,
            icon: _isSaving
                ? PulsrProgressBar.circular(
                    size: AppSpacing.s18,
                    strokeWidth: 2,
                    color: p.onAccent,
                  )
                : const Icon(Icons.check_circle_outline_rounded, size: 20),
            label: Text(
              hasChanges
                  ? '${context.l10n.browseApplyChanges} (+$toAdd / -$toRemove)'
                  : '${context.l10n.browseNoChangesToSave} (${_selectedSongIds.length})',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: AppFontSize.body,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: hasChanges ? p.accent : p.surfaceContainerHigh,
              foregroundColor: hasChanges ? p.onAccent : p.textTertiary,
              elevation: hasChanges ? 3 : 0,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.buttonRadius,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyChanges() async {
    if (_isSaving) return;
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);

    final toAdd = _selectedSongIds.difference(_initialSongIds).toList();
    final toRemove = _initialSongIds.difference(_selectedSongIds).toList();

    String? failureMessage;
    try {
      if (toAdd.isNotEmpty) {
        final res = await _playlistUseCases.addSongsToPlaylist(
          widget.playlist.id,
          toAdd,
        );
        failureMessage = res.fold<String?>((f) => f.message, (_) => null);
      }

      if (failureMessage == null) {
        for (final songId in toRemove) {
          final res = await _playlistUseCases.removeSongFromPlaylist(
            widget.playlist.id,
            songId,
          );
          failureMessage = res.fold<String?>((f) => f.message, (_) => null);
          if (failureMessage != null) break;
        }
      }
    } catch (e) {
      failureMessage = e.toString();
    }

    if (!mounted) return;

    if (failureMessage != null) {
      setState(() => _isSaving = false);
      PulsrToast.show(
        context,
        message: failureMessage,
        icon: Icons.error_outline_rounded,
        isError: true,
      );
      return;
    }

    PulsrToast.show(
      context,
      message:
          '${context.l10n.browsePlaylistUpdated} (+${toAdd.length}, -${toRemove.length})',
      icon: Icons.check_circle_rounded,
    );
    Navigator.of(context).pop(true);
  }
}

class _ManageSongRow extends StatelessWidget {
  final SongsTableData song;
  final String query;
  final bool isSelected;
  final bool isNewlyAdded;
  final bool isMarkedRemoved;
  final PulsrPalette palette;
  final VoidCallback onTap;

  const _ManageSongRow({
    required this.song,
    required this.query,
    required this.isSelected,
    required this.isNewlyAdded,
    required this.isMarkedRemoved,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final subtitle =
        song.album.isNotEmpty ? '${song.artist} •${song.album}' : song.artist;

    final Color borderColor;
    final Color bgColor;
    if (isNewlyAdded) {
      borderColor = p.accent.withValues(alpha: 0.45);
      bgColor = p.accent.withValues(alpha: p.isDark ? 0.14 : 0.09);
    } else if (isMarkedRemoved) {
      borderColor = p.error.withValues(alpha: 0.38);
      bgColor = p.error.withValues(alpha: p.isDark ? 0.10 : 0.06);
    } else if (isSelected) {
      borderColor = p.accent.withValues(alpha: 0.28);
      bgColor = p.accent.withValues(alpha: p.isDark ? 0.09 : 0.06);
    } else {
      borderColor = Colors.transparent;
      bgColor = Colors.transparent;
    }

    final titleStyle = TextStyle(
      color: isMarkedRemoved ? p.textSecondary : p.textPrimary,
      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
      fontSize: AppFontSize.body,
      decoration: isMarkedRemoved ? TextDecoration.lineThrough : null,
    );
    final subtitleStyle = TextStyle(
      color: p.textSecondary,
      fontSize: AppFontSize.label,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: AnimatedContainer(
        duration: context.motion(PulsrMotion.state),
        curve: context.motionCurve(PulsrMotion.enter),
        decoration: BoxDecoration(
          borderRadius: AppRadii.cardRadius,
          color: bgColor,
          border: Border.all(color: borderColor, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadii.cardRadius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10,
                vertical: AppSpacing.s6,
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    activeColor: p.accent,
                    checkColor: p.onAccent,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r6),
                    ),
                    onChanged: (_) => onTap(),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  CachedArtwork(
                    id: song.id,
                    albumId: song.albumId,
                    remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                    type: ArtworkType.AUDIO,
                    size: 46,
                    borderRadius: 10,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PulsrHighlightedText(
                          text: song.title,
                          query: query,
                          baseStyle: titleStyle,
                          matchStyle: titleStyle.copyWith(
                            color: p.accent,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        PulsrHighlightedText(
                          text: subtitle,
                          query: query,
                          baseStyle: subtitleStyle,
                          matchStyle: subtitleStyle.copyWith(
                            color: p.accent,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isNewlyAdded || isMarkedRemoved) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (isNewlyAdded ? p.accent : p.error)
                            .withValues(alpha: 0.16),
                        borderRadius: AppRadii.r6All,
                      ),
                      child: Text(
                        isNewlyAdded ? '+1' : '-1',
                        style: TextStyle(
                          color: isNewlyAdded ? p.accent : p.error,
                          fontSize: AppFontSize.tiny,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                  if (song.durationMs > 0) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      Formatters.formatDurationMs(song.durationMs),
                      style: TextStyle(
                        color: p.textTertiary,
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
