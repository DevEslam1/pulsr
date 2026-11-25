import 'dart:math' as math;
import '../../../../core/di/injection.dart';
// lib/features/player/presentation/widgets/autoeq_search_sheet.dart
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/safe_file_path.dart';
import '../../../../data/audio/autoeq_parametric_parser.dart';
import '../../../../data/audio/equalizer_manager.dart';
import '../../../../data/audio/headphone_profiles_repository.dart';
import '../../../../domain/models/headphone_profile.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../cubit/player_cubit.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/utils/pulsr_haptics.dart';

/// AutoEQ profile browser backed by the bundled real-AutoEQ dataset
/// (`headphone_profiles.json`). Profiles carry genuine parametric filters
/// (freq/Q/gain/type) that drive the native 64-band parametric EQ, so the
/// sheet surfaces the filter count to distinguish PEQ-fidelity profiles from
/// legacy flat-curve ones.
class AutoEqSearchSheet extends StatefulWidget {
  final HeadphoneProfilesRepository? repo;
  const AutoEqSearchSheet({super.key, this.repo});

  @override
  State<AutoEqSearchSheet> createState() => _AutoEqSearchSheetState();
}

class _AutoEqSearchSheetState extends State<AutoEqSearchSheet> {
  late final HeadphoneProfilesRepository _repo;
  final TextEditingController _searchController = TextEditingController();
  List<HeadphoneProfile> _results = [];
  String _category = 'All';
  List<String> _categories = const ['All'];
  bool _isLoading = true;
  bool _isImporting = false;
  AutoEqCorrectionMode _correctionMode = AutoEqCorrectionMode.peq;

  @override
  void initState() {
    super.initState();
    _repo = widget.repo ??
        (getIt.isRegistered<HeadphoneProfilesRepository>()
            ? getIt<HeadphoneProfilesRepository>()
            : HeadphoneProfilesRepository());
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _repo.loadProfiles();
    AutoEqCorrectionMode loadedMode = _correctionMode;
    if (getIt.isRegistered<EqualizerManager>()) {
      loadedMode = getIt<EqualizerManager>().autoEqCorrectionMode;
    }
    if (!mounted) return;
    setState(() {
      _correctionMode = loadedMode;
      _categories = _repo.getCategories();
      _applyFilter();
      _isLoading = false;
    });
  }

  void _applyFilter() {
    _results = _repo.search(_searchController.text, category: _category);
  }

