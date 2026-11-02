// lib/features/library/presentation/artwork_grid_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';

class ArtworkGridScreen extends StatefulWidget {
  const ArtworkGridScreen({super.key});

  @override
  State<ArtworkGridScreen> createState() => _ArtworkGridScreenState();
}

class _ArtworkGridScreenState extends State<ArtworkGridScreen> {
  double _columnCount = 3.0;
  final ScrollController _scrollController = ScrollController();
  int _visibleCount = 60;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    try {
      await context.read<SettingsCubit>().rescanLibrary();
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to rescan library from artwork grid',
        error: e,
        stackTrace: st,
        category: 'ArtworkGrid',
      );
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      final total = context.read<LibraryCubit>().state.albums.length;
      if (mounted && _visibleCount < total) {
        setState(() {
          _visibleCount = (_visibleCount + 60).clamp(0, total);
        });
      }
    }
  }

  void _updateColumns(double nextValue, double minCols, double maxCols) {
    final prevRounded = _columnCount.round();
    final clamped = nextValue.clamp(minCols, maxCols);
    if (clamped == _columnCount) return;
    setState(() => _columnCount = clamped);
    if (clamped.round() != prevRounded) {
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final maxCols = context.isTablet ? 8.0 : 6.0;
    const minCols = 2.0;
    final activeCols = _columnCount.round();
    // High-density wall mode hides text labels when >= 5 columns for a clean
    // mosaic view.
    final isCompactWall = activeCols >= 5;

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: const PulsrBackButton(),
          title: Text(
            context.l10n.artworkWall,
            style: TextStyle(
              color: p.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: AppFontSize.bodyLarge,
            ),
          ),
          actions: [
            Container(
              margin: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              decoration: BoxDecoration(
                color: p.surfaceContainer,
                borderRadius: AppRadii.r12All,
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(Icons.zoom_out_rounded, size: 18),
                    color: activeCols < maxCols ? p.textPrimary : p.textTertiary,
                    tooltip: context.l10n.zoomOut,
                    onPressed: activeCols < maxCols
                        ? () => _updateColumns(
                              activeCols + 1.0,
                              minCols,
                              maxCols,
                            )
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                    ),
                    child: Text(
                      '$activeCols×',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w800,
                        color: p.accent,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(Icons.zoom_in_rounded, size: 18),
                    color: activeCols > minCols ? p.textPrimary : p.textTertiary,
                    tooltip: context.l10n.zoomIn,
                    onPressed: activeCols > minCols
                        ? () => _updateColumns(
                              activeCols - 1.0,
                              minCols,
                              maxCols,
                            )
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
        body: BlocBuilder<LibraryCubit, LibraryState>(
          builder: (context, state) {
            final albums = state.albums;

            if (albums.isEmpty) {
              return RefreshIndicator(
                onRefresh: _onRefresh,
                color: p.accent,
                backgroundColor: p.surfaceContainer,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.65,
                      child: PulsrEmptyState(
                        icon: Icons.album_outlined,
                        title: context.l10n.noAlbumsFound,
                        subtitle: context.l10n.rescanSubtitle,
                        primaryActionLabel: context.l10n.rescanLibrary,
                        primaryActionIcon: Icons.refresh_rounded,
                        onPrimaryAction: () =>
                            context.read<SettingsCubit>().rescanLibrary(),
                      ),
                    ),
                  ],
                ),
              );
            }

            final displayCount =
                albums.length > _visibleCount ? _visibleCount : albums.length;
            final spacing = isCompactWall ? 6.0 : 10.0;
            final cardRadius = isCompactWall ? AppRadii.r10All : AppRadii.r14All;
            final artworkRadius = isCompactWall ? 10.0 : 14.0;

            return RefreshIndicator(
              onRefresh: _onRefresh,
              color: p.accent,
              backgroundColor: p.surfaceContainer,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: Adaptive.contentConstraints(context),
                  child: GestureDetector(
                    onScaleUpdate: (details) {
                      if (details.scale > 1.15 && _columnCount > minCols) {
                        _updateColumns(_columnCount - 0.05, minCols, maxCols);
                      } else if (details.scale < 0.85 &&
                          _columnCount < maxCols) {
                        _updateColumns(_columnCount + 0.05, minCols, maxCols);
                      }
                    },
                    child: GridView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      addRepaintBoundaries: true,
                      addAutomaticKeepAlives: false,
                      padding: EdgeInsetsDirectional.fromSTEB(
                        context.pagePadding,
                        AppSpacing.xs,
                        context.pagePadding,
                        PulsrLayoutMetrics.scrollBottom(context),
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: activeCols,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        childAspectRatio: isCompactWall ? 1.0 : 0.80,
                      ),
                      itemCount: displayCount,
                      itemBuilder: (context, index) {
                        final album = albums[index];
                        return Semantics(
                          button: true,
                          label: '${album.title}, ${album.artist}',
                          child: Material(
                            color: p.surfaceCard,
                            borderRadius: cardRadius,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => context.push(
                                '/album?id=${album.id}',
                                extra: album,
                              ),
                              borderRadius: cardRadius,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: cardRadius,
                                  border: Border.all(
                                    color: p.hairline.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: CachedArtwork(
                                        id: album.id,
                                        type: ArtworkType.ALBUM,
                                        remoteUrl: album.artworkUri,
                                        size: 250,
                                        borderRadius: artworkRadius,
                                        fallbackIcon: Icons.album_rounded,
                                      ),
                                    ),
                                    if (!isCompactWall)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.xs,
                                          vertical: AppSpacing.s6,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              album.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: AppFontSize.label,
                                                fontWeight: FontWeight.w700,
                                                color: p.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              album.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: AppFontSize.tiny,
                                                color: p.textSecondary,
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
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}