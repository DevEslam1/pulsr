// lib/features/radio/presentation/radio_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/radio_station_store.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../domain/models/radio_station.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/cubit/player_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import '../../../core/widgets/staggered_reveal.dart';

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final RadioStationStore _store = RadioStationStore();
  final TextEditingController _searchController = TextEditingController();
  List<RadioStation> _stations = const [];
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
      if (mounted) setState(() => _stations = _store.list);
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

  List<String> get _availableGenres {
    final set = <String>{};
    for (final s in _stations) {
      final g = s.genre?.trim();
      if (g != null && g.isNotEmpty) {
        set.add(g);
      }
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  List<RadioStation> get _filteredStations {
    return _stations.where((s) {
      if (_selectedGenre != 'All') {
        if (s.genre?.toLowerCase() != _selectedGenre.toLowerCase()) {
          return false;
        }
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesName = s.name.toLowerCase().contains(query);
        final matchesGenre = s.genre?.toLowerCase().contains(query) ?? false;
        final matchesUrl = s.url.toLowerCase().contains(query);
        if (!matchesName && !matchesGenre && !matchesUrl) return false;
      }
      return true;
    }).toList();
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

    if (station != null && mounted) {
      // A changed stream URL produces a new derived id; drop the old entry so
      // edit replaces rather than duplicates.
      if (initial != null && initial.url != station.url) {
        await _store.remove(initial.id);
      }
      await _store.add(station);
      _refresh();
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.radioNoStreamsFound)),
      );
      return;
    }
    for (final url in urls) {
      await _store.add(
          RadioStation.create(name: _nameForUrl(url), url: url));
    }
    _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.radioImportedCount(urls.length))),
      );
    }
  }

  Future<void> _importCurated() async {
    final added = await _store.importCurated();
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added > 0
            ? context.l10n.radioCuratedAdded(added)
            : context.l10n.radioCuratedUpToDate),
      ),
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

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.surface,
        elevation: 0,
        leading: const PulsrBackButton(),
        title: Text(context.l10n.radioTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.radioCuratedBrowse,
            icon: const Icon(Icons.explore_rounded),
            onPressed: _importCurated,
          ),
          IconButton(
            tooltip: context.l10n.radioImportPlaylist,
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: _showImportDialog,
          ),
          IconButton(
            tooltip: context.l10n.radioAddStation,
            icon: const Icon(Icons.add_rounded),
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: _stations.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: p.accentContainer.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: p.accent.withValues(alpha: 0.25),
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
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: Text(
                        context.l10n.radioAddStation,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: AppSpacing.sm),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.r14),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s10),
                    OutlinedButton.icon(
                      onPressed: _importCurated,
                      icon: const Icon(Icons.explore_rounded, size: 18),
                      label: Text(context.l10n.radioCuratedBrowse),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.accent,
                        side: BorderSide(
                            color: p.accent.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s20, vertical: AppSpacing.sm),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.r14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.bodySmall),
                    decoration: InputDecoration(
                      hintText: 'Search station, genre, or URL…',
                      hintStyle: TextStyle(color: p.textTertiary, fontSize: AppFontSize.bodySmall),
                      prefixIcon: Icon(Icons.search_rounded, color: p.textSecondary, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close_rounded, color: p.textSecondary, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.r12),
                        borderSide: BorderSide(color: p.hairline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.r12),
                        borderSide: BorderSide(color: p.hairline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.r12),
                        borderSide: BorderSide(color: p.accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
                if (availableGenres.length > 2)
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      itemCount: availableGenres.length,
                      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                      itemBuilder: (context, idx) {
                        final g = availableGenres[idx];
                        final isSelected = _selectedGenre == g;
                        return FilterChip(
                          label: Text(g),
                          selected: isSelected,
                          selectedColor: p.accent.withValues(alpha: 0.2),
                          checkmarkColor: p.accent,
                          labelStyle: TextStyle(
                            color: isSelected ? p.accent : p.textSecondary,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            fontSize: AppFontSize.caption,
                          ),
                          side: BorderSide(
                            color: isSelected ? p.accent.withValues(alpha: 0.4) : p.hairline,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r12),
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
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 48, color: p.textTertiary),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'No stations match "$_searchQuery"',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.body,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.scrollBottom),
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
                              child: BlocBuilder<PlayerCubit, PlayerState>(
                                buildWhen: (prev, curr) =>
                                    prev.currentSong?.path != curr.currentSong?.path ||
                                    prev.isPlaying != curr.isPlaying,
                                builder: (context, playerState) {
                                  final isCurrent = playerState.currentSong?.path == station.url;
                                  final isPlaying = isCurrent && playerState.isPlaying;

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
                                    leading: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: isPlaying
                                            ? p.accent.withValues(alpha: 0.2)
                                            : p.accentContainer.withValues(alpha: 0.35),
                                        borderRadius: BorderRadius.circular(AppRadii.r12),
                                        border: isPlaying
                                            ? Border.all(color: p.accent, width: 1.5)
                                            : null,
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        isPlaying ? Icons.graphic_eq_rounded : Icons.radio_rounded,
                                        color: p.accent,
                                        size: 22,
                                      ),
                                    ),
                                    title: Text(
                                      station.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
                                                horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: p.accentContainer.withValues(alpha: 0.35),
                                              borderRadius: BorderRadius.circular(AppRadii.r6),
                                            ),
                                            child: Text(
                                              station.genre!,
                                              style: TextStyle(
                                                color: p.accent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                        Expanded(
                                          child: Text(
                                            station.url,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: p.textSecondary,
                                                fontSize: AppFontSize.label),
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: context.l10n.radioEdit,
                                          icon: Icon(Icons.edit_rounded,
                                              color: p.textSecondary, size: 22),
                                          onPressed: () => _showAddDialog(initial: station),
                                        ),
                                        IconButton(
                                          tooltip: isPlaying ? 'Pause' : context.l10n.radioPlay,
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
                                              playerCubit.playRadioStation(station);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      if (isCurrent) {
                                        playerCubit.togglePlayPause();
                                      } else {
                                        playerCubit.playRadioStation(station);
                                      }
                                    },
                                    onLongPress: () => _showStationActions(station),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
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

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _urlController = TextEditingController(text: widget.initial?.url ?? '');
    _genreController = TextEditingController(text: widget.initial?.genre ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _genreController.dispose();
    super.dispose();
  }

  /// Returns a user-facing reason the URL is invalid, or null when valid.
  String? _validateUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return 'Please enter a URL';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'URL must start with http:// or https://';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return 'Invalid URL format';
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
    Navigator.of(context, rootNavigator: true).pop(
      RadioStation.create(
        name: name,
        url: url,
        genre: genre.isNotEmpty ? genre : null,
        artworkUrl: widget.initial?.artworkUrl,
        lastPlayed: widget.initial?.lastPlayed,
      ),
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
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
              decoration: InputDecoration(
                labelText: context.l10n.radioStationName,
                labelStyle: TextStyle(color: p.textSecondary),
                hintText: context.l10n.browseRadioNameHint,
                hintStyle: TextStyle(color: p.textTertiary),
                filled: true,
                fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.r12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.r12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.r12),
                  borderSide: BorderSide(color: p.accent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s14),
            TextField(
              controller: _genreController,
              textInputAction: TextInputAction.next,
              style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
              decoration: InputDecoration(
                labelText: 'Genre / Category (Optional)',
                labelStyle: TextStyle(color: p.textSecondary),
                hintText: 'e.g. Chill, Classical, Jazz, Quran...',
                hintStyle: TextStyle(color: p.textTertiary),
                filled: true,
                fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.r12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.r12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.r12),
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
              style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
              decoration: InputDecoration(
                labelText: context.l10n.radioStationUrl,
                labelStyle: TextStyle(color: p.textSecondary),
                hintText: 'https://...',
                hintStyle: TextStyle(color: p.textTertiary),
                errorText: _urlError,
                filled: true,
                fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.r12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.r12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.r12),
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20, vertical: AppSpacing.sm),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.r12),
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
          style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.bodySmall),
          decoration: InputDecoration(
            hintText: context.l10n.radioImportHint,
            hintStyle: TextStyle(color: p.textTertiary, fontSize: AppFontSize.bodySmall),
            filled: true,
            fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.r12),
              borderSide: BorderSide(color: p.hairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.r12),
              borderSide: BorderSide(color: p.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.r12),
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
          onPressed: () => Navigator.of(context, rootNavigator: true)
              .pop(_controller.text),
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20, vertical: AppSpacing.sm),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.r12),
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

