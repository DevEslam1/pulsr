// lib/features/playlists/presentation/playlists_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/injection.dart';
import '../../../core/errors/error_message_resolver.dart';
import '../../../core/services/playlist_share_service.dart';
import '../../../core/services/playlist_suggestions_service.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/safe_file_path.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_button.dart';
import '../../../core/widgets/pulsr_card.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_progress.dart';
import '../../../core/widgets/pulsr_refresh_indicator.dart';
import '../../../core/widgets/pulsr_section_header.dart';
import '../../../core/widgets/source_scope_switcher.dart';
import '../../../core/widgets/pulsr_static_grid.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/staggered_reveal.dart';
import '../../../data/db/app_database.dart';
import '../../../data/usecases/playlist_io_usecases.dart';
import '../../../domain/models/smart_playlist_criteria.dart';
import '../../../domain/models/ytm_track.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import '../../auth/presentation/ytm_web_login_sheet.dart';
import '../../player/cubit/player_cubit.dart';
import '../../playlist_detail/presentation/online_playlist_detail_screen.dart';
import '../../playlist_detail/presentation/playlist_detail_screen.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../cubit/playlist_cubit.dart';
import '../cubit/playlist_state.dart';
import 'widgets/playlist_suggestion_card.dart';
import 'widgets/smart_playlist_card.dart';
import 'widgets/spotify_import_dialog.dart';
import '../../../core/utils/pulsr_haptics.dart';
part 'playlists_screen_components.dart';
part 'playlists_screen_online_cards.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  SourceScope _scope = SourceScope.local;
  PlaylistsTableData? _selectedPlaylist;
  List<PlaylistSuggestion> _suggestions = const [];
  bool _isCreatingPlaylist = false;
  final Set<String> _creatingSuggestions = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuggestions());
  }

  /// Suggestion service output is optional and non-intrusive: it stays hidden
  /// until real library songs produce at least one suggestion.
  Future<void> _loadSuggestions({bool forceRefresh = false}) async {
    if (!getIt.isRegistered<GetSongsUseCase>() ||
        !getIt.isRegistered<PlaylistSuggestionsService>()) {
      return;
    }
    try {
      final result = await getIt<GetSongsUseCase>().getAllSongs();
      final allSongs = result.fold((_) => <SongsTableData>[], (songs) => songs);
      final suggestions = await getIt<PlaylistSuggestionsService>()
          .generateSuggestionsAsync(allSongs, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() => _suggestions = suggestions);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to load playlist suggestions',
        error: e,
        stackTrace: st,
        category: 'PlaylistsScreen',
      );
    }
  }

  Future<void> _createPlaylistFromSuggestion(
    PlaylistSuggestion suggestion,
  ) async {
    if (!_creatingSuggestions.add(suggestion.title)) return;
    PulsrHaptics.selectionClick();
    final createFailedText = context.l10n.suggestCreateFailed;
    final loc = context.l10n;
    final useCases = getIt<PlaylistUseCases>();
    try {
      final created = await useCases.createPlaylist(suggestion.title);
      final playlistId = created.fold<int?>((_) => null, (id) => id);
      if (playlistId == null) {
        if (mounted) {
          PulsrToast.show(context, message: createFailedText, isError: true);
        }
        return;
      }
      final songIds = suggestion.songs.map((s) => s.id).toList();
      if (songIds.isNotEmpty) {
        await useCases.addSongsToPlaylist(playlistId, songIds);
      }
      if (mounted) {
        setState(() {
          _suggestions =
              _suggestions.where((s) => s.title != suggestion.title).toList();
        });
      }
      getIt<PlaylistSuggestionsService>().invalidateCache();
      unawaited(_loadSuggestions(forceRefresh: true));
      if (mounted) {
        PulsrToast.show(
          context,
          message: loc.suggestedCreated(suggestion.title, songIds.length),
          isSuccess: true,
        );
      }
    } catch (_) {
      if (mounted) {
        PulsrToast.show(context, message: createFailedText, isError: true);
      }
    } finally {
      _creatingSuggestions.remove(suggestion.title);
    }
  }

  void _onSelectPlaylist(PlaylistsTableData pl) {
    PulsrHaptics.selectionClick();
    if (context.isTwoPanePlaylist) {
      setState(() => _selectedPlaylist = pl);
    } else {
      context.push('/playlist?id=${pl.id}', extra: pl);
    }
  }

  void _showCreateDialog(BuildContext context, PlaylistCubit cubit) async {
    if (_isCreatingPlaylist) return;
    final name = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.createPlaylist,
      hintText: context.l10n.enterPlaylistName,
      icon: Icons.playlist_add_rounded,
      confirmLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
    );
    if (name != null && name.trim().isNotEmpty && mounted) {
      setState(() => _isCreatingPlaylist = true);
      try {
        await cubit.createPlaylist(name.trim());
      } finally {
        if (mounted) {
          setState(() => _isCreatingPlaylist = false);
        }
      }
    }
  }

  void _showRenameDialog(
    BuildContext context,
    PlaylistCubit cubit,
    PlaylistsTableData pl,
  ) async {
    final name = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.browseRenamePlaylist,
      initialText: pl.name,
      icon: Icons.drive_file_rename_outline_rounded,
      confirmLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      await cubit.renamePlaylist(pl.id, trimmed);
    }
  }

  Future<String> _saveExportedPlaylistFile(
    String playlistTitle,
    File tempFile,
    PlaylistFormat format,
  ) async {
    if (!tempFile.existsSync()) {
      return tempFile.path;
    }
    final fileName = tempFile.uri.pathSegments.isNotEmpty
        ? tempFile.uri.pathSegments.last
        : 'playlist.${format.extension}';
    final bytes = await tempFile.readAsBytes();
    try {
      final outputUri = await FilePicker.saveFile(
        dialogTitle: playlistTitle,
        fileName: fileName,
        bytes: bytes,
      );
      if (outputUri != null) {
        final pickedPath = outputUri.isScheme('file')
            ? outputUri.toFilePath()
            : outputUri.toString();
        if (pickedPath.trim().isNotEmpty) {
          if (outputUri.isScheme('file')) {
            final outFile = File(pickedPath);
            try {
              if (!await outFile.exists() || await outFile.length() == 0) {
                await outFile.writeAsBytes(bytes, flush: true);
              }
            } catch (e, st) {
              ErrorLogger.log('Failed to write picked playlist export file',
                  error: e, stackTrace: st, category: 'PlaylistExport');
            }
          }
          return pickedPath;
        }
      }
    } catch (e, st) {
      ErrorLogger.log('FilePicker.saveFile unavailable for playlist export',
          error: e, stackTrace: st, category: 'PlaylistExport');
    }

    try {
      final dir = await getDownloadsDirectory() ??
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final exportDir =
          Directory('${dir.path}${Platform.pathSeparator}Playlists');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      final fallbackFile =
          File('${exportDir.path}${Platform.pathSeparator}$fileName');
      await fallbackFile.writeAsBytes(bytes, flush: true);
      return fallbackFile.path;
    } catch (_) {
      return tempFile.path;
    }
  }

  Future<void> _exportPlaylistSongs(
    BuildContext context,
    PlaylistsTableData pl, {
    bool share = false,
    PlaylistFormat format = PlaylistFormat.m3u,
  }) async {
    final sharePrefix = context.l10n.browsePlaylistSharePrefix;
    final exportedSuccess = context.l10n.browsePlaylistExportedSuccess;
    final tracksLabel = context.l10n.browseTracks;
    try {
      final useCases = getIt<PlaylistUseCases>();
      final List<SongsTableData> songs;
      if (pl.isSmart && pl.smartCriteria != null) {
        songs = await useCases
            .watchSmartPlaylistSongs(
              SmartCriteria.fromJsonString(pl.smartCriteria!),
            )
            .first;
      } else {
        final res = await useCases.watchPlaylistSongs(pl.id).first;
        songs = res.fold((l) => <SongsTableData>[], (r) => r);
      }
      if (!context.mounted) return;
      if (songs.isEmpty) {
        PulsrToast.show(context, message: context.l10n.cannotExportEmpty);
        return;
      }
      final file = await getIt<PlaylistExportUseCase>()
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
              text: '$sharePrefix ${pl.name}',
            ),
          );
        } finally {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      } else {
        final savedPath =
            await _saveExportedPlaylistFile(pl.name, file, format);
        if (!context.mounted) return;
        PulsrToast.show(
          context,
          message:
              '$exportedSuccess (${songs.length} $tracksLabel): $savedPath',
          isSuccess: true,
        );
      }
    } catch (_) {
      if (context.mounted) {
        PulsrToast.show(
          context,
          message: context.l10n.exportFailedRetry,
          isError: true,
        );
      }
    }
  }

  Future<void> _showExportFormatSheet(
    BuildContext context,
    PlaylistsTableData pl,
  ) async {
    final p = context.palette;
    final format = await PulsrSheetHelper.showPulsrSheet<PlaylistFormat>(
      context: context,
      builder: (ctx) => PulsrBottomSheet(
        title: Text(context.l10n.export),
        subtitle: Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.playlist_play_rounded, color: p.accent),
              title: const Text(
                'M3U',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(context.l10n.mostCompatible),
              onTap: () => Navigator.pop(ctx, PlaylistFormat.m3u),
            ),
            ListTile(
              leading: Icon(Icons.list_alt_rounded, color: p.accent),
              title: const Text(
                'PLS',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(context.l10n.exportFormatWinampLabel),
              onTap: () => Navigator.pop(ctx, PlaylistFormat.pls),
            ),
            ListTile(
              leading: Icon(Icons.queue_music_rounded, color: p.accent),
              title: const Text(
                'WPL',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(context.l10n.exportFormatWmpLabel),
              onTap: () => Navigator.pop(ctx, PlaylistFormat.wpl),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
    if (format == null || !context.mounted) return;
    await _exportPlaylistSongs(context, pl, format: format);
  }

  Future<bool> _sharePlaylistBundle(
    String name,
    List<SongsTableData> songs,
  ) async {
    final sharePrefix = context.l10n.browsePlaylistSharePrefix;
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
            text: '$sharePrefix $name',
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
    BuildContext context,
    PlaylistCubit cubit,
    PlaylistsTableData pl,
  ) async {
    final undoLabel = context.l10n.undo;
    final deleteTitle = '${context.l10n.delete} "${pl.name}"?';
    final deleteMessage = context.l10n.browseCannotBeUndone;
    final deleteLabel = context.l10n.delete;
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: deleteTitle,
      message: deleteMessage,
      icon: Icons.delete_outline_rounded,
      confirmLabel: deleteLabel,
      isDestructive: true,
    );
    if (confirmed == true) {
      final plName = pl.name;
      final isSmart = pl.isSmart;
      final smartCriteria = pl.smartCriteria;
      List<int> songIds = const [];
      if (!isSmart) {
        try {
          final useCases = getIt<PlaylistUseCases>();
          final res = await useCases.watchPlaylistSongs(pl.id).first;
          songIds = res.fold(
            (_) => const <int>[],
            (songs) => [for (final s in songs) s.id],
          );
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to capture playlist songs for undo',
            error: e,
            stackTrace: st,
            category: 'PlaylistsScreen',
          );
        }
      }
      final deleted = await cubit.deletePlaylist(pl.id);
      if (!context.mounted) return;
      if (!deleted) {
        PulsrToast.show(
          context,
          message: cubit.state.errorMessage ?? context.l10n.somethingWentWrong,
          isError: true,
        );
        return;
      }
      PulsrToast.show(
        context,
        message: context.l10n.playlistDeleted(plName),
        actionLabel: undoLabel,
        onActionPressed: () => cubit.restorePlaylist(
          plName,
          isSmart: isSmart,
          criteria: smartCriteria,
          songIds: songIds,
        ),
      );
    }
  }

  Future<void> _importPlaylist(BuildContext context) async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'pls', 'wpl'],
    );
    if (result == null) return;
    final file = SafeFilePath.validate(
      result.path,
      allowedExtensions: ['m3u', 'm3u8', 'pls', 'wpl'],
    );
    if (file == null) return;

    final filePath = file.path;
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
            content: Text(context.l10n.importPlaylistFailed(failure.message)),
          ),
        );
      },
      (importResult) {
        PulsrDialogHelper.showPulsrDialog(
          context,
          icon: Icon(
            Icons.check_circle_rounded,
            color: context.palette.success,
            size: 28,
          ),
          title: Text(
            context.l10n.playlistImported,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            context.l10n.importMatched(
              importResult.matchedTrackCount,
              importResult.totalExtractedPaths,
            ),
          ),
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
    BuildContext context,
    PlaylistCubit cubit,
  ) async {
    final url = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.addYouTubePlaylist,
      message: context.l10n.browsePastePlaylistLinkHint,
      hintText: 'https://www.youtube.com/playlist?list=PLxxx',
      icon: Icons.cloud_download_rounded,
      confirmLabel: context.l10n.confirm,
      cancelLabel: context.l10n.cancel,
    );
    if (url != null && url.isNotEmpty && context.mounted) {
      cubit.fetchOnlinePlaylistByUrl(url);
      context.push(
        '/online-playlist?id=${Uri.encodeComponent(url)}',
        extra: OnlinePlaylistDetailArgs(playlistId: url),
      );
    }
  }

  void _showImportSpotifyDialog(BuildContext context, PlaylistCubit cubit) {
    SpotifyImportDialog.show(
      context,
      onImportFinished: () {
        cubit.reloadPlaylists();
      },
    );
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
        final isTwoPane = context.isTwoPanePlaylist;

        final PlaylistsTableData? resolvedSelection;
        if (isTwoPane) {
          final current = _selectedPlaylist;
          final exists = current != null &&
              (userPlaylists.any((x) => x.id == current.id) ||
                  smartPlaylists.any((x) => x.id == current.id));
          resolvedSelection = exists
              ? current
              : (userPlaylists.isNotEmpty
                  ? userPlaylists.first
                  : (smartPlaylists.isNotEmpty ? smartPlaylists.first : null));
        } else {
          resolvedSelection = null;
        }
        if (resolvedSelection?.id != _selectedPlaylist?.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedPlaylist = resolvedSelection);
          });
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
          isTabletLandscape: isTwoPane,
        );

        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(
            backgroundColor: p.bg,
            surfaceTintColor: p.bg.withValues(alpha: 0),
            elevation: 0,
            title: Semantics(
              header: true,
              child: Text(
                context.l10n.playlists,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.titleLarge,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            actions: [
              if (_scope == SourceScope.online) ...[
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: context.l10n.syncOnlineLibrary,
                  onPressed: () {
                    PulsrHaptics.lightImpact();
                    cubit.refreshOnlineLibrary();
                  },
                ),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  icon: const Icon(Icons.add_link_rounded),
                  tooltip: context.l10n.addPlaylistUrl,
                  onPressed: () => _showAddOnlinePlaylistDialog(context, cubit),
                ),
              ] else ...[
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  icon: const Icon(Icons.playlist_play_rounded),
                  tooltip: context.l10n.playlistImportSpotify,
                  onPressed: () => _showImportSpotifyDialog(context, cubit),
                ),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  icon: const Icon(Icons.file_upload_rounded),
                  tooltip: context.l10n.importM3u,
                  onPressed: () => _importPlaylist(context),
                ),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  icon: _isCreatingPlaylist
                      ? PulsrProgressBar.circular(
                          size: 18,
                          strokeWidth: 2,
                          color: p.accent,
                        )
                      : Icon(Icons.add_rounded, color: p.accent),
                  tooltip: context.l10n.createPlaylist,
                  onPressed: _isCreatingPlaylist
                      ? null
                      : () => _showCreateDialog(context, cubit),
                ),
              ],
              const SizedBox(width: AppSpacing.xxs),
            ],
          ),
          body: isTwoPane
              ? Row(
                  children: [
                    SizedBox(
                      width: PulsrLayoutMetrics.defaultLeftPaneWidth,
                      child: playlistListWidget,
                    ),
                    if (context.hasHinge)
                      SizedBox(width: context.hinge!.bounds.width)
                    else
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: p.hairline,
                      ),
                    Expanded(
                      child: resolvedSelection != null
                          ? PlaylistDetailScreen(
                              key: ValueKey('playlist_${resolvedSelection.id}'),
                              playlist: resolvedSelection,
                              isEmbedded: true,
                            )
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.queue_music_rounded,
                                    size: 64,
                                    color: p.textTertiary,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Text(
                                    context.l10n.selectPlaylistHint,
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: AppFontSize.bodyLarge,
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
    return PulsrRefreshIndicator(
      onRefresh: () async {
        if (_scope == SourceScope.online) {
          await cubit.refreshOnlineLibrary();
        } else {
          final count = await context.read<SettingsCubit>().rescanLibrary();
          if (context.mounted) {
            PulsrToast.show(
              context,
              message: context.l10n.scanResult(count),
            );
          }
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.only(
          bottom: PulsrLayoutMetrics.scrollBottom(context),
          top: AppSpacing.sm,
        ),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: Adaptive.pagePadding(context),
            ),
            child: _PlaylistHeroCard(
              title: context.l10n.favorites,
              subtitle: context.l10n.likedTracks,
              icon: Icons.favorite_rounded,
              colors: [p.favorite, AppColors.roseDeep],
              onTap: () {
                PulsrHaptics.selectionClick();
                context.push('/favorites');
              },
            ),
          ),
          if (_suggestions.isNotEmpty || smartPlaylists.isNotEmpty) ...[
            PulsrSectionHeader(
              title: _suggestions.isNotEmpty
                  ? context.l10n.suggestedForYou
                  : context.l10n.smartPlaylists,
              padding: EdgeInsetsDirectional.only(
                start: Adaptive.pagePadding(context),
                end: Adaptive.pagePadding(context),
                top: AppSpacing.sectionGap,
                bottom: AppSpacing.s10,
              ),
              actionLabel: context.l10n.createSmartPlaylist,
              onAction: () async {
                PulsrHaptics.selectionClick();
                await context.push('/smart-playlist-builder');
              },
            ),
            SizedBox(
              height: 152,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: Adaptive.pagePadding(context),
                ),
                itemCount: _suggestions.length + smartPlaylists.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index < _suggestions.length) {
                    final suggestion = _suggestions[index];
                    return PlaylistSuggestionCard(
                      suggestion: suggestion,
                      onTap: () => _createPlaylistFromSuggestion(suggestion),
                    );
                  }
                  final smartIndex = index - _suggestions.length;
                  final pl = smartPlaylists[smartIndex];
                  final count = state.smartPlaylistCounts[pl.id] ?? 0;
                  return StaggeredReveal(
                    index: index,
                    horizontal: true,
                    groupKey: 'smart_playlists',
                    child: SmartPlaylistCard(
                      playlist: pl,
                      songCount: count,
                      isSelected:
                          isTabletLandscape && _selectedPlaylist?.id == pl.id,
                      onTap: () => _onSelectPlaylist(pl),
                      onLongPress: () => _onSelectPlaylist(pl),
                      menuItems: (_) => [
                        PopupMenuItem(
                          value: 'edit-smart',
                          child: Text(context.l10n.editSmartRules),
                        ),
                        PopupMenuItem(
                          value: 'share',
                          child: Text(context.l10n.share),
                        ),
                        PopupMenuItem(
                          value: 'rename',
                          child: Text(context.l10n.rename),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            context.l10n.delete,
                            style: TextStyle(color: p.error),
                          ),
                        ),
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
                    ),
                  );
                },
              ),
            ),
          ],
          PulsrSectionHeader(
            title: context.l10n.playlists,
            padding: EdgeInsetsDirectional.fromSTEB(
              Adaptive.pagePadding(context),
              28,
              Adaptive.pagePadding(context),
              12,
            ),
          ),
          SourceScopeSwitcher(
            persistKey: 'playlists',
            margin: EdgeInsets.symmetric(
              horizontal: Adaptive.pagePadding(context),
            ),
            selectedScope: _scope,
            onChanged: (mode) {
              PulsrHaptics.selectionClick();
              setState(() => _scope = mode);
              if (mode == SourceScope.online) {
                cubit.autoFetchOnlineLibrary();
              }
            },
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedSwitcher(
            duration: context.motion(PulsrMotion.state),
            switchInCurve: context.motionCurve(PulsrMotion.enter),
            switchOutCurve: context.motionCurve(PulsrMotion.exit),
            transitionBuilder: (child, animation) {
              if (!PulsrMotion.shouldAnimate(context)) return child;
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1.0)
                      .animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey(_scope),
              child: _scope == SourceScope.local
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.playlists.isEmpty && state.isLoading)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: Adaptive.pagePadding(context),
                            ),
                            child: SkeletonGrid(
                              columns: isTabletLandscape ? 2 : columns,
                              itemCount: (isTabletLandscape ? 2 : columns) * 2,
                              padding: EdgeInsets.zero,
                            ),
                          )
                        else if (state.playlists.isEmpty &&
                            state.errorMessage != null)
                          PulsrEmptyState(
                            icon: Icons.error_outline_rounded,
                            title: context.l10n.playlistLoadFailed,
                            subtitle: resolveUiErrorMessage(
                                context, state.errorMessage!),
                            primaryActionLabel: context.l10n.retry,
                            onPrimaryAction: cubit.reloadPlaylists,
                          )
                        else if (userPlaylists.isEmpty)
                          PulsrEmptyState(
                            icon: Icons.playlist_add_rounded,
                            title: context.l10n.emptyPlaylists,
                            subtitle: context.l10n.emptyPlaylistsSubtitle,
                            primaryActionLabel: context.l10n.createPlaylist,
                            primaryActionIcon: Icons.add_rounded,
                            onPrimaryAction: () =>
                                _showCreateDialog(context, cubit),
                            secondaryActionLabel: context.l10n.importM3u,
                            secondaryActionIcon: Icons.file_upload_rounded,
                            onSecondaryAction: () => _importPlaylist(context),
                          )
                        else
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: Adaptive.pagePadding(context),
                            ),
                            child: PulsrStaticGrid(
                              crossAxisCount: isTabletLandscape ? 2 : columns,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              childAspectRatio: 1.0,
                              itemCount: userPlaylists.length,
                              itemBuilder: (context, index) {
                                final pl = userPlaylists[index];
                                return StaggeredReveal(
                                  index: index,
                                  groupKey: 'user_playlists',
                                  child: _PlaylistCard(
                                    heroTag: isTabletLandscape
                                        ? null
                                        : 'playlist_${pl.id}',
                                    name: pl.name,
                                    subtitle: context.l10n.browseOfflinePlaylist,
                                    icon: Icons.queue_music_rounded,
                                    gradient: [
                                      p.surfaceContainerHigh,
                                      p.surfaceContainer,
                                    ],
                                    muted: true,
                                    isSelected: isTabletLandscape &&
                                        _selectedPlaylist?.id == pl.id,
                                    onTap: () => _onSelectPlaylist(pl),
                                    onLongPress: () => _onSelectPlaylist(pl),
                                    menuItems: (_) => [
                                      PopupMenuItem(
                                        value: 'export',
                                        child: Text(context.l10n.export),
                                      ),
                                      PopupMenuItem(
                                        value: 'share',
                                        child: Text(context.l10n.share),
                                      ),
                                      PopupMenuItem(
                                        value: 'rename',
                                        child: Text(context.l10n.rename),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text(
                                          context.l10n.delete,
                                          style: TextStyle(color: p.error),
                                        ),
                                      ),
                                    ],
                                    onMenuSelected: (v) {
                                      if (v == 'export') {
                                        _showExportFormatSheet(context, pl);
                                      } else if (v == 'share') {
                                        _exportPlaylistSongs(context, pl,
                                            share: true);
                                      } else if (v == 'rename') {
                                        _showRenameDialog(context, cubit, pl);
                                      } else if (v == 'delete') {
                                        _confirmDelete(context, cubit, pl);
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    )
                  : _OnlinePlaylistsContent(
                      cubit: cubit,
                      playerCubit: playerCubit,
                      onAddPlaylist: () =>
                          _showAddOnlinePlaylistDialog(context, cubit),
                    ),
            ),
          ),
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
    PulsrHaptics.selectionClick();
    final l10n = context.l10n;
    final loadFailedText = l10n.playlistLoadFailed;
    if (context.mounted) {
      PulsrToast.show(
        context,
        message:
            '${l10n.browseFetching} "${playlist.title}" ${l10n.browseForDownload}…',
      );
    }

    try {
      final ytmService = getIt<YtmService>();
      final tracks = await ytmService
          .getPlaylistTracks(
            playlist.playlistId,
            limit: kYtmMaxPlaylistTracks,
          )
          .timeout(const Duration(seconds: 120));
      if (tracks.isNotEmpty) {
        final songs = tracks.map((t) => t.toSongData()).toList();
        final downloadCubit = getIt.isRegistered<YtmDownloadCubit>()
            ? getIt<YtmDownloadCubit>()
            : null;
        if (downloadCubit == null) {
          if (context.mounted) {
            PulsrToast.show(context, message: loadFailedText, isError: true);
          }
          return;
        }
        final report = await downloadCubit.downloadAllDetailed(songs);
        final queuedCount = report.queued;
        final extras = describeBatchOutcomeExtras(
          l10n,
          capped: report.capped,
          failed: report.failed,
          firstError: report.firstError,
          skippedLocal: report.skippedLocal,
        );
        if (context.mounted) {
          PulsrToast.show(
            context,
            message: queuedCount > 0
                ? '${l10n.browseQueued} $queuedCount ${l10n.browseTracksFrom} "${playlist.title}" ${l10n.browseForDownload} ${l10n.browseActiveDownloadsSuffix}$extras'
                : '${l10n.browseAllTracksFrom} "${playlist.title}" ${l10n.browseAlreadyDownloadedOffline}$extras',
            isSuccess: queuedCount > 0 && report.failed == 0,
          );
        }
      } else {
        if (context.mounted) {
          PulsrToast.show(context, message: loadFailedText, isError: true);
        }
      }
    } catch (_) {
      if (context.mounted) {
        PulsrToast.show(context, message: loadFailedText, isError: true);
      }
    }
  }

  Future<void> _downloadCustomPlaylist(
    BuildContext context,
    OnlinePlaylistEntry entry,
  ) async {
    if (entry.tracks.isEmpty) {
      PulsrToast.show(context, message: context.l10n.emptyPlaylist);
      return;
    }
    PulsrHaptics.selectionClick();
    final l10n = context.l10n;
    PulsrToast.show(
      context,
      message:
          '${l10n.browseFetching} "${entry.title}" ${l10n.browseForDownload}…',
    );
    var tracks = entry.tracks;
    try {
      final fullTracks = await getIt<YtmService>()
          .getPlaylistTracks(entry.id, limit: kYtmMaxPlaylistTracks)
          .timeout(const Duration(seconds: 120));
      if (fullTracks.isNotEmpty) tracks = fullTracks;
    } catch (_) {}
    if (!context.mounted) return;

    final songs = tracks.map((t) => t.toSongData()).toList();
    final downloadCubit = context.read<YtmDownloadCubit?>() ??
        (getIt.isRegistered<YtmDownloadCubit>()
            ? getIt<YtmDownloadCubit>()
            : null);
    if (downloadCubit == null) return;
    final report = await downloadCubit.downloadAllDetailed(songs);
    if (!context.mounted) return;
    final queuedCount = report.queued;
    final extras = describeBatchOutcomeExtras(
      context.l10n,
      capped: report.capped,
      failed: report.failed,
      firstError: report.firstError,
      skippedLocal: report.skippedLocal,
    );
    PulsrToast.show(
      context,
      message: queuedCount > 0
          ? '${context.l10n.browseQueued} $queuedCount ${context.l10n.browseTracksFrom} "${entry.title}" ${context.l10n.browseForDownload} ${context.l10n.browseActiveDownloadsSuffix}$extras'
          : '${context.l10n.browseAllTracksFrom} "${entry.title}" ${context.l10n.browseAlreadyDownloadedOffline}$extras',
      isSuccess: queuedCount > 0 && report.failed == 0,
    );
  }

  Future<void> _downloadLikedSongs(
    BuildContext context,
    List<YtmTrack> likedTracks,
  ) async {
    if (likedTracks.isEmpty) {
      PulsrToast.show(context, message: context.l10n.noLikedToDownload);
      return;
    }
    PulsrHaptics.selectionClick();
    final songs = likedTracks.map((t) => t.toSongData()).toList();
    final downloadCubit = context.read<YtmDownloadCubit?>() ??
        (getIt.isRegistered<YtmDownloadCubit>()
            ? getIt<YtmDownloadCubit>()
            : null);
    if (downloadCubit == null) return;
    final report = await downloadCubit.downloadAllDetailed(songs);
    if (!context.mounted) return;
    final queuedCount = report.queued;
    final extras = describeBatchOutcomeExtras(
      context.l10n,
      capped: report.capped,
      failed: report.failed,
      firstError: report.firstError,
      skippedLocal: report.skippedLocal,
    );
    PulsrToast.show(
      context,
      message: queuedCount > 0
          ? '${context.l10n.browseQueued} $queuedCount ${context.l10n.browseLikedSongsForDownload} ${context.l10n.browseActiveDownloadsSuffix}$extras'
          : '${context.l10n.browseAllLikedSongsDownloadedOffline}$extras',
      isSuccess: queuedCount > 0 && report.failed == 0,
    );
  }

  Future<void> _confirmRemoveCustomPlaylist(
    BuildContext context,
    OnlinePlaylistEntry entry,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final undoLabel = context.l10n.undo;
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: '${context.l10n.delete} "${entry.title}"?',
      message: context.l10n.browseCannotBeUndone,
      icon: Icons.delete_outline_rounded,
      confirmLabel: context.l10n.delete,
      isDestructive: true,
    );
    if (confirmed != true) return;
    cubit.removeCustomPlaylist(entry.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text('${entry.title} - $undoLabel?'),
        action: SnackBarAction(
          label: undoLabel,
          onPressed: () => cubit.restoreCustomPlaylist(entry),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ytmAccount = getIt.isRegistered<YtmAccountService>()
        ? getIt<YtmAccountService>()
        : null;

    if (ytmAccount == null) return const SizedBox.shrink();

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
                    child: PulsrCard(
                      variant: PulsrCardVariant.filled,
                      padding: const EdgeInsets.all(AppSpacing.s20),
                      borderRadius: AppRadii.r20,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: p.accentSoft,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.cloud_sync_rounded,
                              size: 28,
                              color: p.accent,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.connectYtm,
                                  style: TextStyle(
                                    fontSize: AppFontSize.callout,
                                    fontWeight: FontWeight.w800,
                                    color: p.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  context.l10n.signInToSync,
                                  style: TextStyle(
                                    fontSize: AppFontSize.label,
                                    color: p.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          PulsrButton(
                            label: context.l10n.signIn,
                            size: PulsrButtonSize.lg,
                            onPressed: () async {
                              final ok = await YtmWebLoginSheet.show(context);
                              if (ok == true) {
                                cubit.autoFetchOnlineLibrary(force: true);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                if (isLoggedIn && online.isCachingLibrary)
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      Adaptive.pagePadding(context),
                      AppSpacing.xs,
                      Adaptive.pagePadding(context),
                      AppSpacing.sm,
                    ),
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s14,
                          vertical: AppSpacing.s10,
                        ),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: AppRadii.r14All,
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          children: [
                            ExcludeSemantics(
                              child: Icon(
                                Icons.cloud_download_rounded,
                                color: p.accent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.onlineCacheProgress(
                                      online.cacheCompleted,
                                      online.cacheTotal,
                                    ),
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: AppFontSize.label,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s6),
                                  PulsrProgressBar(
                                    value: online.cacheTotal == 0
                                        ? null
                                        : online.cacheCompleted /
                                            online.cacheTotal,
                                    height: 4,
                                    color: p.accent,
                                    backgroundColor: p.surfaceContainerHigh,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (isLoggedIn) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: Adaptive.pagePadding(context),
                    ),
                    child: _LikedMusicOnlineCard(
                      status: online.likedStatus,
                      trackCount: online.likedTracks.length,
                      error: online.likedError,
                      onFetch: () => cubit.fetchLikedSongsPlaylist(),
                      onDownload: () =>
                          _downloadLikedSongs(context, online.likedTracks),
                      onPlay: () => context.push(
                        '/online-playlist?id=VLLM&title=${Uri.encodeComponent(context.l10n.likedMusic)}&kind=${OnlineLibraryKind.liked}',
                        extra: OnlinePlaylistDetailArgs(
                          playlistId: 'VLLM',
                          title: context.l10n.likedMusic,
                          subtitle: 'YouTube Music',
                          initialTracks: online.likedTracks,
                          kind: OnlineLibraryKind.liked,
                        ),
                      ),
                    ),
                  ),
                  PulsrSectionHeader(
                    title: context.l10n.accountPlaylists,
                    padding: EdgeInsetsDirectional.fromSTEB(
                      Adaptive.pagePadding(context),
                      24,
                      Adaptive.pagePadding(context),
                      10,
                    ),
                    trailing: online.accountStatus == YtmFetchStatus.loading
                        ? PulsrProgressBar.circular(
                            size: AppSpacing.s14,
                            strokeWidth: 2,
                            color: p.accent,
                          )
                        : (online.accountPlaylists.isNotEmpty
                            ? Text(
                                context.l10n.accountPlaylistCount(
                                  online.accountPlaylists.length,
                                ),
                                style: TextStyle(
                                  color: p.textTertiary,
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              )
                            : null),
                  ),
                  if (online.accountStatus == YtmFetchStatus.loading &&
                      online.accountPlaylists.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context),
                      ),
                      child: const SkeletonList(itemCount: 4),
                    )
                  else if (online.accountStatus == YtmFetchStatus.error &&
                      online.accountPlaylists.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context),
                        vertical: 10,
                      ),
                      child: Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: p.surfaceContainer,
                            borderRadius: AppRadii.r16All,
                            border: Border.all(color: p.hairline),
                          ),
                          child: Row(
                            children: [
                              ExcludeSemantics(
                                child: Icon(
                                  Icons.error_outline_rounded,
                                  color: p.error,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  online.accountError ??
                                      context.l10n
                                          .browseFailedToLoadAccountPlaylists,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.label,
                                  ),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(
                                    AppSpacing.minTouchTarget,
                                    AppSpacing.minTouchTarget,
                                  ),
                                  tapTargetSize: MaterialTapTargetSize.padded,
                                ),
                                onPressed: () => cubit.fetchAccountPlaylists(),
                                child: Text(context.l10n.retry),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (online.accountPlaylists.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.s18),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: AppRadii.r18All,
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.playlist_remove_rounded,
                              color: p.textTertiary,
                              size: 26,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                context.l10n.noAccountPlaylists,
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.bodySmall,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context),
                      ),
                      child: PulsrStaticGrid(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.0,
                        itemCount: online.accountPlaylists.length,
                        itemBuilder: (context, i) {
                          final pl = online.accountPlaylists[i];
                          return _AccountPlaylistCard(
                            playlist: pl,
                            onTap: () => context.push(
                              '/online-playlist?id=${Uri.encodeComponent(pl.playlistId)}&title=${Uri.encodeComponent(pl.title)}&kind=${OnlineLibraryKind.account}',
                              extra: pl,
                            ),
                            onDownload: () =>
                                _downloadAccountPlaylist(context, pl),
                          );
                        },
                      ),
                    ),
                ],
                if (online.customPlaylists.isNotEmpty ||
                    online.customStatus == YtmFetchStatus.error ||
                    online.customStatus == YtmFetchStatus.loading) ...[
                  PulsrSectionHeader(
                    title: context.l10n.addedPlaylists,
                    padding: EdgeInsetsDirectional.fromSTEB(
                      Adaptive.pagePadding(context),
                      24,
                      Adaptive.pagePadding(context),
                      10,
                    ),
                  ),
                  if (online.customStatus == YtmFetchStatus.error &&
                      online.customPlaylists.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context),
                        vertical: 10,
                      ),
                      child: Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: p.surfaceContainer,
                            borderRadius: AppRadii.r16All,
                            border: Border.all(color: p.hairline),
                          ),
                          child: Row(
                            children: [
                              ExcludeSemantics(
                                child: Icon(
                                  Icons.error_outline_rounded,
                                  color: p.error,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  online.customError ??
                                      context.l10n.browseFailedToFetch,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.label,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (online.customStatus == YtmFetchStatus.loading &&
                      online.customPlaylists.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context),
                      ),
                      child: const SkeletonList(itemCount: 2),
                    )
                  else if (online.customPlaylists.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context),
                      ),
                      child: PulsrStaticGrid(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.0,
                        itemCount: online.customPlaylists.length,
                        itemBuilder: (context, i) {
                          final pl = online.customPlaylists[i];
                          return _OnlinePlaylistCard(
                            entry: pl,
                            onTap: () => context.push(
                              '/online-playlist?id=${Uri.encodeComponent(pl.id)}&title=${Uri.encodeComponent(pl.title)}&kind=${OnlineLibraryKind.custom}',
                              extra: pl,
                            ),
                            onDownload: () =>
                                _downloadCustomPlaylist(context, pl),
                            onRemove: () =>
                                _confirmRemoveCustomPlaylist(context, pl),
                          );
                        },
                      ),
                    ),
                ],
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    Adaptive.pagePadding(context),
                    16,
                    Adaptive.pagePadding(context),
                    0,
                  ),
                  child: Semantics(
                    button: true,
                    label: context.l10n.addYtmUrl,
                    child: InkWell(
                      onTap: () {
                        PulsrHaptics.selectionClick();
                        onAddPlaylist();
                      },
                      borderRadius: AppRadii.r18All,
                      child: DashedBorderCard(
                        color: AppColors.ytRed,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const ExcludeSemantics(
                              child: Icon(
                                Icons.add_rounded,
                                color: AppColors.ytRed,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              context.l10n.addYtmUrl,
                              style: const TextStyle(
                                color: AppColors.ytRed,
                                fontWeight: FontWeight.w800,
                                fontSize: AppFontSize.body,
                              ),
                            ),
                          ],
                        ),
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

