// lib/features/settings/presentation/widgets/battery_optimization_card.dart
import 'package:flutter/material.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/services/battery_optimization_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/platform_capabilities.dart';

class BatteryOptimizationCard extends StatefulWidget {
  const BatteryOptimizationCard({super.key});

  @override
  State<BatteryOptimizationCard> createState() =>
      _BatteryOptimizationCardState();
}

class _BatteryOptimizationCardState extends State<BatteryOptimizationCard> {
  bool _isDismissed = false;
  bool _isIgnoring = true;
  String _manufacturer = '';

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (!PlatformCapabilities.isAndroid) return;
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
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
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Playback stops when screen is off?',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                icon:
                    Icon(Icons.close_rounded, size: 18, color: p.textTertiary),
                onPressed: () async {
                  await BatteryOptimizationService.dismissCard();
                  setState(() => _isDismissed = true);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Some device manufacturers aggressively stop background playback. Granting battery exemption ensures uninterrupted music playback.',
            style: TextStyle(color: p.textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                onPressed: () async {
                  await BatteryOptimizationService
                      .requestIgnoreBatteryOptimizations();
                  await _checkStatus();
                },
                child: const Text('Allow Background Playback'),
              ),
              if (isAggressive) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    final guideUrl =
                        BatteryOptimizationService.getDontKillMyAppUrl(
                            _manufacturer);
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(
                            '${_manufacturer.toUpperCase()} Background Guide'),
                        content: Text(
                          'Your device manufacturer is known for aggressive background process killing.\n\nVisit $guideUrl to configure lock screen and battery settings.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Text(
                    'Device Guide',
                    style: TextStyle(
                        color: p.accent,
                        fontSize: 12,
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
