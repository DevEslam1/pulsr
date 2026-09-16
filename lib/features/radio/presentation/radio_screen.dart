// lib/features/radio/presentation/radio_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/radio_station_store.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../domain/models/radio_station.dart';
import '../../player/cubit/player_cubit.dart';

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final RadioStationStore _store = RadioStationStore();
  List<RadioStation> _stations = const [];

  @override
  void initState() {
    super.initState();
    _store.ready.then((_) {
      if (mounted) setState(() => _stations = _store.list);
    });
  }

  void _refresh() {
    if (mounted) setState(() => _stations = _store.list);
  }

  String _nameForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    return url;
  }

  Future<void> _showAddDialog() async {
    final station = await PulsrDialogHelper.showCustomDialog<RadioStation>(
      context,
      builder: (_) => const _AddStationDialog(),
    );

    if (station != null && mounted) {
      await _store.add(station);
      _refresh();
    }
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
                padding: const EdgeInsets.all(32),
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
                    const SizedBox(height: 20),
                    Text(
                      context.l10n.radioEmptyTitle,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.radioEmptySubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
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
                            horizontal: 22, vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _importCurated,
                      icon: const Icon(Icons.explore_rounded, size: 18),
                      label: Text(context.l10n.radioCuratedBrowse),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.accent,
                        side: BorderSide(
                            color: p.accent.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(top: 8, bottom: 120),
              itemCount: _stations.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 72,
                endIndent: 16,
                color: p.hairline,
              ),
              itemBuilder: (context, index) {
                final station = _stations[index];
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: p.accentContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.radio_rounded,
                        color: p.accent, size: 22),
                  ),
                  title: Text(
                    station.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    station.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textSecondary, fontSize: 12),
                  ),
                  trailing: IconButton(
                    tooltip: context.l10n.radioPlay,
                    icon: Icon(Icons.play_circle_fill_rounded,
                        color: p.accent, size: 30),
                    onPressed: () => playerCubit.playRadioStation(station),
                  ),
                  onTap: () => playerCubit.playRadioStation(station),
                  onLongPress: () => _confirmDelete(station),
                );
              },
            ),
    );
  }
}

class _AddStationDialog extends StatefulWidget {
  const _AddStationDialog();

  @override
  State<_AddStationDialog> createState() => _AddStationDialogState();
}

class _AddStationDialogState extends State<_AddStationDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _urlController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _urlController.text.trim();
    if (!RadioStation.isHttpUrl(url)) {
      setState(() {
        _urlError = context.l10n.radioInvalidUrl;
      });
      return;
    }
    final name = _nameController.text.trim();
    Navigator.of(context, rootNavigator: true).pop(
      RadioStation.create(
        name: name,
        url: url,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulsrDialog(
      icon: Icon(Icons.radio_rounded, color: p.accent, size: 28),
      title: Text(context.l10n.radioAddStation),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              style: TextStyle(color: p.textPrimary, fontSize: 14.5),
              decoration: InputDecoration(
                labelText: context.l10n.radioStationName,
                labelStyle: TextStyle(color: p.textSecondary),
                hintText: context.l10n.browseRadioNameHint,
                hintStyle: TextStyle(color: p.textTertiary),
                filled: true,
                fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.accent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: TextStyle(color: p.textPrimary, fontSize: 14.5),
              decoration: InputDecoration(
                labelText: context.l10n.radioStationUrl,
                labelStyle: TextStyle(color: p.textSecondary),
                hintText: 'https://...',
                hintStyle: TextStyle(color: p.textTertiary),
                errorText: _urlError,
                filled: true,
                fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            context.l10n.radioAdd,
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
          style: TextStyle(color: p.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: context.l10n.radioImportHint,
            hintStyle: TextStyle(color: p.textTertiary, fontSize: 13),
            filled: true,
            fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: p.hairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: p.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
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

