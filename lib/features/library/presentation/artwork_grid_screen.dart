// lib/features/library/presentation/artwork_grid_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/widgets/cached_artwork.dart';
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

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      if (mounted) {
        setState(() {
          _visibleCount += 50;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.surface,
        elevation: 0,
        title: Text(
          'Album Artwork Wall',
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.bold),
        ),
        actions: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.zoom_out_rounded),
                onPressed: () {
                  if (_columnCount < 5) setState(() => _columnCount += 1);
                },
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in_rounded),
                onPressed: () {
                  if (_columnCount > 2) setState(() => _columnCount -= 1);
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
            return Center(
              child: Text(
                'No albums found in library',
                style: TextStyle(color: p.textSecondary),
              ),
            );
          }

          final displayCount = albums.length > _visibleCount ? _visibleCount : albums.length;

          return GestureDetector(
            onScaleUpdate: (details) {
              if (details.scale > 1.2 && _columnCount > 2) {
                setState(() => _columnCount = (_columnCount - 0.05).clamp(2.0, 5.0));
              } else if (details.scale < 0.8 && _columnCount < 5) {
                setState(() => _columnCount = (_columnCount + 0.05).clamp(2.0, 5.0));
              }
            },
            child: GridView.builder(
              controller: _scrollController,
              addRepaintBoundaries: true,
              addAutomaticKeepAlives: false,
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 120),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columnCount.round(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.82,
              ),
              itemCount: displayCount,
              itemBuilder: (context, index) {
                final album = albums[index];
                return InkWell(
                  onTap: () => context.push('/album/${album.id}', extra: album),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.surfaceCard,
                      borderRadius: BorderRadius.circular(14),
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
                          padding: const EdgeInsets.all(6.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                album.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: p.textPrimary,
                                ),
                              ),
                              Text(
                                album.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
