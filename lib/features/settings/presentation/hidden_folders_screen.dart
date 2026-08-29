import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../domain/usecases/folder_usecases.dart';
import '../../library/cubit/library_cubit.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

class HiddenFoldersScreen extends StatefulWidget {
  const HiddenFoldersScreen({super.key});

  @override
  State<HiddenFoldersScreen> createState() => _HiddenFoldersScreenState();
}

class _HiddenFoldersScreenState extends State<HiddenFoldersScreen> {
  final FolderUseCases _folderUseCases = getIt<FolderUseCases>();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customPathController = TextEditingController();

  List<FolderItem> _folders = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customPathController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);
    final result = await _folderUseCases.getFolderHierarchy();
    result.fold(
      (l) => setState(() => _isLoading = false),
      (folders) => setState(() {
        _folders = folders;
        _isLoading = false;
      }),
    );
  }

  Future<void> _toggleFolder(String path) async {
    await _folderUseCases.toggleExcludeFolder(path);
    await _loadFolders();
    if (mounted) {
      unawaited(context.read<LibraryCubit>().loadFolders());
    }
  }

  Future<void> _showAddCustomFolderDialog(
      BuildContext context, PulsrPalette p) async {
    _customPathController.clear();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.hairline),
        ),
        title: Text(
          context.l10n.hideCustomFolder,
          style: TextStyle(
              color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.hideFolderDesc,
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _customPathController,
              autofocus: true,
              style: TextStyle(color: p.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: '/storage/emulated/0/Recordings',
                hintStyle: TextStyle(color: p.textTertiary, fontSize: 12),
                filled: true,
                fillColor: p.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel,
                style: TextStyle(color: p.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final path = _customPathController.text.trim();
              if (path.isNotEmpty) {
                Navigator.pop(ctx);
                await _toggleFolder(path);
              }
            },
            child: Text(context.l10n.hideFolder),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final filteredFolders = _folders.where((f) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return f.name.toLowerCase().contains(q) ||
          f.path.toLowerCase().contains(q);
    }).toList();

    final hiddenCount = _folders.where((f) => f.isExcluded).length;

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();

        return Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.hiddenFolders),
            actions: [
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined),
                tooltip: 'Add Custom Folder',
                onPressed: () => _showAddCustomFolderDialog(context, p),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                icon: state.isScanning
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: p.onAccent),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(
                  state.isScanning
                      ? 'Rescanning library…'
                      : 'Apply & Rescan Library',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                onPressed: state.isScanning
                    ? null
                    : () async {
                        final count = await cubit.rescanLibrary();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Library updated! $count tracks loaded.')),
                          );
                        }
                      },
              ),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: EdgeInsets.only(
                  bottom: 40,
                  top: 8,
                  left: Adaptive.pagePadding(context),
                  right: Adaptive.pagePadding(context),
                ),
                children: [
                  // 1. Auto-Filter System Media & Messengers Card
                  Material(
                    color: p.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: p.hairline),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          value: state.autoHideSystemMedia,
                          activeTrackColor: p.accent,
                          activeThumbColor: Colors.white,
                          onChanged: (val) async {
                            await cubit.setAutoHideSystemMedia(val);
                            await cubit.rescanLibrary();
                          },
                          secondary: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: p.accentContainer,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(Icons.mic_off_rounded,
                                color: p.accent, size: 19),
                          ),
                          title: const Text(
                            'Auto-Filter Voice Notes & Messengers',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          subtitle: Text(
                            'Automatically ignores WhatsApp audio, voice notes, Telegram, Call Recordings, and sound recorder files.',
                            style:
                                TextStyle(color: p.textSecondary, fontSize: 12),
                          ),
                        ),
                        Divider(height: 1, indent: 68, color: p.hairline),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: p.accentContainer,
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: Icon(Icons.timer_outlined,
                                            color: p.accent, size: 19),
                                      ),
                                      const SizedBox(width: 14),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Short Audio Filter',
                                            style: TextStyle(
                                              color: p.textPrimary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            'Ignore short clips and sound effects',
                                            style: TextStyle(
                                                color: p.textSecondary,
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: p.accentContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      state.minDurationSec > 0
                                          ? '${state.minDurationSec}s'
                                          : 'Off',
                                      style: TextStyle(
                                        color: p.accent,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Slider(
                                value: state.minDurationSec.toDouble(),
                                min: 0,
                                max: 90,
                                divisions: 18,
                                activeColor: p.accent,
                                onChanged: (val) =>
                                    cubit.setMinDuration(val.toInt()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 2. Search & Overview Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          'DEVICE AUDIO DIRECTORIES',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: p.textTertiary),
                        ),
                      ),
                      if (hiddenCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: p.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: p.error.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '$hiddenCount Hidden',
                            style: TextStyle(
                                color: p.error,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Search Bar
                  Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.hairline),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: TextStyle(fontSize: 13, color: p.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search directories by name or path...',
                        hintStyle:
                            TextStyle(fontSize: 12, color: p.textTertiary),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: p.textTertiary, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear_rounded,
                                    color: p.textTertiary, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Folders List
                  if (_isLoading)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                          child: CircularProgressIndicator(color: p.accent)),
                    )
                  else if (filteredFolders.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No directories match "$_searchQuery"'
                              : 'No audio folders discovered yet. Scan storage to populate.',
                          style: TextStyle(color: p.textTertiary, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ...filteredFolders.map((folder) {
                      final isHidden = folder.isExcluded;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: isHidden
                              ? p.error.withValues(alpha: 0.08)
                              : p.surfaceContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isHidden
                                  ? p.error.withValues(alpha: 0.35)
                                  : p.hairline,
                              width: isHidden ? 1.2 : 1.0,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isHidden
                                    ? p.error.withValues(alpha: 0.15)
                                    : p.accentContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isHidden
                                    ? Icons.folder_off_rounded
                                    : Icons.folder_rounded,
                                color: isHidden ? p.error : p.accent,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              folder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color:
                                    isHidden ? p.textSecondary : p.textPrimary,
                                decoration: isHidden
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${folder.songCount} tracks • ${folder.path}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isHidden
                                      ? p.textTertiary
                                      : p.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            trailing: TextButton.icon(
                              style: TextButton.styleFrom(
                                backgroundColor: isHidden
                                    ? p.surfaceContainerHigh
                                    : p.error.withValues(alpha: 0.12),
                                foregroundColor:
                                    isHidden ? p.textPrimary : p.error,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: Icon(
                                isHidden
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                                size: 15,
                              ),
                              label: Text(
                                isHidden ? 'Unhide' : 'Hide',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5),
                              ),
                              onPressed: () => _toggleFolder(folder.path),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
