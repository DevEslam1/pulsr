// lib/features/settings/presentation/widgets/battery_optimization_card.dart
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/services/battery_optimization_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class BatteryOptimizationCard extends StatefulWidget {
  const BatteryOptimizationCard({super.key});

  @override
  State<BatteryOptimizationCard> createState() =>
      _BatteryOptimizationCardState();
}

// FIX-M10: Add WidgetsBindingObserver to refresh battery status on app resume
class _BatteryOptimizationCardState extends State<BatteryOptimizationCard>
    with WidgetsBindingObserver {
  bool _isDismissed = false;
  bool _isIgnoring = true;
  String _manufacturer = '';
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkStatus();
    }
  }

  Future<void> _checkStatus() async {
    if (!PlatformCapabilities.isAndroid || _isChecking) return;
    _isChecking = true;
    try {
      final dismissed = await BatteryOptimizationService.isCardDismissed();
      final ignoring =
          await BatteryOptimizationService.isIgnoringBatteryOptimizations();
      final m = await BatteryOptimizationService.getDeviceManufacturer();
      if (mounted) {
        setState(() {
          _isDismissed = dismissed;
          _isIgnoring = ignoring;
          _manufacturer = m;
        });
      }
    } finally {
      _isChecking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.isAndroid || _isDismissed || _isIgnoring) {
      return const SizedBox.shrink();
    }

    final p = context.palette;
    final isAggressive =
        BatteryOptimizationService.isAggressiveOem(_manufacturer);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.battery_alert_rounded, color: p.accent, size: 22),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(context.l10n.playbackStopsScreenOff,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.body,
                  ),
                ),
              ),
              IconButton(
                icon:
                    Icon(Icons.close_rounded, size: 18, color: p.textTertiary),
                tooltip: context.l10n.close,
                onPressed: () async {
                  await BatteryOptimizationService.dismissCard();
                  setState(() => _isDismissed = true);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(context.l10n.batteryExemptionDesc,
            style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.xs),
                  textStyle: const TextStyle(
                      fontSize: AppFontSize.label, fontWeight: FontWeight.w700),
                ),
                onPressed: () async {
                  await BatteryOptimizationService
                      .requestIgnoreBatteryOptimizations();
                  await _checkStatus();
                },
                child: Text(context.l10n.allowBackground),
              ),
              if (isAggressive) ...[
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  onPressed: () {
                    final guideUrl =
                        BatteryOptimizationService.getDontKillMyAppUrl(
                            _manufacturer);
                    PulsrDialogHelper.showCustomDialog<void>(
                      context,
                      builder: (ctx) => PulsrDialog(
                        title: context.l10n.settingsManufacturerBackgroundGuide(_manufacturer.toUpperCase()),
                        icon: Icons.battery_alert_rounded,
                        content: Text(
                          context.l10n.settingsAggressiveBatteryGuide(guideUrl),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(context.l10n.close),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Text(context.l10n.deviceGuide,
                    style: TextStyle(
                        color: p.accent,
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
