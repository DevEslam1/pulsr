// lib/features/library/presentation/artwork_grid_screen.dart
import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class ArtworkGridScreen extends StatefulWidget {
  const ArtworkGridScreen({super.key});

  @override
  State<ArtworkGridScreen> createState() => _ArtworkGridScreenState();
}

class _ArtworkGridScreenState extends State<ArtworkGridScreen> {
  double _columnCount = 3.0;
  final ScrollController _scrollController = ScrollController();
  int _visibleCount = 50;

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
      ErrorLogger.log('Failed to rescan library from artwork grid',
          error: e, stackTrace: st, category: 'ArtworkGrid');
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      final total = context.read<LibraryCubit>().state.albums.length;
      if (mounted && _visibleCount < total) {
        setState(() {
          _visibleCount = (_visibleCount + 50).clamp(0, total);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final maxCols = context.isTablet ? 8.0 : 5.0;
    const minCols = 2.0;

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          backgroundColor: p.surface,
          elevation: 0,
          leading: const PulsrBackButton(),
          title: Text(
            context.l10n.artworkWall,
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
          ),
          actions: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.zoom_out_rounded),
                  tooltip: context.l10n.zoomOut,
                  onPressed: () {
                    if (_columnCount < maxCols) {
                      setState(() => _columnCount =
                          (_columnCount + 1).clamp(minCols, maxCols));
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_in_rounded),
                  tooltip: context.l10n.zoomIn,
                  onPressed: () {
                    if (_columnCount > minCols) {
                      setState(() => _columnCount =
                          (_columnCount - 1).clamp(minCols, maxCols));
                    }
                  },
                ),
              ],
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
                      child: EmptyStateWidget(
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
                      if (details.scale > 1.2 && _columnCount > minCols) {
                        setState(() => _columnCount =
                            (_columnCount - 0.05).clamp(minCols, maxCols));
                      } else if (details.scale < 0.8 && _columnCount < maxCols) {
                        setState(() => _columnCount =
                            (_columnCount + 0.05).clamp(minCols, maxCols));
                      }
                    },
                    child: GridView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      addRepaintBoundaries: true,
                      addAutomaticKeepAlives: false,
                      padding: EdgeInsetsDirectional.fromSTEB(
                          context.pagePadding, 8, context.pagePadding, 160),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _columnCount.round(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: displayCount,
                      itemBuilder: (context, index) {
                        final album = albums[index];
                        return Semantics(
                          button: true,
                          label: '${album.title}, ${album.artist}',
                          child: InkWell(
                      onTap: () =>
                          context.push('/album', extra: album),
                      borderRadius: BorderRadius.circular(AppRadii.r14),
                      child: Container(
                        decoration: BoxDecoration(
                          color: p.surfaceCard,
                          borderRadius: BorderRadius.circular(AppRadii.r14),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: CachedArtwork(
                                id: album.id,
                                type: ArtworkType.ALBUM,
                                size: 250,
                                borderRadius: 14,
                                fallbackIcon: Icons.album_rounded,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.s6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    album.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: AppFontSize.label,
                                      fontWeight: FontWeight.w600,
                                      color: p.textPrimary,
                                    ),
                                  ),
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
