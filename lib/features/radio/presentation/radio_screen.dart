// lib/features/radio/presentation/radio_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/radio_station_store.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_back_button.dart';
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
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    String? error;

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(context.l10n.radioAddStation),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                textInputAction: TextInputAction.next,
                decoration:
                    InputDecoration(labelText: context.l10n.radioStationName),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: context.l10n.radioStationUrl,
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.radioCancel),
            ),
            ElevatedButton(
              onPressed: () {
                final url = urlController.text.trim();
                if (!RadioStation.isHttpUrl(url)) {
                  setDialogState(() => error = context.l10n.radioInvalidUrl);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(context.l10n.radioAdd),
            ),
          ],
        ),
      ),
    );

    if (added == true && mounted) {
      await _store.add(RadioStation.create(
        name: nameController.text,
        url: urlController.text,
      ));
      _refresh();
    }
    nameController.dispose();
    urlController.dispose();
  }

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.radioImportTitle),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: context.l10n.radioImportHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.radioCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(context.l10n.radioImport),
          ),
        ],
      ),
    );
    controller.dispose();
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

  Future<void> _confirmDelete(RadioStation station) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.radioDeleteTitle),
        content: Text(context.l10n.radioDeleteMessage(station.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.radioCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.radioDelete),
          ),
        ],
      ),
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
                    Icon(Icons.radio_rounded,
                        size: 56, color: p.textTertiary),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.radioEmptyTitle,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.radioEmptySubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _stations.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: p.hairline,
              ),
              itemBuilder: (context, index) {
                final station = _stations[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: p.accentContainer,
                    child: Icon(Icons.radio_rounded,
                        color: p.accent, size: 20),
                  ),
                  title: Text(
                    station.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    station.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textSecondary, fontSize: 12),
                  ),
                  trailing: IconButton(
                    tooltip: context.l10n.radioPlay,
                    icon: Icon(Icons.play_arrow_rounded, color: p.accent),
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
