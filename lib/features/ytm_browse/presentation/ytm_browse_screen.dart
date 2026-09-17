// lib/features/ytm_browse/presentation/ytm_browse_screen.dart
import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/ytm_browse_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/widgets/pulsr_back_button.dart';
import '../../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../data/db/app_database.dart';
import '../../player/cubit/player_cubit.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';

class YtmBrowseScreen extends StatefulWidget {
  const YtmBrowseScreen({super.key});

  @override
  State<YtmBrowseScreen> createState() => _YtmBrowseScreenState();
}

class _YtmBrowseScreenState extends State<YtmBrowseScreen> {
  late final YtmBrowseService _browseService;
  List<YtmBrowseSection> _sections = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _browseService = getIt<YtmBrowseService>();
    _loadFeed();
  }

  String? _error;
  bool _loadFailed = false;
  Future<void> _loadFeed() async {
    if (_sections.isEmpty) {
      setState(() {
        _isLoading = true;
        _error = null;
        _loadFailed = false;
      });
    }
    try {
      final sections = await _browseService.getHomeFeed();
      if (mounted) {
        setState(() {
          _sections = sections;
          _isLoading = false;
          // Empty feed is not an error — offline/error surfaces via
          // exception path below. Empty just shows the empty state.
          _loadFailed = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
          _error = context.l10n.browseFailedLoadFeed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          backgroundColor: p.surface,
          elevation: 0,
          leading: const PulsrBackButton(),
          title: Text(context.l10n.ytmExplore,
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: p.textPrimary),
            onPressed: _loadFeed,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: p.primary))
          : (_error != null && _loadFailed)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            color: p.textSecondary, size: 40),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.textSecondary)),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _loadFeed,
                            child: Text(context.l10n.retry)),
                      ],
                    ),
                  ),
                )
              : _sections.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.explore_off_rounded,
                                color: p.textSecondary, size: 40),
                            const SizedBox(height: 12),
                            Text(context.l10n.browseNoRecommendations,
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(color: p.textSecondary)),
                            const SizedBox(height: 12),
                            FilledButton(
                                onPressed: _loadFeed,
                                child: Text(context.l10n.retry)),
                          ],
                        ),
                      ),
                    )
              : RefreshIndicator(
              onRefresh: _loadFeed,
              color: p.primary,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: Adaptive.contentConstraints(context),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 16, bottom: 160),
                    itemCount: _sections.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 24),
                    itemBuilder: (context, index) {
                      final section = _sections[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  section.title,
                                  style: TextStyle(
                                    color: p.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (section.subtitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    section.subtitle!,
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 210,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: section.items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 14),
                              itemBuilder: (context, i) {
                                final item = section.items[i];
                                final queueSongs = [
                                  for (final e in section.items)
                                    e.toYtmTrack().toSongData()
                                ];
                                return _buildBrowseCard(
                                    context, item, queueSongs, p);
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildBrowseCard(BuildContext context, YtmBrowseItem item,
      List<SongsTableData> queueSongs, PulsrPalette p) {
    final song = item.toYtmTrack().toSongData();
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context.read<PlayerCubit>().playSong(song, queue: queueSongs);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                item.artworkUrl != null
                    ? Image.network(
                        item.artworkUrl!,
                        width: 140,
                        height: 130,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 140,
                          height: 130,
                          color: p.surfaceContainer,
                          child: Icon(Icons.music_note_rounded,
                              color: p.primary, size: 36),
                        ),
                      )
                    : Container(
                        width: 140,
                        height: 130,
                        color: p.surfaceContainer,
                        child: Icon(Icons.music_note_rounded,
                            color: p.primary, size: 36),
                      ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: YtmDownloadButton(song: song, iconSize: 16),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.hasKnownDuration
                        ? '${item.subtitle} • ${_formatDuration(item.duration)}'
                        : item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
