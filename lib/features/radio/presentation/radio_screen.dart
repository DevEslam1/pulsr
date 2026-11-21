// lib/features/radio/presentation/radio_screen.dart
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/services/radio_station_store.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/pulsr_haptics.dart';
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
import '../../sheets/sort_filter_sheet.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import '../../../core/widgets/staggered_reveal.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/marquee_text.dart';
import 'widgets/radio_directory_sheet.dart';
import '../../../core/responsive/pulsr_layout_metrics.dart';

part 'radio_screen_dialogs.dart';

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
    RadioStationStore.radioSortBy.addListener(_onSortChanged);
    RadioStationStore.radioSortAsc.addListener(_onSortChanged);
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
    RadioStationStore.radioSortBy.removeListener(_onSortChanged);
    RadioStationStore.radioSortAsc.removeListener(_onSortChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSortChanged() {
    if (!mounted) return;
    setState(() => _cachedFilterKey = null);
  }

  void _refresh() {
    if (mounted) {
      setState(() {
        _stations = _store.list;
        _cachedFilterKey = null;
      });
    }
  }

  Future<void> _reload() async {
    await _store.ready;
    if (!mounted) return;
    setState(() {
      _stations = _store.list;
      _loading = false;
      _loadFailed = _store.loadFailed;
      _cachedFilterKey = null;
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
    final sortBy = RadioStationStore.radioSortBy.value;
    final sortAscending = RadioStationStore.radioSortAsc.value;
    final key =
        '$_selectedGenre|$_searchQuery|$sortBy|$sortAscending|${_stations.length}|${identityHashCode(_stations)}';
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

    final langCode = Localizations.localeOf(context).languageCode;
    switch (sortBy) {
      case 'name':
        filtered.sort((a, b) {
          final nameA = RadioStationStore.localizedStationName(a, langCode);
          final nameB = RadioStationStore.localizedStationName(b, langCode);
          final cmp = nameA.toLowerCase().compareTo(nameB.toLowerCase());
          return sortAscending ? cmp : -cmp;
        });
        break;
      case 'recent':
      case 'lastPlayed':
        filtered.sort((a, b) {
          final timeA = a.lastPlayed ?? 0;
          final timeB = b.lastPlayed ?? 0;
          if (timeA != timeB) {
            final cmp = timeB.compareTo(timeA);
            return sortAscending ? -cmp : cmp;
          }
          return 0;
        });
        break;
      case 'default':
      default:
        if (!sortAscending) {
          final reversed = filtered.reversed.toList();
          filtered
            ..clear()
            ..addAll(reversed);
        }
        break;
    }

    _cachedFilterKey = key;
    _cachedFilteredStations = filtered;
    return filtered;
  }

  String _nameForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return uri.host;
  }

  String _stationFallbackSubtitle(RadioStation station, {bool? isArabic}) {
    final arabic =
        isArabic ?? (Localizations.localeOf(context).languageCode == 'ar');
    if (RadioStationStore.isQuranStation(station)) {
      final name = station.name;
      final id = station.id;
      if (id == 'cur-quran-minshawi-rare' ||
          name.contains('نادرة') ||
          name.contains('نادر')) {
        return arabic
            ? 'تلاوات نادرة ومحافل خاشعة • تسجيلات تاريخية'
            : 'Rare Historic Recitations & Concerts';
      }
      if (id == 'cur-quran-khashia' ||
          name.contains('خاشعة') ||
          name.contains('خاشع')) {
        return arabic
            ? 'تلاوات خاشعة ومؤثرة • كبار القراء'
            : 'Rare Reverent Recitations • Master Reciters';
      }
      if (name.contains('مجود')) {
        return arabic
            ? 'المصحف المجود • تلاوة متقنة'
            : 'Holy Quran • Mujawwad Recitation';
      }
      if (name.contains('مرتل') || name.contains('ترتيل')) {
        return arabic
            ? 'المصحف المرتل • تلاوة خاشعة'
            : 'Holy Quran • Murattal Recitation';
      }
      if (name.contains('القاهرة') || id.contains('cairo')) {
        return arabic
            ? 'بث مباشر من القاهرة • عبر الأثير'
            : 'Live Broadcast from Cairo • Over the Air';
      }
      if (name.contains('السعودية') ||
          name.contains('مكة') ||
          id.contains('makkah')) {
        return arabic
            ? 'بث مباشر من الحرم المكي الشريف'
            : 'Live from the Holy Mosque in Mecca';
      }
      if (name.contains('تراتيل') || id.contains('tarteel')) {
        return arabic
            ? 'تراتيل قصيرة عذبة على مدار الساعة'
            : 'Sweet Short Recitations 24/7';
      }
      if (name.contains('سكينة') || id.contains('sakeenah')) {
        return arabic
            ? 'آيات السكينة والطمأنينة'
            : 'Verses of Serenity & Tranquility';
      }
      return arabic
          ? 'إذاعة القرآن الكريم • بث مباشر'
          : 'Holy Quran Radio • Live Stream';
    }
    return station.url;
  }

  Future<void> _showAddDialog({RadioStation? initial}) async {
    final station = await PulsrDialogHelper.showCustomDialog<RadioStation>(
      context,
      builder: (_) => _AddStationDialog(initial: initial),
    );
    if (station == null || !mounted) return;

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

  void _openSortFilterSheet() {
    PulsrHaptics.selectionClick();
    SortFilterSheet.show(
      context,
      currentSort: RadioStationStore.radioSortBy.value,
      ascending: RadioStationStore.radioSortAsc.value,
      options: [
        SortOptionSpec(
          key: 'default',
          label: context.l10n.sortRadioCardsDefault,
          icon: Icons.auto_awesome_rounded,
        ),
        SortOptionSpec(
          key: 'name',
          label: context.l10n.sortAZ,
          icon: Icons.sort_by_alpha_rounded,
        ),
        SortOptionSpec(
          key: 'recent',
          label: context.l10n.sortRadioCardsRecent,
          icon: Icons.history_rounded,
        ),
      ],
      onApply: (sortBy, ascending) async {
        await RadioStationStore.setRadioSort(
          sortBy: sortBy,
          ascending: ascending,
        );
      },
    );
  }

  Future<void> _showStationActions(RadioStation station) async {
    PulsrHaptics.heavyImpact();
    final langCode = Localizations.localeOf(context).languageCode;
    final displayStationName =
        RadioStationStore.localizedStationName(station, langCode);

    await PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (sheetContext) => _RadioStationActionsSheet(
        station: station,
        displayStationName: displayStationName,
        onEdit: () {
          Navigator.of(sheetContext).pop();
          _showAddDialog(initial: station);
        },
        onDelete: () {
          Navigator.of(sheetContext).pop();
          _confirmDelete(station);
        },
        onOpenSortSheet: () {
          Navigator.of(sheetContext).pop();
          _openSortFilterSheet();
        },
        onSelectSort: (sortBy, ascending) async {
          PulsrHaptics.selectionClick();
          await RadioStationStore.setRadioSort(
            sortBy: sortBy,
            ascending: ascending,
          );
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop();
          }
        },
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

  Widget _buildSearchField(PulsrPalette p, {required bool isCompact}) {
    return TextField(
      controller: _searchController,
      style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.bodySmall),
      decoration: InputDecoration(
        hintText: context.l10n.radioSearchHint,
        hintStyle:
            TextStyle(color: p.textTertiary, fontSize: AppFontSize.bodySmall),
        prefixIcon:
            Icon(Icons.search_rounded, color: p.textSecondary, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                icon:
                    Icon(Icons.close_rounded, color: p.textSecondary, size: 18),
                tooltip: context.l10n.clear,
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        filled: true,
        fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
        isDense: isCompact,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: isCompact ? AppSpacing.xxs : AppSpacing.xs,
        ),
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
    );
  }

  Widget _buildGenreStrip(
    PulsrPalette p,
    List<String> availableGenres, {
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
  }) {
    return SizedBox(
      height: AppSpacing.minTouchTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: availableGenres.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, idx) {
          final g = availableGenres[idx];
          final isSelected = _selectedGenre == g;
          final label = g == 'All' ? context.l10n.all : g;
          return Semantics(
            button: true,
            selected: isSelected,
            label: label,
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              selectedColor: p.accent.withValues(alpha: 0.2),
              checkmarkColor: p.accent,
              labelStyle: TextStyle(
                color: isSelected ? p.accent : p.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardsHiddenBanner(
    PulsrPalette p, {
    required bool isCompactLandscape,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: RadioStationStore.heroCardsVisible,
      builder: (context, visible, _) {
        if (visible) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md,
            isCompactLandscape ? AppSpacing.xxs : AppSpacing.xs,
            AppSpacing.md,
            isCompactLandscape ? AppSpacing.xxs : AppSpacing.xs,
          ),
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: isCompactLandscape ? AppSpacing.xs : AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: p.accentContainer.withValues(alpha: 0.35),
                borderRadius: AppRadii.r16All,
                border: Border.all(
                  color: p.accent.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.visibility_off_rounded,
                        color: p.accent,
                        size: 20,
                      ),
                    ),
                  ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.radioCardsHiddenFromHome,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: AppFontSize.callout,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.tapToRestoreRadioCards,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.caption,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton.tonal(
                  onPressed: () async {
                    await RadioStationStore.setHeroCardsVisible(true);
                    if (!context.mounted) return;
                    PulsrToast.show(
                      context,
                      message: context.l10n.radioCardsRestoredToast,
                      isSuccess: true,
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xxs,
                    ),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.r12All,
                    ),
                  ),
                    child: Text(
                      context.l10n.radioShowAction,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopControls(
    PulsrPalette p,
    List<String> availableGenres, {
    required bool useSingleRowHeader,
    required bool isCompactLandscape,
  }) {
    final hasGenres = availableGenres.length > 2;

    if (useSingleRowHeader && hasGenres) {
      return Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          isCompactLandscape ? AppSpacing.xs : AppSpacing.sm,
          0,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: _buildSearchField(p, isCompact: isCompactLandscape),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _buildGenreStrip(
                p,
                availableGenres,
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.md),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md,
            isCompactLandscape ? AppSpacing.xs : AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: _buildSearchField(p, isCompact: isCompactLandscape),
        ),
        if (hasGenres) ...[
          _buildGenreStrip(p, availableGenres),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }

  Widget _buildStationItem(
    BuildContext context, {
    required RadioStation station,
    required PlayerCubit playerCubit,
    required bool isCardMode,
    required bool isCompactLandscape,
  }) {
    final p = context.palette;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.currentSong?.path != curr.currentSong?.path ||
          prev.currentSong?.album != curr.currentSong?.album ||
          prev.isPlaying != curr.isPlaying,
      builder: (context, playerState) {
        final isCurrent = playerState.currentSong?.path == station.url;
        final isPlaying = isCurrent && playerState.isPlaying;
        final icyNowPlaying =
            isCurrent ? (playerState.currentSong?.album.trim() ?? '') : '';

        final langCode = Localizations.localeOf(context).languageCode;
        final isArabic = langCode == 'ar';
        final displayStationName =
            RadioStationStore.localizedStationName(station, langCode);
        final localizedStation = station.copyWith(name: displayStationName);

        final tile = ListTile(
          dense: isCompactLandscape,
          contentPadding: EdgeInsetsDirectional.fromSTEB(
            isCardMode ? AppSpacing.sm : AppSpacing.md,
            isCompactLandscape ? 0 : AppSpacing.xxs,
            isCardMode ? AppSpacing.xs : AppSpacing.sm,
            isCompactLandscape ? 0 : AppSpacing.xxs,
          ),
          leading: _StationArtwork(
            station: station,
            isPlaying: isPlaying,
          ),
          title: MarqueeText(
            text: displayStationName,
            textAlign: TextAlign.start,
            allowUserPause: false,
            showTooltip: false,
            velocity: 28.0,
            blankSpace: 36.0,
            style: TextStyle(
              color: isCurrent ? p.accent : p.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: AppFontSize.callout,
            ),
          ),
          subtitle: Row(
            children: [
              if (station.genre != null && station.genre!.isNotEmpty) ...[
                Container(
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: p.accentContainer.withValues(alpha: 0.35),
                    borderRadius: AppRadii.r6All,
                  ),
                  child: Text(
                    station.genre!,
                    style: TextStyle(
                      color: p.accent,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              Expanded(
                child: MarqueeText(
                  text: icyNowPlaying.isNotEmpty
                      ? '♫ $icyNowPlaying'
                      : _stationFallbackSubtitle(station, isArabic: isArabic),
                  textAlign: TextAlign.start,
                  allowUserPause: false,
                  showTooltip: false,
                  velocity: 24.0,
                  blankSpace: 32.0,
                  style: TextStyle(
                    color:
                        icyNowPlaying.isNotEmpty ? p.accent : p.textSecondary,
                    fontWeight: icyNowPlaying.isNotEmpty
                        ? FontWeight.w600
                        : FontWeight.normal,
                    fontSize: AppFontSize.label,
                  ),
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                tooltip: context.l10n.radioEdit,
                icon: Icon(
                  Icons.edit_rounded,
                  color: p.textSecondary,
                  size: 20,
                ),
                onPressed: () => _showAddDialog(initial: station),
              ),
              MergeSemantics(
                child: Semantics(
                  toggled: isPlaying,
                  child: IconButton(
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget,
                    ),
                    tooltip:
                        isPlaying ? context.l10n.pause : context.l10n.radioPlay,
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: p.accent,
                      size: 32,
                    ),
                    onPressed: () {
                      if (isCurrent) {
                        playerCubit.togglePlayPause();
                      } else {
                        playerCubit.playRadioStation(localizedStation);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          onTap: () {
            if (isCurrent) {
              playerCubit.togglePlayPause();
            } else {
              playerCubit.playRadioStation(localizedStation);
            }
          },
          onLongPress: () => _showStationActions(station),
        );

        final semanticTile = Semantics(
          container: true,
          selected: isCurrent,
          customSemanticsActions: {
            CustomSemanticsAction(label: context.l10n.radioEdit): () =>
                _showAddDialog(initial: station),
            CustomSemanticsAction(label: context.l10n.radioDelete): () =>
                _confirmDelete(station),
            CustomSemanticsAction(label: context.l10n.sortRadioCardsTitle):
                () => _showStationActions(station),
          },
          child: tile,
        );

        if (!isCardMode) return semanticTile;

        return Material(
          color: isCurrent
              ? p.accentContainer.withValues(alpha: 0.18)
              : p.surfaceContainer.withValues(alpha: 0.65),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.r14All,
            side: BorderSide(
              color: isCurrent ? p.accent.withValues(alpha: 0.45) : p.hairline,
              width: isCurrent ? 1.2 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Center(child: semanticTile),
        );
      },
    );
  }

  Widget _buildEmptyLibraryState(
    PulsrPalette p,
    BoxConstraints viewport, {
    required bool isCompactLandscape,
  }) {
    final avatarSize = isCompactLandscape ? 56.0 : 76.0;
    final iconSize = isCompactLandscape ? 28.0 : 38.0;

    return RefreshIndicator(
      onRefresh: _reload,
      color: p.accent,
      backgroundColor: p.surfaceContainer,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewport.maxHeight),
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: isCompactLandscape ? AppSpacing.md : AppSpacing.xl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          color: p.accentContainer.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: p.accent.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.radio_rounded,
                          size: iconSize,
                          color: p.accent,
                        ),
                      ),
                    ),
                    SizedBox(
                      height:
                          isCompactLandscape ? AppSpacing.sm : AppSpacing.s20,
                    ),
                    Semantics(
                      header: true,
                      child: Text(
                        context.l10n.radioEmptyTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.w700,
                        ),
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
                    SizedBox(
                      height:
                          isCompactLandscape ? AppSpacing.md : AppSpacing.lg,
                    ),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.s10,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _showAddDialog,
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: Text(
                            context.l10n.radioAddStation,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: p.accent,
                            foregroundColor: p.onAccent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: AppSpacing.sm,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r14All,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _importCurated,
                          icon: const Icon(Icons.explore_rounded, size: 18),
                          label: Text(context.l10n.radioCuratedBrowse),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: p.accent,
                            side: BorderSide(
                              color: p.accent.withValues(alpha: 0.5),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s20,
                              vertical: AppSpacing.sm,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r14All,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();
    final availableGenres = _availableGenres;
    final filtered = _filteredStations;

    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;
    final screenHeight = mq.size.height;
    final isLandscape = screenWidth > screenHeight;
    final isCompactLandscape = isLandscape && screenHeight < 520;

    final baseMaxWidth =
        PulsrLayoutMetrics.contentConstraints(context).maxWidth;
    final effectiveMaxWidth = screenWidth >= 600
        ? (baseMaxWidth < 1160 ? 1160.0 : baseMaxWidth)
        : baseMaxWidth;

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          toolbarHeight: isCompactLandscape ? 48 : kToolbarHeight,
          backgroundColor: p.surface,
          elevation: 0,
          leading: const PulsrBackButton(),
          title: Semantics(
            header: true,
            child: Text(context.l10n.radioTitle),
          ),
          actions: [
            ValueListenableBuilder<bool>(
              valueListenable: RadioStationStore.heroCardsVisible,
              builder: (context, visible, _) {
                if (visible) return const SizedBox.shrink();
                return IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  tooltip: context.l10n.radioShowCardsTooltip,
                  icon: Icon(Icons.visibility_rounded, color: p.accent),
                  onPressed: () async {
                    await RadioStationStore.setHeroCardsVisible(true);
                    if (!context.mounted) return;
                    PulsrToast.show(
                      context,
                      message: context.l10n.radioCardsRestoredToast,
                      isSuccess: true,
                    );
                  },
                );
              },
            ),
            ValueListenableBuilder<String>(
              valueListenable: RadioStationStore.radioSortBy,
              builder: (context, activeSort, _) {
                final isCustomSort = activeSort != 'default';
                return IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  tooltip: context.l10n.sortRadioCardsTitle,
                  icon: Icon(
                    Icons.sort_rounded,
                    color: isCustomSort ? p.accent : null,
                  ),
                  onPressed: _openSortFilterSheet,
                );
              },
            ),
            IconButton(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              tooltip: context.l10n.radioDirectoryBrowse,
              icon: const Icon(Icons.public_rounded),
              onPressed: () async {
                await RadioDirectorySheet.show(context, store: _store);
                _refresh();
              },
            ),
            IconButton(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              tooltip: context.l10n.radioCuratedBrowse,
              icon: const Icon(Icons.explore_rounded),
              onPressed: _importCurated,
            ),
            IconButton(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              tooltip: context.l10n.radioImportPlaylist,
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: _showImportDialog,
            ),
            IconButton(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              tooltip: context.l10n.radioAddStation,
              icon: const Icon(Icons.add_rounded),
              onPressed: _showAddDialog,
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
            child: LayoutBuilder(
              builder: (context, viewport) {
                if (_loading) {
                  return Center(
                    child: Semantics(
                      liveRegion: true,
                      label: context.l10n.pageLoadingProgress,
                      child: const CircularProgressIndicator(),
                    ),
                  );
                }

                if (_loadFailed && _stations.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: viewport.maxHeight),
                        child: Center(
                          child: PulsrEmptyState(
                            icon: Icons.error_outline_rounded,
                            title: context.l10n.somethingWentWrong,
                            subtitle: context.l10n.radioEmptySubtitle,
                            primaryActionLabel: context.l10n.retry,
                            onPrimaryAction: _reload,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                if (_stations.isEmpty) {
                  return _buildEmptyLibraryState(
                    p,
                    viewport,
                    isCompactLandscape: isCompactLandscape,
                  );
                }

                final width = viewport.maxWidth;
                final crossAxisCount = width >= 960
                    ? 3
                    : width >= 600
                        ? 2
                        : 1;
                final useSingleRowHeader = isCompactLandscape || width >= 680;
                final bottomPadding = PulsrLayoutMetrics.scrollBottom(context);

                return Column(
                  children: [
                    _buildCardsHiddenBanner(
                      p,
                      isCompactLandscape: isCompactLandscape,
                    ),
                    _buildTopControls(
                      p,
                      availableGenres,
                      useSingleRowHeader: useSingleRowHeader,
                      isCompactLandscape: isCompactLandscape,
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? LayoutBuilder(
                              builder: (context, emptyConstraints) {
                                return RefreshIndicator(
                                  onRefresh: () async => _refresh(),
                                  color: p.accent,
                                  backgroundColor: p.surfaceContainer,
                                  child: SingleChildScrollView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: emptyConstraints.maxHeight,
                                      ),
                                      child: Center(
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
                                  ),
                                );
                              },
                            )
                          : RefreshIndicator(
                              onRefresh: () async => _refresh(),
                              color: p.accent,
                              backgroundColor: p.surfaceContainer,
                              child: crossAxisCount == 1
                                  ? ListView.separated(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: EdgeInsets.only(
                                        top: AppSpacing.xs,
                                        bottom: bottomPadding,
                                      ),
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
                                          child: _buildStationItem(
                                            context,
                                            station: station,
                                            playerCubit: playerCubit,
                                            isCardMode: false,
                                            isCompactLandscape:
                                                isCompactLandscape,
                                          ),
                                        );
                                      },
                                    )
                                  : GridView.builder(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: EdgeInsetsDirectional.fromSTEB(
                                        AppSpacing.md,
                                        AppSpacing.xs,
                                        AppSpacing.md,
                                        bottomPadding,
                                      ),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        mainAxisExtent:
                                            isCompactLandscape ? 68 : 76,
                                        crossAxisSpacing: AppSpacing.sm,
                                        mainAxisSpacing: AppSpacing.sm,
                                      ),
                                      itemCount: filtered.length,
                                      itemBuilder: (context, index) {
                                        final station = filtered[index];
                                        return StaggeredReveal(
                                          index: index,
                                          groupKey: filtered.length,
                                          child: _buildStationItem(
                                            context,
                                            station: station,
                                            playerCubit: playerCubit,
                                            isCardMode: true,
                                            isCompactLandscape:
                                                isCompactLandscape,
                                          ),
                                        );
                                      },
                                    ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}


class _RadioStationActionsSheet extends StatelessWidget {
  final RadioStation station;
  final String displayStationName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onOpenSortSheet;
  final void Function(String sortBy, bool ascending) onSelectSort;

  const _RadioStationActionsSheet({
    required this.station,
    required this.displayStationName,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenSortSheet,
    required this.onSelectSort,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: ValueListenableBuilder<String>(
            valueListenable: RadioStationStore.radioSortBy,
            builder: (context, activeSort, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: RadioStationStore.radioSortAsc,
                builder: (context, activeAsc, _) {
                  final isCustomSort = activeSort != 'default' || !activeAsc;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          _StationArtwork(station: station, isPlaying: false),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    displayStationName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: p.textPrimary,
                                      fontSize: AppFontSize.title,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  station.genre != null &&
                                          station.genre!.isNotEmpty
                                      ? station.genre!
                                      : station.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.caption,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Divider(color: p.hairline, height: 1),
                      const SizedBox(height: AppSpacing.xs),

                      // Edit tile
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.r12All,
                        ),
                        leading: const Icon(Icons.edit_rounded),
                        title: Text(context.l10n.radioEdit),
                        onTap: onEdit,
                      ),

                      // Delete tile
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.r12All,
                        ),
                        leading: const Icon(Icons.delete_outline_rounded),
                        title: Text(context.l10n.radioDelete),
                        onTap: onDelete,
                      ),

                      const SizedBox(height: AppSpacing.xs),
                      Divider(color: p.hairline, height: 1),
                      const SizedBox(height: AppSpacing.sm),

                      // Sort section header
                      Row(
                        children: [
                          ExcludeSemantics(
                            child: Icon(Icons.sort_rounded,
                                size: 16, color: p.accent),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Semantics(
                            header: true,
                            child: Text(
                              context.l10n.sortRadioCardsTitle,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (isCustomSort)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                              ),
                              onPressed: () {
                                onSelectSort('default', true);
                                PulsrToast.show(
                                  context,
                                  message:
                                      context.l10n.radioCardOrderResetToast,
                                  isSuccess: true,
                                );
                              },
                              icon: Icon(
                                Icons.restart_alt_rounded,
                                size: 15,
                                color: p.accent,
                              ),
                              label: Text(
                                context.l10n.resetRadioCardOrder,
                                style: TextStyle(
                                  color: p.accent,
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),

                      // Row of sort chips: Default, A-Z (or Z-A), Recent
                      Row(
                        children: [
                          _RadioSortOptionChip(
                            icon: Icons.auto_awesome_rounded,
                            label: context.l10n.sortRadioCardsDefault,
                            selected: activeSort == 'default' && activeAsc,
                            onTap: () => onSelectSort('default', true),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _RadioSortOptionChip(
                            icon: Icons.sort_by_alpha_rounded,
                            label: (activeSort == 'name' && !activeAsc)
                                ? 'Z–A'
                                : context.l10n.sortRadioCardsAlphabetical,
                            selected: activeSort == 'name',
                            onTap: () {
                              final nextAsc =
                                  activeSort == 'name' ? !activeAsc : true;
                              onSelectSort('name', nextAsc);
                            },
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _RadioSortOptionChip(
                            icon: Icons.history_rounded,
                            label: context.l10n.sortRadioCardsRecent,
                            selected: activeSort == 'recent' ||
                                activeSort == 'lastPlayed',
                            onTap: () => onSelectSort('recent', false),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RadioSortOptionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RadioSortOptionChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadii.r12All,
          child: InkWell(
            borderRadius: AppRadii.r12All,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSpacing.minTouchTarget,
              ),
              child: AnimatedContainer(
                duration: context.motion(PulsrMotion.layout),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? p.accent.withValues(alpha: 0.16)
                      : p.surfaceContainerHigh.withValues(alpha: 0.55),
                  borderRadius: AppRadii.r12All,
                  border: Border.all(
                    color: selected
                        ? p.accent.withValues(alpha: 0.60)
                        : p.hairline.withValues(alpha: 0.7),
                    width: selected ? 1.2 : 0.8,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        icon,
                        size: 18,
                        color: selected ? p.accent : p.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? p.accent : p.textPrimary,
                        fontSize: AppFontSize.caption,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
