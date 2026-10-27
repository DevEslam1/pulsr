// lib/features/radio/presentation/radio_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/radio_station_store.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/search_algorithm_utils.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../domain/models/radio_station.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/cubit/player_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import '../../../core/widgets/staggered_reveal.dart';
import '../../../core/widgets/cached_artwork.dart';
import 'widgets/radio_directory_sheet.dart';
import '../../../core/responsive/pulsr_layout_metrics.dart';

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final RadioStationStore _store = RadioStationStore();
  final TextEditingController _searchController = TextEditingController();
  List<RadioStation> _stations = const [];
  bool _loading = true;
  bool _loadFailed = false;
  String _searchQuery = '';
  String _selectedGenre = 'All';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final text = _searchController.text.trim();
      if (text != _searchQuery) {
        setState(() => _searchQuery = text);
      }
    });
    _store.ready.then((_) {
      if (!mounted) return;
      setState(() {
        _stations = _store.list;
        _loading = false;
        _loadFailed = _store.loadFailed;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() => _stations = _store.list);
  }

  Future<void> _reload() async {
    await _store.load();
    if (!mounted) return;
    setState(() {
      _stations = _store.list;
      _loading = false;
      _loadFailed = _store.loadFailed;
    });
  }

  List<String> get _availableGenres {
    final set = <String>{};
    for (final s in _stations) {
      final g = s.genre?.trim();
      if (g != null && g.isNotEmpty) {
        set.add(g);
      }
    }
    final list = set.toList()..sort();
    if (list.remove('Quran')) {
      return ['All', 'Quran', ...list];
    }
    return ['All', ...list];
  }

  String? _cachedFilterKey;
  List<RadioStation>? _cachedFilteredStations;

  List<RadioStation> get _filteredStations {
    final key =
        '$_selectedGenre|$_searchQuery|${_stations.length}|${identityHashCode(_stations)}';
    if (_cachedFilterKey == key && _cachedFilteredStations != null) {
      return _cachedFilteredStations!;
    }
    final filtered = _stations.where((s) {
      if (_selectedGenre != 'All') {
        if (s.genre?.toLowerCase() != _selectedGenre.toLowerCase()) {
          return false;
        }
      }
      if (_searchQuery.isNotEmpty) {
        final query = SearchAlgorithmUtils.normalize(_searchQuery);
        final matchesName =
            SearchAlgorithmUtils.normalize(s.name).contains(query);
        final matchesGenre = s.genre != null &&
            SearchAlgorithmUtils.normalize(s.genre!).contains(query);
        final matchesUrl =
            s.url.toLowerCase().contains(_searchQuery.toLowerCase());
        if (!matchesName && !matchesGenre && !matchesUrl) return false;
      }
      return true;
    }).toList();
    _cachedFilterKey = key;
    _cachedFilteredStations = filtered;
    return filtered;
  }

  String _nameForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url; // fallback to full URL
    return uri.host;
  }

  Future<void> _showAddDialog({RadioStation? initial}) async {
    final station = await PulsrDialogHelper.showCustomDialog<RadioStation>(
      context,
      builder: (_) => _AddStationDialog(initial: initial),
    );
    if (station == null || !mounted) return;

    // Refuse a URL that already belongs to a different station: `add`/`replace`
    // would otherwise silently delete that station.
    final collision = _store.hasUrlCollision(
      station.url,
      exceptId: initial?.id ?? station.id,
    );
    if (collision) {
      PulsrToast.show(
        context,
        message: context.l10n.radioDuplicateUrl,
        isError: true,
      );
      return;
    }

    if (initial != null) {
      final replaced = await _store.replace(initial, station);
      if (!replaced && mounted) {
        PulsrToast.show(
          context,
          message: context.l10n.radioInvalidUrl,
          isError: true,
        );
        return;
      }
    } else {
      await _store.add(station);
    }
    _refresh();
  }

  Future<void> _showStationActions(RadioStation station) async {
    await PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: Text(context.l10n.radioEdit),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _showAddDialog(initial: station);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: Text(context.l10n.radioDelete),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _confirmDelete(station);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }

  Future<void> _showImportDialog() async {
    final content = await PulsrDialogHelper.showCustomDialog<String>(
      context,
      builder: (_) => const _ImportStationsDialog(),
    );
    if (content == null || content.trim().isEmpty || !mounted) return;

    final urls = RadioStationStore.extractStreamUrls(content);
    if (urls.isEmpty) {
      PulsrToast.show(context,
          message: context.l10n.radioNoStreamsFound, isError: true);
      return;
    }
    await _store.addAll([
      for (final url in urls)
        RadioStation.create(name: _nameForUrl(url), url: url),
    ]);
    _refresh();
    if (mounted) {
      PulsrToast.show(
        context,
        message: context.l10n.radioImportedCount(urls.length),
        isSuccess: true,
      );
    }
  }

  Future<void> _importCurated() async {
    final added = await _store.importCurated();
    _refresh();
    if (!mounted) return;
    PulsrToast.show(
      context,
      message: added > 0
          ? context.l10n.radioCuratedAdded(added)
          : context.l10n.radioCuratedUpToDate,
      isSuccess: added > 0,
    );
  }

  Future<void> _confirmDelete(RadioStation station) async {
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: context.l10n.radioDeleteTitle,
      message: context.l10n.radioDeleteMessage(station.name),
      icon: Icons.delete_outline_rounded,
      confirmLabel: context.l10n.radioDelete,
      isDestructive: true,
    );
    if (confirmed == true) {
      await _store.remove(station.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();
    final availableGenres = _availableGenres;
    final filtered = _filteredStations;

    return PulsrPagePopScope(
        child: Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.surface,
        elevation: 0,
        leading: const PulsrBackButton(),
        title: Text(context.l10n.radioTitle),
        actions: [
          IconButton(
            constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget),
            tooltip: context.l10n.radioDirectoryBrowse,
            icon: const Icon(Icons.public_rounded),
            onPressed: () => RadioDirectorySheet.show(context, store: _store),
          ),
          IconButton(
            constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget),
            tooltip: context.l10n.radioCuratedBrowse,
            icon: const Icon(Icons.explore_rounded),
            onPressed: _importCurated,
          ),
          IconButton(
            constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget),
            tooltip: context.l10n.radioImportPlaylist,
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: _showImportDialog,
          ),
          IconButton(
            constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget),
            tooltip: context.l10n.radioAddStation,
            icon: const Icon(Icons.add_rounded),
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: PulsrLayoutMetrics.contentConstraints(context),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadFailed && _stations.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height -
                                kToolbarHeight -
                                140,
                            child: PulsrEmptyState(
                              icon: Icons.error_outline_rounded,
                              title: context.l10n.somethingWentWrong,
                              subtitle: context.l10n.radioEmptySubtitle,
                              primaryActionLabel: context.l10n.retry,
                              onPrimaryAction: _reload,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _stations.isEmpty
                      ? RefreshIndicator(
                          onRefresh: _reload,
                          color: p.accent,
                          backgroundColor: p.surfaceContainer,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: MediaQuery.of(context).size.height -
                                  kToolbarHeight -
                                  100,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.xl),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 76,
                                        height: 76,
                                        decoration: BoxDecoration(
                                          color: p.accentContainer
                                              .withValues(alpha: 0.35),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: p.accent
                                                .withValues(alpha: 0.25),
                                            width: 1.5,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(Icons.radio_rounded,
                                            size: 38, color: p.accent),
                                      ),
                                      const SizedBox(height: AppSpacing.s20),
                                      Text(
                                        context.l10n.radioEmptyTitle,
                                        style: TextStyle(
                                          color: p.textPrimary,
                                          fontSize: AppFontSize.title,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        context.l10n.radioEmptySubtitle,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: AppFontSize.bodySmall,
                                          height: 1.45,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.lg),
                                      FilledButton.icon(
                                        onPressed: _showAddDialog,
                                        icon: const Icon(Icons.add_rounded,
                                            size: 20),
                                        label: Text(
                                          context.l10n.radioAddStation,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: p.accent,
                                          foregroundColor: p.onAccent,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 22,
                                              vertical: AppSpacing.sm),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: AppRadii.r14All,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.s10),
                                      OutlinedButton.icon(
                                        onPressed: _importCurated,
                                        icon: const Icon(Icons.explore_rounded,
                                            size: 18),
                                        label: Text(
                                            context.l10n.radioCuratedBrowse),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: p.accent,
                                          side: BorderSide(
                                              color: p.accent
                                                  .withValues(alpha: 0.5)),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: AppSpacing.s20,
                                              vertical: AppSpacing.sm),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: AppRadii.r14All,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  AppSpacing.md,
                                  AppSpacing.sm,
                                  AppSpacing.md,
                                  AppSpacing.xs),
                              child: TextField(
                                controller: _searchController,
                                style: TextStyle(
                                    color: p.textPrimary,
                                    fontSize: AppFontSize.bodySmall),
                                decoration: InputDecoration(
                                  hintText: context.l10n.radioSearchHint,
                                  hintStyle: TextStyle(
                                      color: p.textTertiary,
                                      fontSize: AppFontSize.bodySmall),
                                  prefixIcon: Icon(Icons.search_rounded,
                                      color: p.textSecondary, size: 20),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          constraints: const BoxConstraints(
                                              minWidth:
                                                  AppSpacing.minTouchTarget,
                                              minHeight:
                                                  AppSpacing.minTouchTarget),
                                          icon: Icon(Icons.close_rounded,
                                              color: p.textSecondary, size: 18),
                                          tooltip: context.l10n.clear,
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: p.surfaceContainerHigh
                                      .withValues(alpha: 0.5),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                      vertical: AppSpacing.xs),
                                  border: OutlineInputBorder(
                                    borderRadius: AppRadii.r12All,
                                    borderSide: BorderSide(color: p.hairline),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: AppRadii.r12All,
                                    borderSide: BorderSide(color: p.hairline),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: AppRadii.r12All,
                                    borderSide:
                                        BorderSide(color: p.accent, width: 1.5),
                                  ),
                                ),
                              ),
                            ),
                            if (availableGenres.length > 2)
                              SizedBox(
                                height: 38,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md),
                                  itemCount: availableGenres.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: AppSpacing.xs),
                                  itemBuilder: (context, idx) {
                                    final g = availableGenres[idx];
                                    final isSelected = _selectedGenre == g;
                                    return FilterChip(
                                      label: Text(
                                          g == 'All' ? context.l10n.all : g),
                                      selected: isSelected,
                                      selectedColor:
                                          p.accent.withValues(alpha: 0.2),
                                      checkmarkColor: p.accent,
                                      labelStyle: TextStyle(
                                        color: isSelected
                                            ? p.accent
                                            : p.textSecondary,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        fontSize: AppFontSize.caption,
                                      ),
                                      side: BorderSide(
                                        color: isSelected
                                            ? p.accent.withValues(alpha: 0.4)
                                            : p.hairline,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: AppRadii.r12All,
                                      ),
                                      onSelected: (_) {
                                        setState(() => _selectedGenre = g);
                                      },
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: AppSpacing.xs),
                            Expanded(
                              child: filtered.isEmpty
                                  ? RefreshIndicator(
                                      onRefresh: () async => _refresh(),
                                      color: p.accent,
                                      backgroundColor: p.surfaceContainer,
                                      child: SingleChildScrollView(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        child: SizedBox(
                                          height: 350,
                                          child: PulsrEmptyState(
                                            icon: Icons.search_off_rounded,
                                            title: context.l10n
                                                .radioNoStationsMatch(
                                                    _searchQuery),
                                            subtitle: context
                                                .l10n.radioNoStationsMatchDesc,
                                          ),
                                        ),
                                      ),
                                    )
                                  : RefreshIndicator(
                                      onRefresh: () async => _refresh(),
                                      color: p.accent,
                                      backgroundColor: p.surfaceContainer,
                                      child: ListView.separated(
                                        padding: EdgeInsets.only(
                                            top: AppSpacing.xs,
                                            bottom:
                                                PulsrLayoutMetrics.scrollBottom(
                                                    context)),
                                        itemCount: filtered.length,
                                        separatorBuilder: (_, __) => Divider(
                                          height: 1,
                                          indent: 72,
                                          endIndent: 16,
                                          color: p.hairline,
                                        ),
                                        itemBuilder: (context, index) {
                                          final station = filtered[index];
                                          return StaggeredReveal(
                                            index: index,
                                            groupKey: filtered.length,
                                            child: BlocBuilder<PlayerCubit,
                                                PlayerState>(
                                              buildWhen: (prev, curr) =>
                                                  prev.currentSong?.path !=
                                                      curr.currentSong?.path ||
                                                  prev.currentSong?.album !=
                                                      curr.currentSong?.album ||
                                                  prev.isPlaying !=
                                                      curr.isPlaying,
                                              builder: (context, playerState) {
                                                final isCurrent = playerState
                                                        .currentSong?.path ==
                                                    station.url;
                                                final isPlaying = isCurrent &&
                                                    playerState.isPlaying;
                                                final icyNowPlaying = isCurrent
                                                    ? (playerState
                                                            .currentSong?.album
                                                            .trim() ??
                                                        '')
                                                    : '';

                                                return ListTile(
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          horizontal:
                                                              AppSpacing.md,
                                                          vertical:
                                                              AppSpacing.xxs),
                                                  leading: _StationArtwork(
                                                    station: station,
                                                    isPlaying: isPlaying,
                                                  ),
                                                  title: Text(
                                                    station.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: isCurrent
                                                          ? p.accent
                                                          : p.textPrimary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize:
                                                          AppFontSize.callout,
                                                    ),
                                                  ),
                                                  subtitle: Row(
                                                    children: [
                                                      if (station.genre !=
                                                              null &&
                                                          station.genre!
                                                              .isNotEmpty) ...[
                                                        Container(
                                                          margin:
                                                              const EdgeInsetsDirectional
                                                                  .only(end: 6),
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 6,
                                                                  vertical:
                                                                      1.5),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: p
                                                                .accentContainer
                                                                .withValues(
                                                                    alpha:
                                                                        0.35),
                                                            borderRadius:
                                                                AppRadii.r6All,
                                                          ),
                                                          child: Text(
                                                            station.genre!,
                                                            style: TextStyle(
                                                              color: p.accent,
                                                              fontSize:
                                                                  AppFontSize
                                                                      .tiny,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                      Expanded(
                                                        child: Text(
                                                          icyNowPlaying
                                                                  .isNotEmpty
                                                              ? '♫ $icyNowPlaying'
                                                              : station.url,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                              color: icyNowPlaying
                                                                      .isNotEmpty
                                                                  ? p.accent
                                                                  : p
                                                                      .textSecondary,
                                                              fontWeight: icyNowPlaying
                                                                      .isNotEmpty
                                                                  ? FontWeight
                                                                      .w600
                                                                  : FontWeight
                                                                      .normal,
                                                              fontSize:
                                                                  AppFontSize
                                                                      .label),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  trailing: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        constraints: const BoxConstraints(
                                                            minWidth: AppSpacing
                                                                .minTouchTarget,
                                                            minHeight: AppSpacing
                                                                .minTouchTarget),
                                                        tooltip: context
                                                            .l10n.radioEdit,
                                                        icon: Icon(
                                                            Icons.edit_rounded,
                                                            color:
                                                                p.textSecondary,
                                                            size: 22),
                                                        onPressed: () =>
                                                            _showAddDialog(
                                                                initial:
                                                                    station),
                                                      ),
                                                      IconButton(
                                                        constraints: const BoxConstraints(
                                                            minWidth: AppSpacing
                                                                .minTouchTarget,
                                                            minHeight: AppSpacing
                                                                .minTouchTarget),
                                                        tooltip: isPlaying
                                                            ? context.l10n.pause
                                                            : context
                                                                .l10n.radioPlay,
                                                        icon: Icon(
                                                          isPlaying
                                                              ? Icons
                                                                  .pause_circle_filled_rounded
                                                              : Icons
                                                                  .play_circle_fill_rounded,
                                                          color: p.accent,
                                                          size: 32,
                                                        ),
                                                        onPressed: () {
                                                          if (isCurrent) {
                                                            playerCubit
                                                                .togglePlayPause();
                                                          } else {
                                                            playerCubit
                                                                .playRadioStation(
                                                                    station);
                                                          }
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                  onTap: () {
                                                    if (isCurrent) {
                                                      playerCubit
                                                          .togglePlayPause();
                                                    } else {
                                                      playerCubit
                                                          .playRadioStation(
                                                              station);
                                                    }
                                                  },
                                                  onLongPress: () =>
                                                      _showStationActions(
                                                          station),
                                                );
                                              },
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                            ),
                          ],
                        ),
        ),
      ),
    ));
  }
}

class _StationArtwork extends StatelessWidget {
  const _StationArtwork({required this.station, required this.isPlaying});

  final RadioStation station;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final artworkUrl =
        (station.artworkUrl != null && station.artworkUrl!.isNotEmpty)
            ? station.artworkUrl
            : RadioStationStore.resolveArtworkForStation(
                id: station.id,
                name: station.name,
                url: station.url,
              );
    if (artworkUrl == null || artworkUrl.isEmpty) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isPlaying
              ? p.accent.withValues(alpha: 0.2)
              : p.accentContainer.withValues(alpha: 0.35),
          borderRadius: AppRadii.r12All,
          border: isPlaying ? Border.all(color: p.accent, width: 1.5) : null,
        ),
        alignment: Alignment.center,
        child: Icon(
          isPlaying ? Icons.graphic_eq_rounded : Icons.radio_rounded,
          color: p.accent,
          size: 22,
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CachedArtwork(
          id: 0,
          remoteUrl: artworkUrl,
          size: 44,
          borderRadius: AppRadii.r12,
          fallbackIcon: Icons.radio_rounded,
        ),
        if (isPlaying)
          PositionedDirectional(
            end: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: p.accent,
                shape: BoxShape.circle,
                border: Border.all(color: p.bg, width: 1.5),
              ),
              child: Icon(
                Icons.graphic_eq_rounded,
                color: p.onAccent,
                size: 11,
              ),
            ),
          ),
      ],
    );
  }
}