  /// Imports an AutoEQ `ParametricEQ.txt` file, persists it as a custom
  /// profile and applies it. The filters are the authoritative correction, so
  /// the generated profile deliberately carries no 10-band gains — the
  /// repository accepts that shape (gains OR filters) and the native PEQ path
  /// in `EqualizerManager` already prefers filters when present.
  Future<void> _importParametricProfile() async {
    if (_isImporting) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isImporting = true);

    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['txt'],
      );
      if (picked == null) return;

      final file = SafeFilePath.validate(
        picked.path,
        allowedExtensions: const ['txt'],
      );
      if (file == null) {
        _showMessage(messenger, l10n.autoeqParametricImportFailed);
        return;
      }

      final parsed = await AutoEqParametricParser.parseFile(file);
      if (parsed == null) {
        // Empty / comment-only file: valid input, but nothing to import.
        _showMessage(messenger, l10n.autoeqParametricNoFilters);
        return;
      }

      final profile = AutoEqParametricParser.toHeadphoneProfile(parsed);
      if (profile.filters.isEmpty) {
        _showMessage(messenger, l10n.autoeqParametricNoFilters);
        return;
      }

      await _repo.addCustomProfile(profile);
      if (!mounted) return;
      if (_repo.getProfileById(profile.id) == null) {
        // The repository rejected the profile — never report a phantom import.
        _showMessage(messenger, l10n.autoeqParametricImportFailed);
        return;
      }

      setState(() {
        _categories = _repo.getCategories();
        _applyFilter();
      });

      await context.read<PlayerCubit>().applyHeadphoneProfile(profile);
      if (!mounted) return;

      final warnings = parsed.warnings;
      final message = StringBuffer(l10n.autoeqParametricImported(profile.name));
      if (warnings.isNotEmpty) {
        // Surface the first parse/mapping caveat; the full list went to the
        // parser's warning sink for diagnostics.
        message.write('\n${warnings.first}');
      }
      _showMessage(messenger, message.toString(),
          duration: Duration(seconds: warnings.isEmpty ? 2 : 5));
    } on AutoEqParametricParseFailure catch (e, st) {
      ErrorLogger.log('AutoEQ parametric import failed',
          error: e, stackTrace: st, category: 'AutoEqSearchSheet');
      if (!mounted) return;
      _showMessage(
          messenger, '${l10n.autoeqParametricImportFailed}\n${e.message}',
          duration: const Duration(seconds: 5));
    } catch (e, st) {
      ErrorLogger.log('AutoEQ parametric import failed',
          error: e, stackTrace: st, category: 'AutoEqSearchSheet');
      if (!mounted) return;
      _showMessage(messenger, l10n.autoeqParametricImportFailed);
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _showMessage(ScaffoldMessengerState messenger, String message,
      {Duration duration = const Duration(seconds: 3)}) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      duration: duration,
    ));
  }

  Widget _buildModeChoice(
      String title, AutoEqCorrectionMode mode, PulsrPalette p) {
    final selected = _correctionMode == mode;
    return ChoiceChip(
      label: Text(
        title,
        style: TextStyle(
          color: selected ? p.onAccent : p.textSecondary,
          fontSize: AppFontSize.caption,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      selected: selected,
      selectedColor: p.primary,
      backgroundColor: p.surfaceCard,
      side: BorderSide(color: p.hairline),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      onSelected: (_) async {
        PulsrHaptics.selectionClick();
        setState(() => _correctionMode = mode);
        await context.read<PlayerCubit>().setAutoEqCorrectionMode(mode);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Selection is driven by cubit state, updated immediately when a profile
    // is applied (no waiting for the next engine resync).
    final selectedProfileId = context.select<PlayerCubit, String?>(
      (c) => c.state.selectedHeadphoneProfile?.id,
    );

    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, AppSpacing.lg),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.textSecondary.withValues(alpha: 0.3),
                  borderRadius: AppRadii.r2All,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.autoEqDatabase,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        context.l10n.autoEqProfilesSubtitle(
                          _repo.profiles.length,
                        ),
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.caption,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget),
                  icon: Icon(Icons.close, color: p.textSecondary),
                  tooltip: context.l10n.close,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(_applyFilter),
              style:
                  TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
              decoration: InputDecoration(
                hintText: context.l10n.dspSearchHeadphones,
                hintStyle:
                    TextStyle(color: p.textSecondary.withValues(alpha: 0.6)),
                prefixIcon: Icon(Icons.search, color: p.primary),
                filled: true,
                fillColor: p.surfaceCard,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                border: OutlineInputBorder(
                  borderRadius: AppRadii.r16All,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Tooltip(
                message: context.l10n.autoeqParametricImportHint,
                child: OutlinedButton.icon(
                  onPressed: _isImporting ? null : _importParametricProfile,
                  icon: _isImporting
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: p.primary,
                          ),
                        )
                      : Icon(Icons.file_open_rounded,
                          size: 16, color: p.primary),
                  label: Text(
                    context.l10n.autoeqParametricImport,
                    style: TextStyle(
                      color: p.primary,
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: p.surfaceCard,
                    side: BorderSide(color: p.hairline),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s14,
                      vertical: AppSpacing.s6,
                    ),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.r12All,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildModeChoice('PEQ (IIR)', AutoEqCorrectionMode.peq, p),
                  const SizedBox(width: AppSpacing.xs),
                  _buildModeChoice(
                      'FIR Min-Phase', AutoEqCorrectionMode.firMinPhase, p),
                  const SizedBox(width: AppSpacing.xs),
                  _buildModeChoice(
                      'FIR Linear-Phase', AutoEqCorrectionMode.firLinear, p),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: math.max(
                AppSpacing.minTouchTarget,
                MediaQuery.textScalerOf(context).scale(38.0),
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final selected = cat == _category;
                  return ChoiceChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        color: selected ? p.onAccent : p.textSecondary,
                        fontSize: AppFontSize.label,
                      ),
                    ),
                    selected: selected,
                    selectedColor: p.primary,
                    backgroundColor: p.surfaceCard,
                    side: BorderSide(color: p.hairline),
                    showCheckmark: false,
                    onSelected: (_) {
                      PulsrHaptics.selectionClick();
                      setState(() {
                        _category = cat;
                        _applyFilter();
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: _isLoading
                  ? const SkeletonList()
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            context.l10n.noHpMatch,
                            style: TextStyle(color: p.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.xs),
                          itemBuilder: (context, index) {
                            final item = _results[index];
                            final isSelected = selectedProfileId == item.id;
                            final filterCount = item.filters.length;

                            return InkWell(
                              onTap: () async {
                                final cubit = context.read<PlayerCubit>();
                                await cubit.applyHeadphoneProfile(item);
                                if (!context.mounted) return;
                                // Only confirm when the cubit actually applied the
                                // profile (a bit-perfect guard may have refused it).
                                if (cubit.state.selectedHeadphoneProfile?.id !=
                                    item.id) {
                                  return;
                                }
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '${context.l10n.dspAppliedProfile} ${item.name}'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              borderRadius: AppRadii.r16All,
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.s14),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? p.primary.withValues(alpha: 0.15)
                                      : p.surfaceCard,
                                  borderRadius: AppRadii.r16All,
                                  border: Border.all(
                                    color:
                                        isSelected ? p.primary : p.surfaceCard,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding:
                                          const EdgeInsets.all(AppSpacing.s10),
                                      decoration: BoxDecoration(
                                        color:
                                            p.primary.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.headphones_rounded,
                                          color: p.primary, size: 20),
                                    ),
                                    const SizedBox(width: AppSpacing.s14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: p.textPrimary,
                                              fontSize: AppFontSize.body,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: AppSpacing.s2),
                                          Text(
                                            filterCount > 0
                                                ? '${item.category} • $filterCount PEQ bands • AutoEQ'
                                                : '${item.category} • ${context.l10n.dspAutoEqVerified}',
                                            style: TextStyle(
                                              color: p.textSecondary,
                                              fontSize: AppFontSize.label,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(Icons.check_circle_rounded,
                                          color: p.primary, size: 20),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
