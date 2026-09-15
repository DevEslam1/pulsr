import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/playlist_share_service.dart';
import '../../../core/services/playlist_suggestions_service.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../domain/models/smart_playlist_criteria.dart';
import '../../../domain/models/ytm_track.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../domain/usecases/playlist_io_usecases.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import '../../../data/db/app_database.dart';
import '../../auth/presentation/ytm_web_login_sheet.dart';
import '../../player/cubit/player_cubit.dart';
import '../../playlist_detail/presentation/playlist_detail_screen.dart';
import '../../playlist_detail/presentation/online_playlist_detail_screen.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../cubit/playlist_cubit.dart';
import '../cubit/playlist_state.dart';

enum _PlaylistTabMode { local, online }

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  _PlaylistTabMode _selectedTab = _PlaylistTabMode.local;
  PlaylistsTableData? _selectedPlaylist;
  List<PlaylistSuggestion> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuggestions());
  }

  /// Suggestion service output is optional and non-intrusive: it stays hidden
  /// until real library songs produce at least one suggestion.
  Future<void> _loadSuggestions() async {
    try {
      final result = await getIt<GetSongsUseCase>().getAllSongs();
      final allSongs = result.fold((_) => <SongsTableData>[], (songs) => songs);
      final suggestions =
          getIt<PlaylistSuggestionsService>().generateSuggestions(allSongs);
      if (!mounted) return;
      setState(() => _suggestions = suggestions);
    } catch (_) {
      // Suggestions are a best-effort convenience; stay hidden on failure.
    }
  }

  Future<void> _createPlaylistFromSuggestion(
      PlaylistSuggestion suggestion) async {
    final messenger = ScaffoldMessenger.of(context);
    // Capture localized strings before async gaps (no context-across-gap).
    final createFailedText = context.l10n.suggestCreateFailed;
    final loc = context.l10n;
    final useCases = getIt<PlaylistUseCases>();
    try {
      final created = await useCases.createPlaylist(suggestion.title);
      final playlistId = created.fold<int?>((_) => null, (id) => id);
      if (playlistId == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(createFailedText)),
        );
        return;
      }
      // Suggestions already carry resolved songs; persist them by id.
      final songIds = suggestion.songs.map((s) => s.id).toList();
      if (songIds.isNotEmpty) {
        await useCases.addSongsToPlaylist(playlistId, songIds);
      }
      messenger.showSnackBar(
        SnackBar(
          content:
              Text(loc.suggestedCreated(suggestion.title, songIds.length)),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(createFailedText)),
      );
    }
  }

  void _onSelectPlaylist(PlaylistsTableData pl) {
    if (context.isTabletLandscape) {
      setState(() => _selectedPlaylist = pl);
    } else {
      context.push('/playlist', extra: pl);
    }
  }

  void _showCreateDialog(BuildContext context, PlaylistCubit cubit) async {
    final name = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.createPlaylist,
      hintText: context.l10n.enterPlaylistName,
      icon: Icons.playlist_add_rounded,
      confirmLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
    );
    if (name != null && name.isNotEmpty) {
      await cubit.createPlaylist(name);
    }
  }

  void _showRenameDialog(
      BuildContext context, PlaylistCubit cubit, PlaylistsTableData pl) async {
    final name = await PulsrDialogHelper.showInputDialog(
      context,
      title: 'Rename Playlist',
      initialText: pl.name,
      icon: Icons.drive_file_rename_outline_rounded,
      confirmLabel: 'Save',
      cancelLabel: 'Cancel',
    );
    if (name != null && name.isNotEmpty) {
      await cubit.renamePlaylist(pl.id, name);
    }
  }

  /// Exports (or shares) a playlist from the list cards. Smart playlists
  /// resolve through their live criteria query. Defaults to M3U export.
  Future<void> _exportPlaylistSongs(
    BuildContext context,
    PlaylistsTableData pl, {
    bool share = false,
    PlaylistFormat format = PlaylistFormat.m3u,
  }) async {
    try {
      final useCases = getIt<PlaylistUseCases>();
      final List<SongsTableData> songs;
      if (pl.isSmart && pl.smartCriteria != null) {
        songs = await useCases.watchSmartPlaylistSongs(
                SmartCriteria.fromJsonString(pl.smartCriteria!))
            .first;
      } else {
        final res = await useCases.watchPlaylistSongs(pl.id).first;
        songs = res.fold((l) => <SongsTableData>[], (r) => r);
      }
      if (!context.mounted) return;
      if (songs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.cannotExportEmpty)),
        );
        return;
      }
      final file =
          await getIt<PlaylistExportUseCase>()
              .exportToFile(pl.name, songs, format: format);
      if (!context.mounted) return;
      if (share) {
        final sharedBundle = await _sharePlaylistBundle(pl.name, songs);
        if (sharedBundle) {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
          return;
        }
        try {
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(file.path, mimeType: 'audio/x-mpegurl')],
              text: 'Playlist: ${pl.name}',
            ),
          );
        } finally {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Playlist exported successfully (${songs.length} tracks).')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.exportFailedRetry)),
        );
      }
    }
  }

  /// Presents a small format picker, then exports the playlist in the chosen
  /// M3U / PLS / WPL format.
  Future<void> _showExportFormatSheet(
      BuildContext context, PlaylistsTableData pl) async {
    final format = await showModalBottomSheet<PlaylistFormat>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('M3U'),
              subtitle: Text(context.l10n.mostCompatible),
              onTap: () => Navigator.pop(ctx, PlaylistFormat.m3u),
            ),
            ListTile(
              leading: const Icon(Icons.list_alt_rounded),
              title: const Text('PLS'),
              subtitle: const Text('Winamp / Poweramp'),
              onTap: () => Navigator.pop(ctx, PlaylistFormat.pls),
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('WPL'),
              subtitle: const Text('Windows Media Player'),
              onTap: () => Navigator.pop(ctx, PlaylistFormat.wpl),
            ),
          ],
        ),
      ),
    );
    if (format == null || !context.mounted) return;
    await _exportPlaylistSongs(context, pl, format: format);
  }

  /// Routes sharing through [PlaylistShareService] so the portable JSON bundle
  /// is the primary format. Returns false (caller falls back to the existing
  /// M3U share) when the service cannot produce or validate a bundle.
  Future<bool> _sharePlaylistBundle(
      String name, List<SongsTableData> songs) async {
    try {
      final shareService = getIt<PlaylistShareService>();
      final json = shareService.exportPlaylist(name, songs);
      if (json.isEmpty || shareService.importPlaylist(json) == null) {
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final bundle = File('${tempDir.path}/$safeName.pulsr.json');
      await bundle.writeAsString(json);
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(bundle.path, mimeType: 'application/json')],
            text: 'Playlist: $name',
          ),
        );
        return true;
      } finally {
        try {
          if (await bundle.exists()) await bundle.delete();
        } catch (_) {}
      }
    } catch (_) {
      return false;
    }
  }

  void _confirmDelete(
      BuildContext context, PlaylistCubit cubit, PlaylistsTableData pl) async {
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: 'Delete "${pl.name}"?',
      message: 'This cannot be undone.',
      icon: Icons.delete_outline_rounded,
      confirmLabel: context.l10n.delete,
      isDestructive: true,
    );
    if (confirmed == true) {
      await cubit.deletePlaylist(pl.id);
    }
  }

  Future<void> _importPlaylist(BuildContext context) async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'pls', 'wpl'],
    );
    if (result == null || result.path == null) return;

    final filePath = result.path!;
    final playlistName = result.name.replaceAll(
      RegExp(r'\.(m3u8?|pls|wpl)$', caseSensitive: false),
      '',
    );
    final importUseCase = getIt<PlaylistImportUseCase>();

    final res = await importUseCase.importPlaylistFromFile(
      filePath: filePath,
      playlistName: playlistName,
    );
    if (!context.mounted) return;

    res.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .importPlaylistFailed(failure.message))),
        );
      },
      (importResult) {
        PulsrDialogHelper.showPulsrDialog(
          context,
          icon: Icon(Icons.check_circle_rounded,
              color: context.palette.success, size: 28),
          title: Text(context.l10n.playlistImported,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text(context.l10n.importMatched(
              importResult.matchedTrackCount,
              importResult.totalExtractedPaths)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
              child: Text(context.l10n.close),
            ),
          ],
        );
      },
    );
  }

  void _showAddOnlinePlaylistDialog(
      BuildContext context, PlaylistCubit cubit) async {
    final url = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.addYouTubePlaylist,
      message: 'Paste a YouTube or YouTube Music playlist link.',
      hintText: 'https://www.youtube.com/playlist?list=PLxxx',
      icon: Icons.cloud_download_rounded,
      confirmLabel: context.l10n.confirm,
      cancelLabel: context.l10n.cancel,
    );
    if (url != null && url.isNotEmpty && context.mounted) {
      cubit.fetchOnlinePlaylistByUrl(url);
      context.push(
        '/online-playlist',
        extra: OnlinePlaylistDetailArgs(playlistId: url),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<PlaylistCubit>();
    final getSongsUseCase = getIt<GetSongsUseCase>();
    final playerCubit = context.read<PlayerCubit>();

    return BlocBuilder<PlaylistCubit, PlaylistState>(
      builder: (context, state) {
        final smartPlaylists = state.playlists.where((x) => x.isSmart).toList();
        final userPlaylists = state.playlists.where((x) => !x.isSmart).toList();
        final columns = Adaptive.gridColumns(context, minItemWidth: 170);
        final isTabletLandscape = context.isTabletLandscape;

        if (isTabletLandscape && _selectedPlaylist == null) {
          if (userPlaylists.isNotEmpty) {
            _selectedPlaylist = userPlaylists.first;
          } else if (smartPlaylists.isNotEmpty) {
            _selectedPlaylist = smartPlaylists.first;
          }
        }

        final playlistListWidget = _buildPlaylistListContent(
          context: context,
          cubit: cubit,
          state: state,
          p: p,
          getSongsUseCase: getSongsUseCase,
          playerCubit: playerCubit,
          smartPlaylists: smartPlaylists,
          userPlaylists: userPlaylists,
          columns: columns,
          isTabletLandscape: isTabletLandscape,
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.playlists),
            actions: [
              if (_selectedTab == _PlaylistTabMode.online) ...[
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: context.l10n.syncOnlineLibrary,
                  onPressed: () => cubit.autoFetchOnlineLibrary(force: true),
                ),
                IconButton(
                  icon: const Icon(Icons.add_link_rounded),
                  tooltip: context.l10n.addPlaylistUrl,
                  onPressed: () => _showAddOnlinePlaylistDialog(context, cubit),
                ),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.file_upload_rounded),
                  tooltip: context.l10n.importM3u,
                  onPressed: () => _importPlaylist(context),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded),
                  tooltip: context.l10n.createPlaylist,
                  onPressed: () => _showCreateDialog(context, cubit),
                ),
              ],
            ],
          ),
          body: isTabletLandscape
              ? Row(
                  children: [
                    SizedBox(
                      width: 380,
                      child: playlistListWidget,
                    ),
                    VerticalDivider(width: 1, thickness: 1, color: p.hairline),
                    Expanded(
                      child: _selectedPlaylist != null
                          ? PlaylistDetailScreen(
                              key: ValueKey('playlist_${_selectedPlaylist!.id}'),
                              playlist: _selectedPlaylist!,
                              isEmbedded: true,
                            )
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.queue_music_rounded,
                                      size: 64, color: p.textTertiary),
                                  const SizedBox(height: 16),
                                  Text(context.l10n.selectPlaylistHint,
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: Adaptive.contentConstraints(context),
                    child: playlistListWidget,
                  ),
                ),
        );
      },
    );
  }

  Widget _buildPlaylistListContent({
    required BuildContext context,
    required PlaylistCubit cubit,
    required PlaylistState state,
    required PulsrPalette p,
    required GetSongsUseCase getSongsUseCase,
    required PlayerCubit playerCubit,
    required List<PlaylistsTableData> smartPlaylists,
    required List<PlaylistsTableData> userPlaylists,
    required int columns,
    required bool isTabletLandscape,
  }) {
    return RefreshIndicator(
      onRefresh: () async {
        if (_selectedTab == _PlaylistTabMode.online) {
          await cubit.autoFetchOnlineLibrary(force: true);
        } else {
          final count =
              await context.read<SettingsCubit>().rescanLibrary();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.l10n.scanResult(count)),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 160, top: 12),
        children: [
          // Liked songs hero card (Local favorites)
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: Adaptive.pagePadding(context)),
            child: _PlaylistHeroCard(
              title: context.l10n.favorites,
              subtitle: context.l10n.likedTracks,
              icon: Icons.favorite_rounded,
              colors: [p.favorite, const Color(0xFFB0316B)],
              onTap: () => context.push('/favorites'),
            ),
          ),

          // Suggested for you (optional; hidden until real library data yields
          // at least one suggestion).
          if (_suggestions.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.only(
                left: Adaptive.pagePadding(context),
                right: Adaptive.pagePadding(context),
                top: 24,
                bottom: 10,
              ),
              child: Text(context.l10n.suggestedForYou,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: p.textTertiary),
              ),
            ),
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                    horizontal: Adaptive.pagePadding(context)),
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return _SuggestionCard(
                    suggestion: suggestion,
                    onTap: () => _createPlaylistFromSuggestion(suggestion),
                  );
                },
              ),
            ),
          ],

          // SMART PLAYLISTS Header
          Padding(
            padding: EdgeInsets.only(
              left: Adaptive.pagePadding(context),
              right: Adaptive.pagePadding(context),
              top: 24,
              bottom: 10,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10n.smartPlaylists.toUpperCase(),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: p.textTertiary),
                ),
                if (smartPlaylists.isEmpty)
                  InkWell(
                    onTap: () => context.push('/smart-playlist-builder'),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded,
                              size: 14, color: p.accent),
                          const SizedBox(width: 4),
                          Text(
                            context.l10n.createSmartPlaylist,
                            style: TextStyle(
                              color: p.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (smartPlaylists.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: Adaptive.pagePadding(context)),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isTabletLandscape ? 2 : columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.0,
                ),
                itemCount: smartPlaylists.length,
                itemBuilder: (context, index) {
                  final pl = smartPlaylists[index];
                  final count = state.smartPlaylistCounts[pl.id] ?? 0;
                  return _PlaylistCard(
                    name: pl.name,
                    subtitle:
                        '${context.l10n.tracksCount(count)} • Smart',
                    icon: Icons.auto_awesome_rounded,
                    gradient: [
                      p.accent.withValues(alpha: 0.65),
                      p.accent.withValues(alpha: 0.25)
                    ],
                    isSelected: isTabletLandscape && _selectedPlaylist?.id == pl.id,
                    onTap: () => _onSelectPlaylist(pl),
                    onLongPress: () => _onSelectPlaylist(pl),
                    menuItems: (_) => [
                      PopupMenuItem(
                          value: 'edit-smart',
                          child: Text(context.l10n.editSmartRules)),
                      PopupMenuItem(value: 'share', child: Text(context.l10n.share)),
                      PopupMenuItem(
                          value: 'rename', child: Text(context.l10n.rename)),
                      PopupMenuItem(
                          value: 'delete', child: Text(context.l10n.delete)),
                    ],
                    onMenuSelected: (v) {
                      if (v == 'edit-smart') {
                        context.push('/smart-playlist-builder', extra: pl);
                      } else if (v == 'share') {
                        _exportPlaylistSongs(context, pl, share: true);
                      } else if (v == 'rename') {
                        _showRenameDialog(context, cubit, pl);
                      } else if (v == 'delete') {
                        _confirmDelete(context, cubit, pl);
                      }
                    },
                  );
                },
              ),
            ),

          // ── YOUR PLAYLISTS SECTION ──────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
                Adaptive.pagePadding(context),
                28,
                Adaptive.pagePadding(context),
                12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10n.playlists.toUpperCase(),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),

          // ── TABS UNDER YOUR PLAYLISTS (Local vs Online) ─────────
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: Adaptive.pagePadding(context)),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_PlaylistTabMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                segments: [
                  ButtonSegment(
                    value: _PlaylistTabMode.local,
                    label: Text(context.l10n.local,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700)),
                    icon: const Icon(Icons.folder_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: _PlaylistTabMode.online,
                    label: Text(context.l10n.online,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700)),
                    icon: const Icon(Icons.cloud_rounded, size: 16),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (sel) {
                  setState(() => _selectedTab = sel.first);
                  if (sel.first == _PlaylistTabMode.online) {
                    cubit.autoFetchOnlineLibrary();
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── TAB CONTENT ─────────────────────────────────────────
          if (_selectedTab == _PlaylistTabMode.local) ...[
            // LOCAL PLAYLISTS VIEW
            if (userPlaylists.isEmpty)
              EmptyStateWidget(
                icon: Icons.playlist_add_rounded,
                title: context.l10n.emptyPlaylists,
                subtitle: context.l10n.emptyPlaylistsSubtitle,
                primaryActionLabel: context.l10n.createPlaylist,
                primaryActionIcon: Icons.add_rounded,
                onPrimaryAction: () =>
                    _showCreateDialog(context, cubit),
                secondaryActionLabel: 'Import M3U',
                secondaryActionIcon: Icons.file_upload_rounded,
                onSecondaryAction: () => _importPlaylist(context),
              )
            else
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: Adaptive.pagePadding(context)),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isTabletLandscape ? 2 : columns,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: userPlaylists.length,
                  itemBuilder: (context, index) {
                    final pl = userPlaylists[index];
                    return _PlaylistCard(
                      name: pl.name,
                      subtitle: 'Offline playlist',
                      icon: Icons.queue_music_rounded,
                      gradient: [
                        p.surfaceContainerHigh,
                        p.surfaceContainer
                      ],
                      muted: true,
                      isSelected: isTabletLandscape && _selectedPlaylist?.id == pl.id,
                      onTap: () => _onSelectPlaylist(pl),
                      onLongPress: () => _onSelectPlaylist(pl),
                      menuItems: (_) => [
                        PopupMenuItem(
                            value: 'export', child: Text(context.l10n.export)),
                        PopupMenuItem(value: 'share', child: Text(context.l10n.share)),
                        PopupMenuItem(
                            value: 'rename', child: Text(context.l10n.rename)),
                        PopupMenuItem(
                            value: 'delete', child: Text(context.l10n.delete)),
                      ],
                      onMenuSelected: (v) {
                        if (v == 'export') {
                          _showExportFormatSheet(context, pl);
                        } else if (v == 'share') {
                          _exportPlaylistSongs(context, pl, share: true);
                        } else if (v == 'rename') {
                          _showRenameDialog(context, cubit, pl);
                        } else if (v == 'delete') {
                          _confirmDelete(context, cubit, pl);
                        }
                      },
                    );
                  },
                ),
              ),
          ] else ...[
            // ONLINE PLAYLISTS VIEW (Auto-fetches YouTube Music library)
            _OnlinePlaylistsContent(
              cubit: cubit,
              playerCubit: playerCubit,
              onAddPlaylist: () =>
                  _showAddOnlinePlaylistDialog(context, cubit),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ONLINE PLAYLISTS CONTENT (Under 'Your Playlists' Online Tab)
// ─────────────────────────────────────────────────────────────────────────────

class _OnlinePlaylistsContent extends StatelessWidget {
  final PlaylistCubit cubit;
  final PlayerCubit playerCubit;
  final VoidCallback onAddPlaylist;

  const _OnlinePlaylistsContent({
    required this.cubit,
    required this.playerCubit,
    required this.onAddPlaylist,
  });

  Future<void> _downloadAccountPlaylist(
    BuildContext context,
    YtmAccountPlaylist playlist,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    // Capture localized strings before async gaps (avoid context-across-gap).
    final loadFailedText = context.l10n.playlistLoadFailed;
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('Fetching "${playlist.title}" for download…'),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final ytmService = getIt<YtmService>();
      final tracks =
          await ytmService.getPlaylistTracks(playlist.playlistId, limit: 200);
      if (tracks.isNotEmpty) {
        final songs = tracks.map((t) => t.toSongData()).toList();
        final downloadCubit = getIt<YtmDownloadCubit>();
        final queuedCount = downloadCubit.downloadAll(songs);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              queuedCount > 0
                  ? 'Queued $queuedCount tracks from "${playlist.title}" for download (3 active downloads)...'
                  : 'All tracks from "${playlist.title}" are already downloaded offline.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final emptyText = loadFailedText;
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(emptyText)),
        );
      }
    } catch (_) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(loadFailedText)),
      );
    }
  }

  void _downloadCustomPlaylist(
    BuildContext context,
    OnlinePlaylistEntry entry,
  ) {
    if (entry.tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.emptyPlaylist)),
      );
      return;
    }
    final songs = entry.tracks.map((t) => t.toSongData()).toList();
    final downloadCubit =
        context.read<YtmDownloadCubit?>() ?? getIt<YtmDownloadCubit>();
    final queuedCount = downloadCubit.downloadAll(songs);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          queuedCount > 0
              ? 'Queued $queuedCount tracks from "${entry.title}" for download (3 active downloads)...'
              : 'All tracks from "${entry.title}" are already downloaded offline.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _downloadLikedSongs(
    BuildContext context,
    List<YtmTrack> likedTracks,
  ) {
    if (likedTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noLikedToDownload)),
      );
      return;
    }
    final songs = likedTracks.map((t) => t.toSongData()).toList();
    final downloadCubit =
        context.read<YtmDownloadCubit?>() ?? getIt<YtmDownloadCubit>();
    final queuedCount = downloadCubit.downloadAll(songs);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          queuedCount > 0
              ? 'Queued $queuedCount liked songs for download (3 active downloads)...'
              : 'All liked songs are already downloaded offline.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ytmAccount = getIt<YtmAccountService>();

    return ValueListenableBuilder<bool>(
      valueListenable: ytmAccount.loginState,
      builder: (context, isLoggedIn, _) {
        return ValueListenableBuilder<YtmOnlineState>(
          valueListenable: cubit.ytmOnline,
          builder: (context, online, _) {
            final columns = Adaptive.gridColumns(context, minItemWidth: 170);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isLoggedIn)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: Adaptive.pagePadding(context),
                      vertical: 12,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.cloud_sync_rounded,
                                size: 28, color: p.accent),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.l10n.connectYtm,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: p.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(context.l10n.signInToSync,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              final ok = await YtmWebLoginSheet.show(context);
                              if (ok == true) {
                                cubit.autoFetchOnlineLibrary(force: true);
                              }
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(context.l10n.signIn,
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (isLoggedIn) ...[
                  // Liked Music Online Hero Card
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context)),
                    child: _LikedMusicOnlineCard(
                      status: online.likedStatus,
                      trackCount: online.likedTracks.length,
                      error: online.likedError,
                      onFetch: () => cubit.fetchLikedSongsPlaylist(),
                      onDownload: () =>
                          _downloadLikedSongs(context, online.likedTracks),
                      onPlay: () => context.push(
                        '/online-playlist',
                        extra: OnlinePlaylistDetailArgs(
                          playlistId: 'VLLM',
                          title: 'Liked Music',
                          subtitle: 'YouTube Music',
                          initialTracks: online.likedTracks,
                        ),
                      ),
                    ),
                  ),

                  // ── ACCOUNT PLAYLISTS SECTION ─────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context),
                        24, Adaptive.pagePadding(context), 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(context.l10n.accountPlaylists,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: p.textTertiary),
                          ),
                        ),
                        if (online.accountStatus == YtmFetchStatus.loading)
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: p.accent),
                          )
                        else if (online.accountPlaylists.isNotEmpty)
                          Text(
                            context.l10n.accountPlaylistCount(
                                online.accountPlaylists.length),
                            style: TextStyle(
                                color: p.textTertiary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),

                  if (online.accountStatus == YtmFetchStatus.loading &&
                      online.accountPlaylists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          children: [
                            SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: p.accent)),
                            const SizedBox(height: 12),
                            Text(context.l10n.fetchingAccount,
                                style: TextStyle(
                                    color: p.textSecondary, fontSize: 13)),
                          ],
                        ),
                      ),
                    )
                  else if (online.accountStatus == YtmFetchStatus.error &&
                      online.accountPlaylists.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: Adaptive.pagePadding(context),
                          vertical: 10),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded,
                                color: p.error, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                online.accountError ??
                                    'Failed to load account playlists',
                                style: TextStyle(
                                    color: p.textSecondary, fontSize: 12.5),
                              ),
                            ),
                            TextButton(
                              onPressed: () => cubit.fetchAccountPlaylists(),
                              child: Text(context.l10n.retry),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (online.accountPlaylists.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: Adaptive.pagePadding(context)),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.playlist_remove_rounded,
                                color: p.textTertiary, size: 26),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(context.l10n.noAccountPlaylists,
                                style: TextStyle(
                                    color: p.textSecondary, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: Adaptive.pagePadding(context)),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: online.accountPlaylists.length,
                        itemBuilder: (context, i) {
                          final pl = online.accountPlaylists[i];
                          return _AccountPlaylistCard(
                            playlist: pl,
                            onTap: () =>
                                context.push('/online-playlist', extra: pl),
                            onDownload: () =>
                                _downloadAccountPlaylist(context, pl),
                          );
                        },
                      ),
                    ),
                ],

                // ── ADDED PLAYLISTS SECTION ─────────────────────────────
                if (online.customPlaylists.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context),
                        24, Adaptive.pagePadding(context), 10),
                    child: Text(context.l10n.addedPlaylists,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: p.textTertiary),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context)),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: online.customPlaylists.length,
                      itemBuilder: (context, i) {
                        final pl = online.customPlaylists[i];
                        return _OnlinePlaylistCard(
                          entry: pl,
                          onTap: () =>
                              context.push('/online-playlist', extra: pl),
                          onDownload: () =>
                              _downloadCustomPlaylist(context, pl),
                          onRemove: () => cubit.removeCustomPlaylist(pl.id),
                        );
                      },
                    ),
                  ),
                ],

                // Add YouTube Playlist Button
                Padding(
                  padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context),
                      16, Adaptive.pagePadding(context), 0),
                  child: InkWell(
                    onTap: onAddPlaylist,
                    borderRadius: BorderRadius.circular(18),
                    child: DashedBorderCard(
                      color: const Color(0xFFFF0000),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_rounded,
                              color: Color(0xFFFF0000), size: 20),
                          const SizedBox(width: 8),
                          Text(context.l10n.addYtmUrl,
                            style: TextStyle(
                              color: Color(0xFFFF0000),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account Playlist Card (from YouTube Music library)
// ─────────────────────────────────────────────────────────────────────────────

class _AccountPlaylistCard extends StatelessWidget {
  final YtmAccountPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  const _AccountPlaylistCard({
    required this.playlist,
    required this.onTap,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const gradientColors = [Color(0xFFE50914), Color(0xFF8B0000)];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(19)),
                    child: playlist.artworkUrl != null
                        ? Image.network(
                            playlist.artworkUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: gradientColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Center(
                                child: Icon(Icons.queue_music_rounded,
                                    color: Colors.white, size: 36),
                              ),
                            ),
                          )
                        : Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: gradientColors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Icon(Icons.queue_music_rounded,
                                  color: Colors.white, size: 36),
                            ),
                          ),
                  ),
                  if (onDownload != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onDownload,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.download_rounded,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    playlist.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Liked Music Online Hero Card
// ─────────────────────────────────────────────────────────────────────────────

class _LikedMusicOnlineCard extends StatelessWidget {
  final YtmFetchStatus status;
  final int trackCount;
  final String? error;
  final VoidCallback onFetch;
  final VoidCallback onPlay;
  final VoidCallback? onDownload;

  const _LikedMusicOnlineCard({
    required this.status,
    required this.trackCount,
    required this.error,
    required this.onFetch,
    required this.onPlay,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    const gradientColors = [Color(0xFF1ED760), Color(0xFF14833B)];

    String subtitle;
    switch (status) {
      case YtmFetchStatus.idle:
        subtitle = 'Tap to sync from YouTube Music';
        break;
      case YtmFetchStatus.loading:
        subtitle = 'Syncing liked songs…';
        break;
      case YtmFetchStatus.done:
        subtitle = '$trackCount songs synced • Tap to play or download';
        break;
      case YtmFetchStatus.error:
        subtitle = error ?? 'Failed to fetch';
        break;
    }

    return InkWell(
      onTap: status == YtmFetchStatus.loading
          ? null
          : (status == YtmFetchStatus.done
              ? onPlay
              : (error != null &&
                      (error!.toLowerCase().contains('sign in') ||
                          error!.toLowerCase().contains('expired'))
                  ? () => YtmWebLoginSheet.show(context)
                  : onFetch)),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withValues(alpha: 0.35),
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.thumb_up_alt_rounded,
                  color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.likedMusic,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(
                          alpha: status == YtmFetchStatus.error ? 0.7 : 0.85),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (status == YtmFetchStatus.loading)
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            else if (status == YtmFetchStatus.done)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onDownload != null) ...[
                    GestureDetector(
                      onTap: onDownload,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.download_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: Icon(Icons.play_arrow_rounded,
                        color: gradientColors.first, size: 26),
                  ),
                ],
              )
            else
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: Icon(
                  status == YtmFetchStatus.error
                      ? Icons.refresh_rounded
                      : Icons.download_rounded,
                  color: gradientColors.first,
                  size: 22,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Online Playlist Card (custom URL/ID)
// ─────────────────────────────────────────────────────────────────────────────

class _OnlinePlaylistCard extends StatelessWidget {
  final OnlinePlaylistEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onDownload;

  const _OnlinePlaylistCard({
    required this.entry,
    required this.onTap,
    required this.onRemove,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const ytRed = Color(0xFFFF0000);
    return InkWell(
      onTap: onTap,
      onLongPress: onRemove,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ytRed.withValues(alpha: 0.8),
                      ytRed.withValues(alpha: 0.35)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(19)),
                ),
                child: Stack(
                  children: [
                    const Center(
                        child: Icon(Icons.queue_music_rounded,
                            color: Colors.white, size: 40)),
                    if (onDownload != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: GestureDetector(
                          onTap: onDownload,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.download_rounded,
                                color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onRemove,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(context.l10n.entryAdded(entry.tracks.length),
                      style: TextStyle(color: p.textSecondary, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reused local components
// ─────────────────────────────────────────────────────────────────────────────

class _PlaylistHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  const _PlaylistHeroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.35),
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12.5)),
                ],
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child:
                  Icon(Icons.play_arrow_rounded, color: colors.first, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final PlaylistSuggestion suggestion;
  final VoidCallback onTap;

  const _SuggestionCard({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: p.accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    suggestion.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              suggestion.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.textSecondary, fontSize: 12),
            ),
            const Spacer(),
            Text(
              context.l10n.tapToCreate(suggestion.songs.length),
              style: TextStyle(color: p.textTertiary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final bool muted;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final List<PopupMenuEntry<String>> Function(BuildContext)? menuItems;
  final void Function(String)? onMenuSelected;

  const _PlaylistCard({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.muted = false,
    this.isSelected = false,
    this.onLongPress,
    this.menuItems,
    this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? p.accent : p.hairline,
            width: isSelected ? 2.2 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: p.glow.withValues(alpha: 0.35),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(19)),
                ),
                child: Center(
                  child: Icon(icon,
                      color: muted ? p.textSecondary : Colors.white, size: 40),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(
                                color: p.textSecondary, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  if (menuItems != null)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded,
                          size: 18, color: p.textTertiary),
                      onSelected: onMenuSelected,
                      itemBuilder: menuItems!,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (onLongPress == null && menuItems == null) return card;
    return card;
  }
}

class DashedBorderCard extends StatelessWidget {
  final Widget child;
  final Color color;
  const DashedBorderCard({super.key, required this.child, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.4),
        color: color.withValues(alpha: 0.05),
      ),
      child: child,
    );
  }
}