class _AddStationDialog extends StatefulWidget {
  const _AddStationDialog({this.initial});

  /// When non-null the dialog edits an existing station instead of adding one.
  final RadioStation? initial;

  @override
  State<_AddStationDialog> createState() => _AddStationDialogState();
}

class _AddStationDialogState extends State<_AddStationDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _genreController;
  String? _urlError;
  String? _artworkUrl;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _urlController = TextEditingController(text: widget.initial?.url ?? '');
    _genreController = TextEditingController(text: widget.initial?.genre ?? '');
    _artworkUrl = widget.initial?.artworkUrl ??
        RadioStationStore.resolveArtworkForStation(
          id: widget.initial?.id,
          name: widget.initial?.name,
          url: widget.initial?.url,
        );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _genreController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() => _artworkUrl = picked.path);
      }
    } catch (_) {}
  }

  /// Returns a user-facing reason the URL is invalid, or null when valid.
  String? _validateUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return context.l10n.radioErrorEnterUrl;
    final scheme = url.toLowerCase();
    if (!scheme.startsWith('http://') && !scheme.startsWith('https://')) {
      return context.l10n.radioErrorUrlScheme;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return context.l10n.radioErrorInvalidUrl;
    }
    if (!RadioStation.isHttpUrl(url)) {
      return context.l10n.radioErrorInvalidUrl;
    }
    return null;
  }

  void _submit() {
    final url = _urlController.text.trim();
    final error = _validateUrl(url);
    if (error != null) {
      setState(() => _urlError = error);
      return;
    }
    final name = _nameController.text.trim();
    final genre = _genreController.text.trim();
    final effectiveArt = _artworkUrl ??
        RadioStationStore.resolveArtworkForStation(
          name: name,
          url: url,
        );
    Navigator.of(context, rootNavigator: true).pop(
      RadioStation.create(
        name: name,
        url: url,
        genre: genre.isNotEmpty ? genre : null,
        artworkUrl: effectiveArt,
        lastPlayed: widget.initial?.lastPlayed,
      ),
    );
  }

  Widget _buildPresetChip(String label, String assetPath) {
    final isSelected = _artworkUrl == assetPath;
    final p = context.palette;
    return ChoiceChip(
      avatar: ClipOval(
        child: Image.asset(assetPath,
            width: 18,
            height: 18,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 14)),
      ),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      onSelected: (val) {
        setState(() => _artworkUrl = val ? assetPath : null);
      },
      selectedColor: p.accent.withValues(alpha: 0.25),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulsrDialog(
      icon: Icon(Icons.radio_rounded, color: p.accent, size: 28),
      title: Text(_isEditing
          ? context.l10n.radioEditStation
          : context.l10n.radioAddStation),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.r16All,
                        color: p.surfaceContainerHigh,
                        border: Border.all(color: p.hairline),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _artworkUrl != null && _artworkUrl!.isNotEmpty
                          ? CachedArtwork(
                              id: 0,
                              remoteUrl: _artworkUrl,
                              size: 68,
                              borderRadius: 16,
                              fallbackIcon: Icons.radio_rounded,
                            )
                          : Icon(Icons.radio_rounded,
                              color: p.accent, size: 36),
                    ),
                  ),
                  PositionedDirectional(
                    end: -4,
                    bottom: -4,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: p.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.camera_alt_rounded,
                            color: p.onAccent, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s10),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              alignment: WrapAlignment.center,
              children: [
                _buildPresetChip(
                    'القرآن - القاهرة', RadioStationStore.quranCairoArtwork),
                _buildPresetChip('الحصري', RadioStationStore.hussaryArtwork),
                _buildPresetChip('المنشاوي', RadioStationStore.minshawiArtwork),
                _buildPresetChip(
                    'عبد الباسط', RadioStationStore.abdulBasitArtwork),
                _buildPresetChip(
                    'مصطفى إسماعيل', RadioStationStore.mustafaIsmailArtwork),
                _buildPresetChip('تراتيل', RadioStationStore.tarteelArtwork),
                if (_artworkUrl != null)
                  ActionChip(
                    avatar: const Icon(Icons.clear_rounded, size: 14),
                    label: const Text('إلغاء الصورة',
                        style: TextStyle(fontSize: 11)),
                    onPressed: () => setState(() => _artworkUrl = null),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s14),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              onChanged: (text) {
                if (_artworkUrl == null ||
                    _artworkUrl!.startsWith('assets/Pictures/')) {
                  final detected = RadioStationStore.resolveArtworkForStation(
                    name: text,
                    url: _urlController.text,
                  );
                  if (detected != _artworkUrl) {
                    setState(() => _artworkUrl = detected);
                  }
                }
              },
              style:
                  TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
              decoration: InputDecoration(
                labelText: context.l10n.radioStationName,
                labelStyle: TextStyle(color: p.textSecondary),
                hintText: context.l10n.browseRadioNameHint,
                hintStyle: TextStyle(color: p.textTertiary),
                filled: true,
                fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: AppRadii.r12All,
                  borderSide: BorderSide(color: p.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadii.r12All,
                  borderSide: BorderSide(color: p.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadii.r12All,
                  borderSide: BorderSide(color: p.accent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s14),
            TextField(
              controller: _genreController,
              textInputAction: TextInputAction.next,
              style:
                  TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
              decoration: InputDecoration(
                labelText: context.l10n.radioGenreLabel,
                labelStyle: TextStyle(color: p.textSecondary),
                hintText: context.l10n.radioGenreHint,
                hintStyle: TextStyle(color: p.textTertiary),
                filled: true,
                fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: AppRadii.r12All,
                  borderSide: BorderSide(color: p.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadii.r12All,
                  borderSide: BorderSide(color: p.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadii.r12All,
                  borderSide: BorderSide(color: p.accent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s14),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style:
                  TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
              decoration: InputDecoration(
                labelText: context.l10n.radioStationUrl,
                labelStyle: TextStyle(color: p.textSecondary),
                hintText: 'https://...',
                hintStyle: TextStyle(color: p.textTertiary),
                errorText: _urlError,
                filled: true,
                fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: AppRadii.r12All,
                  borderSide: BorderSide(color: p.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadii.r12All,
                  borderSide: BorderSide(color: p.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadii.r12All,
                  borderSide: BorderSide(color: p.accent, width: 1.5),
                ),
              ),
              onChanged: (_) {
                if (_urlError != null) {
                  setState(() => _urlError = null);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
          style: TextButton.styleFrom(
            foregroundColor: p.textSecondary,
          ),
          child: Text(context.l10n.radioCancel),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20, vertical: AppSpacing.sm),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r12All,
            ),
          ),
          child: Text(
            _isEditing ? context.l10n.radioSave : context.l10n.radioAdd,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ImportStationsDialog extends StatefulWidget {
  const _ImportStationsDialog();

  @override
  State<_ImportStationsDialog> createState() => _ImportStationsDialogState();
}

class _ImportStationsDialogState extends State<_ImportStationsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulsrDialog(
      icon: Icon(Icons.download_rounded, color: p.accent, size: 28),
      title: Text(context.l10n.radioImportTitle),
      content: SingleChildScrollView(
        child: TextField(
          controller: _controller,
          maxLines: 6,
          style:
              TextStyle(color: p.textPrimary, fontSize: AppFontSize.bodySmall),
          decoration: InputDecoration(
            hintText: context.l10n.radioImportHint,
            hintStyle: TextStyle(
                color: p.textTertiary, fontSize: AppFontSize.bodySmall),
            filled: true,
            fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: AppRadii.r12All,
              borderSide: BorderSide(color: p.hairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.r12All,
              borderSide: BorderSide(color: p.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadii.r12All,
              borderSide: BorderSide(color: p.accent, width: 1.5),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
          style: TextButton.styleFrom(
            foregroundColor: p.textSecondary,
          ),
          child: Text(context.l10n.radioCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(_controller.text),
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20, vertical: AppSpacing.sm),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r12All,
            ),
          ),
          child: Text(
            context.l10n.radioImport,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
