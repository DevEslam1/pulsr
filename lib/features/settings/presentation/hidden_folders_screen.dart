import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_slider.dart';
import '../../../domain/usecases/folder_usecases.dart';
import '../../library/cubit/library_cubit.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
  Timer? _searchDebounce;
  int _minFileSizeKb = 0;

  @override
  void initState() {
    super.initState();
    _loadFolders();
    _loadMinFileSize();
  }

  Future<void> _loadMinFileSize() async {
    try {
      final kb = await context.read<SettingsCubit>().getMinFileSizeKb();
      if (mounted) setState(() => _minFileSizeKb = kb);
    } catch (e, st) {
      ErrorLogger.log('Failed to load min file size filter',
          error: e, stackTrace: st, category: 'HiddenFoldersScreen');
      if (mounted) setState(() => _minFileSizeKb = 0);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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
      context.read<LibraryCubit>().loadFolders();
    }
  }

  Future<void> _showAddCustomFolderDialog(
      BuildContext context, PulsrPalette p) async {
    final path = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.hideCustomFolder,
      message: context.l10n.hideFolderDesc,
      hintText: '/storage/emulated/0/Recordings',
      icon: Icons.folder_off_rounded,
      confirmLabel: context.l10n.hideFolder,
      cancelLabel: context.l10n.cancel,
    );
    if (path != null && path.isNotEmpty) {
      await _toggleFolder(path);
    }
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

        return PulsrPagePopScope(
          child: Scaffold(
            appBar: AppBar(
              leading: const PulsrBackButton(),
              title: Text(context.l10n.hiddenFolders),
            actions: [
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined),
                tooltip: context.l10n.settingsAddCustomFolder,
                onPressed: () => _showAddCustomFolderDialog(context, p),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r16)),
                ),
                icon: state.isScanning
                    ? SizedBox(width: AppSpacing.s18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: p.onAccent),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(
                  state.isScanning
                      ? context.l10n.settingsRescanningLibrary
                      : context.l10n.settingsApplyRescanLibrary,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: AppFontSize.body),
                ),
                onPressed: state.isScanning
                    ? null
                    : () async {
                        final count = await cubit.rescanLibrary();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    context.l10n.settingsLibraryUpdated(count))),
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
                padding: EdgeInsetsDirectional.only(
                  bottom: 40,
                  top: 8,
                  start: Adaptive.pagePadding(context),
                  end: Adaptive.pagePadding(context),
                ),
                children: [
                  // 1. Auto-Filter System Media & Messengers Card
                  Material(
                    color: p.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r20),
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
                              borderRadius: BorderRadius.circular(AppRadii.r12),
                            ),
                            child: Icon(Icons.mic_off_rounded,
                                color: p.accent, size: 20),
                          ),
                          title: Text(context.l10n.autoFilterVoiceNotes,
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: AppFontSize.body),
                          ),
                          subtitle: Text(context.l10n.autoFilterVoiceNotesDesc,
                            style:
                                TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
                          ),
                        ),
                        Divider(height: 1, indent: 68, color: p.hairline),
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.s14),
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
                                              BorderRadius.circular(AppRadii.r12),
                                        ),
                                        child: Icon(Icons.timer_outlined,
                                            color: p.accent, size: 20),
                                      ),
                                      const SizedBox(width: AppSpacing.s14),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(context.l10n.shortAudioFilter,
                                            style: TextStyle(
                                              color: p.textPrimary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: AppFontSize.body,
                                            ),
                                          ),
                                          Text(context.l10n.shortAudioFilterDesc,
                                            style: TextStyle(
                                                color: p.textSecondary,
                                                fontSize: AppFontSize.label),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(

                                        horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                                    decoration: BoxDecoration(
                                      color: p.accentContainer,
                                      borderRadius: BorderRadius.circular(AppRadii.r8),
                                    ),
                                    child: Text(
                                      state.minDurationSec > 0
                                          ? '${state.minDurationSec}s'
                                          : context.l10n.rgOff,
                                      style: TextStyle(
                                        color: p.accent,
                                        fontWeight: FontWeight.w800,
                                        fontSize: AppFontSize.label,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xxs),
                                  IconButton(
                                    icon: Icon(Icons.settings_backup_restore,
                                        size: 18,
                                        color: state.minDurationSec == 30
                                            ? p.textTertiary.withValues(alpha: 0.4)
                                            : p.accent),
                                    tooltip: context.l10n.resetToDefault30s,
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 28, minHeight: 28),
                                    onPressed: state.minDurationSec == 30
                                        ? null
                                        : () => cubit.setMinDuration(30),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              PulsrSlider(
                                value: state.minDurationSec.toDouble(),
                                min: 0,
                                max: 90,
                                divisions: 18,
                                semanticLabel: context.l10n.shortAudioFilter,
                                onChanged: (val) =>
                                    cubit.setMinDuration(val.toInt()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Minimum File Size Filter Card
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppRadii.r20),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: p.accentContainer,
                                    borderRadius: BorderRadius.circular(AppRadii.r12),
                                  ),
                                  child: Icon(Icons.sd_storage_outlined,
                                      color: p.accent, size: 20),
                                ),
                                const SizedBox(width: AppSpacing.s14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(context.l10n.minFileSize,
                                      style: TextStyle(
                                        color: p.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: AppFontSize.body,
                                      ),
                                    ),
                                    Text(context.l10n.minFileSizeDesc,
                                      style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: AppFontSize.label),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(

                                  horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                              decoration: BoxDecoration(
                                color: p.accentContainer,
                                borderRadius: BorderRadius.circular(AppRadii.r8),
                              ),
                              child: Text(
                                _minFileSizeKb > 0
                                    ? (_minFileSizeKb >= 1024
                                        ? '${(_minFileSizeKb / 1024).toStringAsFixed(0)}MB'
                                        : '${_minFileSizeKb}KB')
                                    : context.l10n.rgOff,
                                style: TextStyle(
                                  color: p.accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: AppFontSize.label,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [0, 50, 100, 200, 500, 1024].map((kb) {
                            final isSelected = _minFileSizeKb == kb;
                            final label = kb == 0
                                ? context.l10n.rgOff
                                : kb >= 1024
                                    ? '1 MB'
                                    : '$kb KB';
                            return ChoiceChip(
                              label: Text(label),
                              selected: isSelected,
                              onSelected: (_) async {
                                setState(() => _minFileSizeKb = kb);
                                await cubit.setMinFileSizeKb(kb);
                              },
                              selectedColor: p.accent,
                              labelStyle: TextStyle(
                                color: isSelected ? p.onAccent : p.textPrimary,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                                fontSize: AppFontSize.label,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s20),

                  // 2. Search & Overview Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: AppSpacing.s6),
                        child: Text(context.l10n.deviceAudioDirectories,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: p.textTertiary),
                        ),
                      ),
                      if (hiddenCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(

                              horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
                          decoration: BoxDecoration(
                            color: p.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadii.r8),
                            border: Border.all(
                                color: p.error.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            context.l10n.settingsHiddenCount(hiddenCount),
                            style: TextStyle(
                                color: p.error,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  // Search Bar
                  Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppRadii.r14),
                      border: Border.all(color: p.hairline),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        _searchDebounce?.cancel();
                        _searchDebounce =
                            Timer(const Duration(milliseconds: 250), () {
                          if (mounted) setState(() => _searchQuery = val);
                        });
                      },
                      style: TextStyle(fontSize: AppFontSize.bodySmall, color: p.textPrimary),
                      decoration: InputDecoration(
                        hintText: context.l10n.settingsSearchDirectoriesHint,
                        hintStyle:
                            TextStyle(fontSize: AppFontSize.label, color: p.textTertiary),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: p.textTertiary, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                tooltip: context.l10n.clear,
                                icon: Icon(Icons.clear_rounded,
                                    color: p.textTertiary, size: 16),
                                onPressed: () {
                                  _searchDebounce?.cancel();
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Folders List
                  if (_isLoading)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.s40),
                      child: Center(
                          child: CircularProgressIndicator(color: p.accent)),
                    )
                  else if (filteredFolders.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadii.r20),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? context.l10n.settingsNoDirectoriesMatch(_searchQuery)
                              : context.l10n.settingsNoAudioFolders,
                          style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.bodySmall),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ...filteredFolders.map((folder) {
                      final isHidden = folder.isExcluded;

                      return Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Material(
                          color: isHidden
                              ? p.error.withValues(alpha: 0.08)
                              : p.surfaceContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r16),
                            side: BorderSide(
                              color: isHidden
                                  ? p.error.withValues(alpha: 0.35)
                                  : p.hairline,
                              width: isHidden ? 1.2 : 1.0,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(

                                horizontal: AppSpacing.s14, vertical: AppSpacing.xxs),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isHidden
                                    ? p.error.withValues(alpha: 0.15)
                                    : p.accentContainer,
                                borderRadius: BorderRadius.circular(AppRadii.r12),
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
                                fontSize: AppFontSize.bodySmall,
                                color:
                                    isHidden ? p.textSecondary : p.textPrimary,
                                decoration: isHidden
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.s2),
                              child: Text(
                                '${context.l10n.tracksCount(folder.songCount)} • ${folder.path}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isHidden
                                      ? p.textTertiary
                                      : p.textSecondary,
                                  fontSize: AppFontSize.caption,
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

                                    horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadii.r10)),
                              ),
                              icon: Icon(
                                isHidden
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                                size: 15,
                              ),
                              label: Text(
                                isHidden ? context.l10n.settingsUnhide : context.l10n.settingsHide,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: AppFontSize.label),
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
        ),
      );
    },
    );
  }
}
