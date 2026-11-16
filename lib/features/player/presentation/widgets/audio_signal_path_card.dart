// lib/features/player/presentation/widgets/audio_signal_path_card.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../domain/models/audio_signal_path.dart';

/// Real-time 4-stage Audio Signal Path readout card:
/// Source File -> Decoder Output -> Active Output Route -> Hardware Output Rate.
class AudioSignalPathCard extends StatelessWidget {
  final AudioSignalPath signalPath;
  final Color activeColor;

  const AudioSignalPathCard({
    super.key,
    required this.signalPath,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final statusColor = signalPath.isBitPerfect
        ? AppColors.dacGold
        : (signalPath.isDirectPath ? p.success : activeColor);
    final capsParts = <String>[
      if (signalPath.deviceEncodings.isNotEmpty)
        '${context.l10n.signalPathEncodingsLabel}: ${signalPath.deviceEncodings.join(', ')}',
      if (signalPath.deviceChannelCounts.isNotEmpty)
        '${context.l10n.signalPathChannelsLabel}: ${signalPath.deviceChannelCounts.join('/')}ch',
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(
          color: signalPath.isBitPerfect
              ? AppColors.dacGold.withValues(alpha: 0.45)
              : p.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 18, color: statusColor),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.signalPathTitle,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      context.l10n.signalPathSubtitle,
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded, size: 16, color: p.textSecondary),
                visualDensity: VisualDensity.compact,
                tooltip: context.l10n.signalPathCopyTooltip,
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: signalPath.toChainString()),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.signalPathCopied)),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          _SignalStageRow(
            index: 1,
            label: context.l10n.dspSourceFile,
            value: signalPath.sourceSummary,
            accent: activeColor,
            p: p,
          ),
          const SizedBox(height: AppSpacing.s6),
          _SignalStageRow(
            index: 2,
            label: context.l10n.dspDecoderOutput,
            value: signalPath.decoderSummary,
            accent: activeColor,
            p: p,
          ),
          const SizedBox(height: AppSpacing.s6),
          _SignalStageRow(
            index: 3,
            label: context.l10n.signalPathActiveRoute,
            value: capsParts.isEmpty
                ? signalPath.routeSummary
                : '${signalPath.routeSummary}\n${capsParts.join(' • ')}',
            accent: statusColor,
            p: p,
          ),
          const SizedBox(height: AppSpacing.s6),
          _SignalStageRow(
            index: 4,
            label: context.l10n.dspHardwareEndpoint,
            value: signalPath.hardwareSummary,
            accent: statusColor,
            p: p,
          ),
        ],
      ),
    );
  }
}

class _SignalStageRow extends StatelessWidget {
  final int index;
  final String label;
  final String value;
  final Color accent;
  final PulsrPalette p;

  const _SignalStageRow({
    required this.index,
    required this.label,
    required this.value,
    required this.accent,
    required this.p,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: TextStyle(
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                  color: p.textSecondary,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
