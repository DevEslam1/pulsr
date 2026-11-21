part of '../audio_quality_sheet.dart';

/// Now Playing tab content for [AudioQualitySheet]: Hero Quality Tier card,
/// YouTube streaming quality selector, and track source specifications.
extension _AudioQualityNowPlayingTab on AudioQualitySheet {
  List<Widget> _buildNowPlayingChildren({
    required BuildContext context,
    required AudioQualityInfo info,
    required SongsTableData resolvedSong,
    required SettingsCubit? settingsCubit,
    required YtmAudioQuality? streamingQuality,
    required PulsrPalette p,
  }) {
    return <Widget>[
      // Hero Quality Tier Card
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.s18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              info.badgeColor.withValues(alpha: 0.22),
              info.badgeColor.withValues(alpha: 0.05),
              p.surfaceContainer.withValues(alpha: 0.4),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: AppRadii.r20All,
          border: Border.all(
            color: info.badgeColor.withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: info.badgeColor.withValues(alpha: 0.15),
              blurRadius: 16,
              spreadRadius: -2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: info.badgeColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    info.icon,
                    color: info.badgeColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.tierLabel,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: p.textPrimary,
                              letterSpacing: AppTracking.label,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        info.shortBadgeLabel,
                        style: TextStyle(
                          color: info.badgeColor,
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w800,
                          letterSpacing: AppTracking.overline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s10),
            Text(
              info.description,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.label,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),

      // Streaming & Download Quality Selector for YouTube online streams
      if ((resolvedSong.source == SongSource.youtube ||
              resolvedSong.path.toLowerCase().startsWith('ytmusic://')) &&
          resolvedSong.isDownloaded != true) ...[
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.l10n.streamingQuality,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                letterSpacing: AppTracking.wide,
                fontWeight: FontWeight.w800,
                color: p.textSecondary,
              ),
            ),
            Text(
              context.l10n.downloadsMatchStream,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: activeColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildStreamingQualitySelector(
          context,
          settingsCubit,
          streamingQuality ?? YtmAudioQuality.high,
          p,
          activeColor,
        ),
      ],

      const SizedBox(height: AppSpacing.s20),

      // Audio Specifications
      Text(
        context.l10n.trackSourceSpecs,
        style: TextStyle(
          fontSize: AppFontSize.caption,
          letterSpacing: AppTracking.wide,
          fontWeight: FontWeight.w800,
          color: p.textSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.s10),
      Container(
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: AppRadii.r16All,
          border: Border.all(color: p.hairline),
        ),
        child: Column(
          children: [
            _buildSpecItem(
              context,
              icon: Icons.audio_file_rounded,
              label: context.l10n.dspAudioFormatCodec,
              value: info.format,
              subValue: info.codecName,
              p: p,
              isFirst: true,
            ),
            _buildSpecItem(
              context,
              icon: Icons.speed_rounded,
              label: info.bitrateEstimated
                  ? context.l10n.containerAverageEstimated
                  : context.l10n.dspSourceBitrate,
              value: info.bitrateKbps != null
                  ? '${info.bitrateKbps} kbps'
                  : context.l10n.dspUnknown,
              subValue: info.tier == AudioQualityTier.hiResLossless ||
                      info.tier == AudioQualityTier.lossless
                  ? context.l10n.losslessOutputFidelityNote
                  : context.l10n.dspCompressedStream,
              p: p,
            ),
            _buildSpecItem(
              context,
              icon: Icons.tune_rounded,
              label: context.l10n.dspSourceSampleRateDepth,
              value: (info.sampleRate != 'Unknown' &&
                      info.sampleRate.isNotEmpty)
                  ? ((info.bitDepth.isNotEmpty && info.bitDepth != 'Unknown')
                      ? '${info.sampleRate} / ${info.bitDepth}'
                      : info.sampleRate)
                  : ((info.bitDepth.isNotEmpty && info.bitDepth != 'Unknown')
                      ? info.bitDepth
                      : context.l10n.dspUnknown),
              subValue: info.channels,
              p: p,
            ),
            _buildSpecItem(
              context,
              icon: Icons.folder_zip_rounded,
              label: context.l10n.dspFileSizeDuration,
              value: resolvedSong.fileSize != null
                  ? '${(resolvedSong.fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB'
                  : context.l10n.dspUnknown,
              subValue:
                  '${context.l10n.duration}: ${Formatters.formatDuration(Duration(milliseconds: resolvedSong.durationMs))}',
              p: p,
            ),
            _buildSpecItem(
              context,
              icon: Icons.graphic_eq_rounded,
              label: context.l10n.dspDynamicRangeLra,
              value: resolvedSong.loudnessRange != null
                  ? '${resolvedSong.loudnessRange!.toStringAsFixed(1)} LU (${resolvedSong.loudnessRange! >= 12 ? context.l10n.dspDr12Audiophile : (resolvedSong.loudnessRange! >= 7 ? context.l10n.dspDrHighDynamic : context.l10n.dspDrStandard)})'
                  : context.l10n.dspStandardDynamicRange,
              subValue: context.l10n.dspEbuR128,
              p: p,
              isLast: true,
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildStreamingQualitySelector(
    BuildContext context,
    SettingsCubit? cubit,
    YtmAudioQuality current,
    PulsrPalette p,
    Color activeColor,
  ) {
    final options = [
      (
        quality: YtmAudioQuality.high,
        label: context.l10n.ytmQualityHighBitrate,
        icon: Icons.high_quality_rounded
      ),
      (
        quality: YtmAudioQuality.medium,
        label: context.l10n.ytmQualityMediumBitrate,
        icon: Icons.graphic_eq_rounded
      ),
      (
        quality: YtmAudioQuality.low,
        label: context.l10n.ytmQualityLowBitrate,
        icon: Icons.data_saver_on_rounded
      ),
    ];

    return Row(
      children: options.map((opt) {
        final isSelected = opt.quality == current;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Material(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.16)
                  : p.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.r12All,
                side: BorderSide(
                  color: isSelected ? activeColor : p.hairline,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: InkWell(
                borderRadius: AppRadii.r12All,
                onTap: () {
                  PulsrHaptics.selectionClick();
                  cubit?.setStreamingQuality(opt.quality);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        opt.icon,
                        size: 18,
                        color: isSelected ? activeColor : p.textSecondary,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        opt.label,
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? activeColor : p.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSpecItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String subValue,
    required PulsrPalette p,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: !isLast ? Border(bottom: BorderSide(color: p.hairline)) : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: AppRadii.r10All,
            ),
            child: Icon(icon, size: 18, color: p.textPrimary),
          ),
          const SizedBox(width: AppSpacing.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                    color: p.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: AppFontSize.bodySmall,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
                Text(
                  subValue,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: p.textSecondary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
