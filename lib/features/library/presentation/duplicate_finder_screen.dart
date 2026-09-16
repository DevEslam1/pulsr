// lib/features/library/presentation/duplicate_finder_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/duplicate_finder_service.dart';
import '../../../core/services/missing_artwork_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../player/cubit/player_cubit.dart';

class DuplicateFinderScreen extends StatefulWidget {
  const DuplicateFinderScreen({super.key});

  @override
  State<DuplicateFinderScreen> createState() => _DuplicateFinderScreenState();
}

enum _ResolveAction { keep, delete }

class _DuplicateFinderScreenState extends State<DuplicateFinderScreen> {
  late final DuplicateFinderService _finder;
  List<DuplicateGroup> _duplicateGroups = [];
  final Map<String, int> _keptSongByGroup = {};
  bool _isScanning = true;
  bool _isFetchingArtwork = false;

  @override
  void initState() {
    super.initState();
    _finder = getIt<DuplicateFinderService>();
    _scan();
  }

  Future<void> _scan() async {
    if (mounted) setState(() => _isScanning = true);
    var songs = const <SongsTableData>[];
    if (getIt.isRegistered<IMusicRepository>()) {
      final res = await getIt<IMusicRepository>().getAllSongs();
      songs = res.fold((_) => const <SongsTableData>[], (list) => list);
    }
    final duplicates = await _finder.findDuplicates(songs);
    if (!mounted) return;
    setState(() {
      _duplicateGroups = duplicates;
      _keptSongByGroup
          .removeWhere((key, _) => !duplicates.any((g) => g.key == key));
      _isScanning = false;
    });
  }

  Future<void> _fetchMissingArtwork() async {
    final l10n = context.l10n;
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: l10n.fetchMissingArtworkTitle,
      message: l10n.fetchMissingArtworkBody,
      icon: Icons.image_search_rounded,
      confirmLabel: l10n.fetchArtwork,
    );
    if (confirmed != true || !mounted) return;
    if (!getIt.isRegistered<MissingArtworkService>()) {
      PulsrToast.show(context,
          message: l10n.artworkServiceUnavailable, isError: true);
      return;
    }
    setState(() => _isFetchingArtwork = true);
    final count =
        await getIt<MissingArtworkService>().fetchAndPersistMissingArtwork();
    if (!mounted) return;
    setState(() => _isFetchingArtwork = false);
    PulsrToast.show(
      context,
      message: count == 0
          ? l10n.noMissingArtworkFound
          : l10n.updatedArtworkForAlbums(count),
      icon: Icons.image_rounded,
    );
  }

  Future<void> _showResolveSheet(
      DuplicateGroup group, SongsTableData song) async {
    final p = context.palette;
    final l10n = context.l10n;
    final action = await PulsrSheetHelper.showPulsrSheet<_ResolveAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(Icons.check_circle_outline_rounded, color: p.accent),
              title: Text(l10n.keepThisOne,
                  style: TextStyle(color: p.textPrimary)),
              subtitle: Text(
                l10n.markAsCopyToKeep(song.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textSecondary),
              ),
              onTap: () => Navigator.pop(ctx, _ResolveAction.keep),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: p.error),
              title: Text(l10n.deleteFile, style: TextStyle(color: p.error)),
              subtitle: Text(
                l10n.removeFromDevice(song.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textSecondary),
              ),
              onTap: () => Navigator.pop(ctx, _ResolveAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == _ResolveAction.keep) {
      _keepSong(group, song);
    } else {
      await _confirmDelete(group, song);
    }
  }

  void _keepSong(DuplicateGroup group, SongsTableData song) {
    setState(() => _keptSongByGroup[group.key] = song.id);
    PulsrToast.show(context,
        message: context.l10n.keepingTitle(song.title),
        icon: Icons.check_circle_rounded);
  }

  Future<void> _confirmDelete(DuplicateGroup group, SongsTableData song) async {
    final l10n = context.l10n;
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: l10n.deleteThisFile,
      message: l10n.deleteFileConfirmBody(song.title),
      icon: Icons.delete_outline_rounded,
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _deleteSong(group, song);
  }

  Future<void> _deleteSong(DuplicateGroup group, SongsTableData song) async {
    final l10n = context.l10n;
    if (!getIt.isRegistered<IMusicRepository>()) {
      PulsrToast.show(context,
          message: l10n.deleteIsUnavailable, isError: true);
      return;
    }
    final res = await getIt<IMusicRepository>().deleteSongs([song.id]);
    if (!mounted) return;
    res.fold(
      (failure) => PulsrToast.show(context,
          message: l10n.failedToDelete(failure.message), isError: true),
      (_) {
        setState(() {
          _duplicateGroups = _duplicateGroups
              .map((g) => DuplicateGroup(
                    key: g.key,
                    reason: g.reason,
                    songs: g.songs.where((s) => s.id != song.id).toList(),
                  ))
              .where((g) => g.songs.length > 1)
              .toList();
          if (_keptSongByGroup[group.key] == song.id) {
            _keptSongByGroup.remove(group.key);
          }
        });
        PulsrToast.show(context,
            message: l10n.deletedTitle(song.title),
            icon: Icons.delete_outline_rounded);
      },
    );
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
          title: Text(
            context.l10n.duplicateCleaner,
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: _isFetchingArtwork
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: p.primary,
                      ),
                    )
                  : Icon(Icons.image_search_rounded, color: p.textPrimary),
              tooltip: context.l10n.fetchMissingArtworkTooltip,
              onPressed: _isFetchingArtwork ? null : _fetchMissingArtwork,
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: p.textPrimary),
              tooltip: context.l10n.rescanLibrary,
              onPressed: _isScanning ? null : _scan,
            ),
          ],
        ),
        body: RefreshIndicator(
          color: p.primary,
          backgroundColor: p.surfaceCard,
          onRefresh: _scan,
          child: _buildBody(p),
        ),
      ),
    );
  }

  Widget _buildBody(PulsrPalette p) {
    if (_isScanning) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.3),
          Center(child: CircularProgressIndicator(color: p.primary)),
        ],
      );
    }

    if (_duplicateGroups.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 96, 24, 24),
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 64, color: p.accent),
          const SizedBox(height: 16),
          Text(
            context.l10n.noDuplicatesFound,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: p.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.libraryCleanlyOrganized,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary, fontSize: 13),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemCount: _duplicateGroups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final group = _duplicateGroups[index];
        final keptId = _keptSongByGroup[group.key];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      group.reason,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: p.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      context.l10n.tracksCount(group.songs.length),
                      style: TextStyle(fontSize: 11, color: p.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final song in group.songs)
                SongTile(
                  song: song,
                  onTap: () => context.read<PlayerCubit>().playSong(song),
                  onLongPress: () => _showResolveSheet(group, song),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (song.id == keptId)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            context.l10n.kept,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: p.accent,
                            ),
                          ),
                        ),
                      PopupMenuButton<_ResolveAction>(
                        icon: Icon(Icons.more_vert_rounded,
                            size: 20, color: p.textTertiary),
                        tooltip: context.l10n.resolveDuplicate,
                        onSelected: (action) {
                          if (action == _ResolveAction.keep) {
                            _keepSong(group, song);
                          } else {
                            _confirmDelete(group, song);
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: _ResolveAction.keep,
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline_rounded,
                                    size: 20, color: p.accent),
                                const SizedBox(width: 12),
                                Text(context.l10n.keepThisOne),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: _ResolveAction.delete,
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded,
                                    size: 20, color: p.error),
                                const SizedBox(width: 12),
                                Text(context.l10n.deleteFile),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
