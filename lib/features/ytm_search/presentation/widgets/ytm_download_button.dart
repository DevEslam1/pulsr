// lib/features/ytm_search/presentation/widgets/ytm_download_button.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/errors/error_message_resolver.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/models/download_settings.dart';
import '../../../../domain/models/ytm_audio_quality.dart';
import '../../../downloads/presentation/widgets/download_quality_picker_sheet.dart';
import '../../cubit/ytm_download_cubit.dart';

import '../../../../core/utils/pulsr_haptics.dart';

/// Routes a picker-confirmed [quality] into the queued task, where the
/// repository persists it and hands it to the transfer service. Extracted to
/// the top level so the wiring is unit-testable without the YTM UI being
/// compiled in.
@visibleForTesting
void routeDownloadQuality(
  YtmDownloadCubit cubit,
  SongsTableData song,
  YtmAudioQuality quality,
) {
  cubit.download(song, quality: quality);
}

/// The picker's preselection: the user's persisted download-quality default,
/// falling back to high for an unknown/legacy value.
@visibleForTesting
YtmAudioQuality downloadQualityFromSetting(String? value) {
  final normalized = value?.trim().toLowerCase();
  for (final quality in YtmAudioQuality.values) {
    if (quality.name == normalized) return quality;
  }
  return YtmAudioQuality.high;
}

/// Per-result download control: shows an idle download icon, a determinate
/// progress ring while transferring, a check once it lands in the library, and
/// a retry icon on failure. Keyed by the track's video id so its state survives
/// list reordering.
class YtmDownloadButton extends StatelessWidget {
  final SongsTableData song;
  final Color? activeColor;
  final Color? iconColor;
  final double iconSize;

  const YtmDownloadButton({
    super.key,
    required this.song,
    this.activeColor,
    this.iconColor,
    this.iconSize = 20,
  });

