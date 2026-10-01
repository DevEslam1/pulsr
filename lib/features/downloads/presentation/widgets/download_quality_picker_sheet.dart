// lib/features/downloads/presentation/widgets/download_quality_picker_sheet.dart
import 'package:flutter/material.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/ytm_audio_quality.dart';

/// Modal bottom sheet allowing users to select download quality with live
/// file size estimates before starting a download.
class DownloadQualityPickerSheet extends StatefulWidget {
  final SongsTableData song;
  final YtmAudioQuality initialQuality;
  final ValueChanged<YtmAudioQuality> onConfirm;

  const DownloadQualityPickerSheet({
    super.key,
    required this.song,
    this.initialQuality = YtmAudioQuality.high,
    required this.onConfirm,
  });

  /// Displays the download quality picker as a modal bottom sheet.
  static Future<YtmAudioQuality?> show(
    BuildContext context, {
    required SongsTableData song,
    YtmAudioQuality initialQuality = YtmAudioQuality.high,
    ValueChanged<YtmAudioQuality>? onConfirm,
  }) {
    return showModalBottomSheet<YtmAudioQuality>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DownloadQualityPickerSheet(
        song: song,
        initialQuality: initialQuality,
        onConfirm: (q) {
          Navigator.of(ctx).pop(q);
          onConfirm?.call(q);
        },
      ),
    );
  }

  /// Estimates audio file size in bytes based on duration and bitrate.
  static int estimateBytes(int durationMs, int bitrateKbps) {
    if (durationMs <= 0 || bitrateKbps <= 0) return 0;
    final seconds = durationMs ~/ 1000;
    return seconds * bitrateKbps * 1000 ~/ 8;
  }

  @override
  State<DownloadQualityPickerSheet> createState() =>
      _DownloadQualityPickerSheetState();
}

class _DownloadQualityPickerSheetState
    extends State<DownloadQualityPickerSheet> {
  late YtmAudioQuality _selectedQuality;

  @override
  void initState() {
    super.initState();
    _selectedQuality = widget.initialQuality;
  }

  int _bitrateFor(YtmAudioQuality q) {
    return switch (q) {
      YtmAudioQuality.low => 64,
      YtmAudioQuality.medium => 128,
      YtmAudioQuality.high => 256,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final durationMs = widget.song.durationMs;

    final options = [
      (
        quality: YtmAudioQuality.high,
        title: context.l10n.settingsQualityHigh,
        desc: context.l10n.settingsQualityHighDownloadDesc,
        badge: '256 kbps',
        icon: Icons.high_quality_rounded,
      ),
      (
        quality: YtmAudioQuality.medium,
        title: context.l10n.settingsQualityMedium,
        desc: context.l10n.settingsQualityMediumDownloadDesc,
        badge: '128 kbps',
        icon: Icons.graphic_eq_rounded,
      ),
      (
        quality: YtmAudioQuality.low,
        title: context.l10n.settingsQualityLow,
        desc: context.l10n.settingsQualityLowDownloadDesc,
        badge: '64 kbps',
        icon: Icons.data_saver_on_rounded,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.r24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              decoration: BoxDecoration(
                color: p.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadii.r4),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Icon(Icons.downloading_rounded, color: p.accent, size: 24),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.downloadQuality,
                      style: TextStyle(
                        fontSize: AppFontSize.titleLarge,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      '${widget.song.title} • ${widget.song.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                color: p.textSecondary,
                tooltip: context.l10n.cancel,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Quality Option Cards
          ...options.map((opt) {
            final isSelected = opt.quality == _selectedQuality;
            final bitrate = _bitrateFor(opt.quality);
            final estBytes =
                DownloadQualityPickerSheet.estimateBytes(durationMs, bitrate);
            final estString =
                estBytes > 0 ? Formatters.formatBytes(estBytes) : null;

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Material(
                color: isSelected
                    ? p.accent.withValues(alpha: 0.12)
                    : p.surfaceContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.r16),
                  side: BorderSide(
                    color: isSelected ? p.accent : p.hairline,
                    width: isSelected ? 1.8 : 1.0,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.r16),
                  onTap: () {
                    setState(() => _selectedQuality = opt.quality);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(
                          opt.icon,
                          color: isSelected ? p.accent : p.textSecondary,
                          size: 24,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    opt.title,
                                    style: TextStyle(
                                      fontSize: AppFontSize.body,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          isSelected ? p.accent : p.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.xs,
                                      vertical: AppSpacing.xxs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? p.accent.withValues(alpha: 0.2)
                                          : p.hairline,
                                      borderRadius:
                                          BorderRadius.circular(AppRadii.r4),
                                    ),
                                    child: Text(
                                      opt.badge,
                                      style: TextStyle(
                                        fontSize: AppFontSize.tiny,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? p.accent
                                            : p.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                opt.desc,
                                style: TextStyle(
                                  fontSize: AppFontSize.caption,
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (estString != null)
                          Text(
                            '~$estString',
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? p.accent : p.textSecondary,
                            ),
                          ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: isSelected ? p.accent : p.textTertiary,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: AppSpacing.xs),

          // Confirm Button
          FilledButton.icon(
            icon: const Icon(Icons.download_rounded, size: 20),
            label: Text(context.l10n.confirm),
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.r14),
              ),
            ),
            onPressed: () => widget.onConfirm(_selectedQuality),
          ),
        ],
      ),
    );
  }
}
