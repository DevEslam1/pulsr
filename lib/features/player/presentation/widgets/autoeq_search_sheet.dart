// lib/features/player/presentation/widgets/autoeq_search_sheet.dart
import 'package:flutter/material.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/services/autoeq_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../data/audio/equalizer_manager.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class AutoEqSearchSheet extends StatefulWidget {
  final EqualizerManager equalizerManager;

  const AutoEqSearchSheet({super.key, required this.equalizerManager});

  @override
  State<AutoEqSearchSheet> createState() => _AutoEqSearchSheetState();
}

class _AutoEqSearchSheetState extends State<AutoEqSearchSheet> {
  // Reuse the DI singleton so its profile cache survives across opens instead
  // of constructing a fresh (cache-less) service on every sheet.
  final AutoEqService _autoEqService = getIt.isRegistered<AutoEqService>()
      ? getIt<AutoEqService>()
      : AutoEqService();
  final TextEditingController _searchController = TextEditingController();
  List<AutoEqResult> _results = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _performSearch('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    final results = await _autoEqService.search(query);
    if (mounted) {
      setState(() {
        _results = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, AppSpacing.lg),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
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
              Text(context.l10n.autoEqDatabase,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.title,
                  fontWeight: FontWeight.w700,
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
            onChanged: _performSearch,
            style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
            decoration: InputDecoration(
              hintText: context.l10n.dspSearchHeadphones,
              hintStyle:
                  TextStyle(color: p.textSecondary.withValues(alpha: 0.6)),
              prefixIcon: Icon(Icons.search, color: p.primary),
              filled: true,
              fillColor: p.surfaceCard,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.r16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: p.primary))
                : _results.isEmpty
                    ? Center(
                        child: Text(context.l10n.noHpMatch,
                          style: TextStyle(color: p.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          final isSelected = widget.equalizerManager
                                  .selectedHeadphoneProfile?.name ==
                              item.name;

                          return InkWell(
                            onTap: () async {
                              final profile = item.toHeadphoneProfile();
                              await widget.equalizerManager
                                  .setHeadphoneProfile(profile);
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '${context.l10n.dspAppliedProfile} ${item.name}'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(AppRadii.r16),
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.s14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? p.primary.withValues(alpha: 0.15)
                                    : p.surfaceCard,
                                borderRadius: BorderRadius.circular(AppRadii.r16),
                                border: Border.all(
                                  color: isSelected ? p.primary : p.surfaceCard,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(AppSpacing.s10),
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
                                          style: TextStyle(
                                            color: p.textPrimary,
                                            fontSize: AppFontSize.body,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.s2),
                                        Text(
                                          '${context.l10n.dspTarget} ${item.target} • ${context.l10n.dspAutoEqVerified}',
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
