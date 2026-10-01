// lib/features/player/presentation/widgets/autoeq_search_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/audio/headphone_profiles_repository.dart';
import '../../../../domain/models/headphone_profile.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../cubit/player_cubit.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// AutoEQ profile browser backed by the bundled real-AutoEQ dataset
/// (`headphone_profiles.json`). Profiles carry genuine parametric filters
/// (freq/Q/gain/type) that drive the native 64-band parametric EQ, so the
/// sheet surfaces the filter count to distinguish PEQ-fidelity profiles from
/// legacy flat-curve ones.
class AutoEqSearchSheet extends StatefulWidget {
  const AutoEqSearchSheet({super.key});

  @override
  State<AutoEqSearchSheet> createState() => _AutoEqSearchSheetState();
}

class _AutoEqSearchSheetState extends State<AutoEqSearchSheet> {
  final HeadphoneProfilesRepository _repo = HeadphoneProfilesRepository();
  final TextEditingController _searchController = TextEditingController();
  List<HeadphoneProfile> _results = [];
  String _category = 'All';
  List<String> _categories = const ['All'];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _repo.loadProfiles();
    if (!mounted) return;
    setState(() {
      _categories = _repo.getCategories();
      _applyFilter();
      _isLoading = false;
    });
  }

  void _applyFilter() {
    _results = _repo.search(_searchController.text, category: _category);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Selection is driven by cubit state, updated immediately when a profile
    // is applied (no waiting for the next engine resync).
    final selectedProfileId =
        context.watch<PlayerCubit>().state.selectedHeadphoneProfile?.id;

    return Container(
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
                borderRadius: BorderRadius.circular(AppRadii.r2),
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
                      '${_repo.profiles.length} profiles • parametric (freq/Q/gain)',
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
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
            style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
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
                borderRadius: BorderRadius.circular(AppRadii.r16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
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
                  onSelected: (_) => setState(() {
                    _category = cat;
                    _applyFilter();
                  }),
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
                            borderRadius: BorderRadius.circular(AppRadii.r16),
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.s14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? p.primary.withValues(alpha: 0.15)
                                    : p.surfaceCard,
                                borderRadius:
                                    BorderRadius.circular(AppRadii.r16),
                                border: Border.all(
                                  color: isSelected ? p.primary : p.surfaceCard,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding:
                                        const EdgeInsets.all(AppSpacing.s10),
                                    decoration: BoxDecoration(
                                      color: p.primary.withValues(alpha: 0.12),
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
    );
  }
}