  Future<void> _openQualityPicker(
    BuildContext context,
    YtmDownloadCubit cubit,
  ) async {
    PulsrHaptics.mediumImpact();
    String? defaultQuality;
    try {
      defaultQuality = (await DownloadSettings.load()).quality;
    } catch (_) {
      defaultQuality = null;
    }
    if (!context.mounted) return;
    DownloadQualityPickerSheet.show(
      context,
      song: song,
      initialQuality: downloadQualityFromSetting(defaultQuality),
      onConfirm: (quality) {
        routeDownloadQuality(cubit, song, quality);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.ytmEnabled) return const SizedBox.shrink();

    final p = context.palette;
    final videoId = song.remoteId ?? '';
    if (videoId.isEmpty) return const SizedBox.shrink();

    final tintColor = activeColor ?? p.accent;
    final baseColor = iconColor ?? p.textTertiary;

    final provided = context.read<YtmDownloadCubit?>();
    final cubit = provided ??
        (getIt.isRegistered<YtmDownloadCubit>()
            ? getIt<YtmDownloadCubit>()
            : null);
    if (cubit == null) return const SizedBox.shrink();

    return BlocSelector<YtmDownloadCubit, YtmDownloadState, YtDownloadItem>(
      bloc: cubit,
      selector: (state) => state.itemFor(videoId),
      builder: (context, item) {
        final isAlreadyLocal = song.source == SongSource.local &&
            (song.remoteId != null && song.remoteId!.isNotEmpty);

        final Widget child;
        if (isAlreadyLocal || item.status == YtDownloadStatus.done) {
          child = SizedBox(
            key: const ValueKey('ytm_dl_done'),
            width: AppSpacing.s40,
            height: 40,
            child: Center(
              child: Container(
                width: iconSize + 10,
                height: iconSize + 10,
                decoration: BoxDecoration(
                  color: tintColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.download_done_rounded,
                  size: iconSize,
                  color: tintColor,
                ),
              ),
            ),
          );
        } else {
          switch (item.status) {
            case YtDownloadStatus.queued:
            case YtDownloadStatus.running:
              final isRunning = item.status == YtDownloadStatus.running;
              final progressValue = isRunning
                  ? item.progress?.clamp(0.0, 1.0)
                  : null;
              final pctLabel = progressValue == null
                  ? null
                  : '${(progressValue * 100).toStringAsFixed(0)}%';
              final actionLabel = isRunning
                  ? '${context.l10n.pause}${pctLabel != null ? ' ($pctLabel)' : ''}'
                  : context.l10n.cancel;
              child = Tooltip(
                key: const ValueKey('ytm_dl_progress'),
                message: actionLabel,
                child: Semantics(
                  button: true,
                  label: actionLabel,
                  value: pctLabel,
                  child: InkResponse(
                    radius: 20,
                    onTap: () {
                      PulsrHaptics.selectionClick();
                      if (isRunning) {
                        cubit.pauseDownload(videoId);
                      } else {
                        cubit.cancelDownload(videoId);
                      }
                    },
                    onLongPress: () {
                      PulsrHaptics.mediumImpact();
                      cubit.cancelDownload(videoId);
                    },
                    child: SizedBox(
                      width: AppSpacing.s40,
                      height: 40,
                      child: Center(
                        child: SizedBox(
                          width: iconSize + 4,
                          height: iconSize + 4,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                strokeWidth: 2.2,
                                value: progressValue,
                                color: tintColor,
                                backgroundColor:
                                    tintColor.withValues(alpha: 0.18),
                              ),
                              Icon(
                                isRunning
                                    ? Icons.pause_rounded
                                    : Icons.close_rounded,
                                size: iconSize * 0.58,
                                color: tintColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              break;
            case YtDownloadStatus.paused:
              child = GestureDetector(
                key: const ValueKey('ytm_dl_paused'),
                onLongPress: () => _openQualityPicker(context, cubit),
                child: IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  tooltip: context.l10n.resume,
                  icon: Icon(
                    Icons.pause_circle_outline_rounded,
                    size: iconSize,
                    color: tintColor,
                  ),
                  onPressed: () {
                    PulsrHaptics.selectionClick();
                    cubit.download(song);
                  },
                ),
              );
              break;
            case YtDownloadStatus.done:
              child = SizedBox(
                key: const ValueKey('ytm_dl_done'),
                width: AppSpacing.s40,
                height: 40,
                child: Icon(
                  Icons.download_done_rounded,
                  size: iconSize,
                  color: tintColor,
                ),
              );
              break;
            case YtDownloadStatus.failed:
              child = GestureDetector(
                key: const ValueKey('ytm_dl_failed'),
                onLongPress: () => _openQualityPicker(context, cubit),
                child: IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  tooltip: item.error == null
                      ? context.l10n.retry
                      : resolveUiErrorMessage(context, item.error!),
                  icon: Icon(
                    Icons.error_outline_rounded,
                    size: iconSize,
                    color: p.error,
                  ),
                  onPressed: () {
                    PulsrHaptics.selectionClick();
                    cubit.retryDownload(song);
                  },
                ),
              );
              break;
            case YtDownloadStatus.canceled:
            case YtDownloadStatus.idle:
              child = GestureDetector(
                key: const ValueKey('ytm_dl_idle'),
                onLongPress: () => _openQualityPicker(context, cubit),
                child: IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  tooltip: context.l10n.browseDownloadOffline,
                  icon: Icon(
                    Icons.download_rounded,
                    size: iconSize,
                    color: baseColor,
                  ),
                  onPressed: () {
                    PulsrHaptics.selectionClick();
                    cubit.download(song);
                  },
                ),
              );
              break;
          }
        }

        return AnimatedSwitcher(
          duration: context.motion(PulsrMotion.state),
          switchInCurve: context.motionCurve(PulsrMotion.enter),
          switchOutCurve: context.motionCurve(PulsrMotion.exit),
          child: child,
        );
      },
    );
  }
}
