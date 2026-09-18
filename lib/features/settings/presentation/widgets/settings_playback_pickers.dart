// lib/features/settings/presentation/widgets/settings_picker_sheets.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';


void showMiniPlayerSwipePickerSheet(
  BuildContext context,
  SettingsCubit cubit, {
  required bool isLeft,
  required MiniPlayerSwipeAction currentAction,
}) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  final cardColor =
      Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
  final outlineColor = Theme.of(context).colorScheme.outline;
  final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
      context.palette.textPrimary;
  final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
      context.palette.textSecondary;

  final options = [
    (
      action: MiniPlayerSwipeAction.next,
      title: context.l10n.settingsSwipeNextTrack,
      subtitle: context.l10n.settingsSwipeNextDesc,
      icon: Icons.skip_next_rounded,
    ),
    (
      action: MiniPlayerSwipeAction.prev,
      title: context.l10n.settingsSwipePreviousTrack,
      subtitle: context.l10n.settingsSwipePrevDesc,
      icon: Icons.skip_previous_rounded,
    ),
    (
      action: MiniPlayerSwipeAction.volume,
      title: context.l10n.settingsSwipeAdjustVolume,
      subtitle: isLeft ? context.l10n.settingsLowerVolume : context.l10n.settingsRaiseVolume,
      icon: isLeft ? Icons.volume_down_rounded : Icons.volume_up_rounded,
    ),
    (
      action: MiniPlayerSwipeAction.none,
      title: context.l10n.settingsSwipeDisabled,
      subtitle: context.l10n.settingsSwipeIgnoreDesc,
      icon: Icons.block_rounded,
    ),
  ];

  PulsrSheetHelper.showPulsrSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s20, horizontal: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                child: Text(
                  isLeft
                      ? context.l10n.settingsSwipeLeftAction
                      : context.l10n.settingsSwipeRightAction,
                  style: const TextStyle(fontSize: AppFontSize.title, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...options.map((opt) {
                final isSelected = opt.action == currentAction;
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Material(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.12)
                        : cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r16),
                      side: BorderSide(
                        color: isSelected ? primaryColor : outlineColor,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(opt.icon,
                          color: isSelected ? primaryColor : textSecondary),
                      title: Text(opt.title,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isSelected ? primaryColor : textPrimary)),
                      subtitle: Text(opt.subtitle,
                          style: TextStyle(fontSize: AppFontSize.label, color: textSecondary)),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded, color: primaryColor)
                          : null,
                      onTap: () {
                        if (isLeft) {
                          cubit.setMiniPlayerSwipeLeft(opt.action);
                        } else {
                          cubit.setMiniPlayerSwipeRight(opt.action);
                        }
                        Navigator.pop(ctx);
                      },
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
}

void showNowPlayingDoubleTapPickerSheet(
  BuildContext context,
  SettingsCubit cubit,
  NowPlayingDoubleTapAction currentAction,
) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  final cardColor =
      Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
  final outlineColor = Theme.of(context).colorScheme.outline;
  final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
      context.palette.textPrimary;
  final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
      context.palette.textSecondary;

  final options = [
    (
      action: NowPlayingDoubleTapAction.toggleFavorite,
      title: context.l10n.settingsDoubleTapToggleFavorite,
      subtitle: context.l10n.settingsDoubleTapFavoriteDesc,
      icon: Icons.favorite_rounded,
    ),
    (
      action: NowPlayingDoubleTapAction.toggleLyrics,
      title: context.l10n.settingsDoubleTapToggleLyrics,
      subtitle: context.l10n.settingsDoubleTapLyricsDesc,
      icon: Icons.lyrics_rounded,
    ),
    (
      action: NowPlayingDoubleTapAction.none,
      title: context.l10n.settingsDoubleTapDisabled,
      subtitle: context.l10n.settingsDoubleTapIgnoreDesc,
      icon: Icons.block_rounded,
    ),
  ];

  PulsrSheetHelper.showPulsrSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s20, horizontal: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                child: Text(context.l10n.npDoubleTap,
                  style: TextStyle(fontSize: AppFontSize.title, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...options.map((opt) {
                final isSelected = opt.action == currentAction;
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Material(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.12)
                        : cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r16),
                      side: BorderSide(
                        color: isSelected ? primaryColor : outlineColor,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(opt.icon,
                          color: isSelected ? primaryColor : textSecondary),
                      title: Text(opt.title,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isSelected ? primaryColor : textPrimary)),
                      subtitle: Text(opt.subtitle,
                          style: TextStyle(fontSize: AppFontSize.label, color: textSecondary)),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded, color: primaryColor)
                          : null,
                      onTap: () {
                        cubit.setNowPlayingDoubleTap(opt.action);
                        Navigator.pop(ctx);
                      },
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
}

void showNowPlayingArtworkSwipePickerSheet(
  BuildContext context,
  SettingsCubit cubit,
  NowPlayingArtworkSwipeAction currentAction,
) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  final cardColor =
      Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
  final outlineColor = Theme.of(context).colorScheme.outline;
  final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
      context.palette.textPrimary;
  final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
      context.palette.textSecondary;

  final options = [
    (
      action: NowPlayingArtworkSwipeAction.nextPrev,
      title: context.l10n.settingsArtworkSwipeNextPrev,
      subtitle: context.l10n.settingsArtworkSwipeNextPrevDesc,
      icon: Icons.swipe_rounded,
    ),
    (
      action: NowPlayingArtworkSwipeAction.none,
      title: context.l10n.settingsArtworkSwipeDisabled,
      subtitle: context.l10n.settingsArtworkSwipeIgnoreDesc,
      icon: Icons.block_rounded,
    ),
  ];

  PulsrSheetHelper.showPulsrSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s20, horizontal: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                child: Text(context.l10n.npArtworkSwipe,
                  style: TextStyle(fontSize: AppFontSize.title, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...options.map((opt) {
                final isSelected = opt.action == currentAction;
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Material(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.12)
                        : cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r16),
                      side: BorderSide(
                        color: isSelected ? primaryColor : outlineColor,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(opt.icon,
                          color: isSelected ? primaryColor : textSecondary),
                      title: Text(opt.title,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isSelected ? primaryColor : textPrimary)),
                      subtitle: Text(opt.subtitle,
                          style: TextStyle(fontSize: AppFontSize.label, color: textSecondary)),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded, color: primaryColor)
                          : null,
                      onTap: () {
                        cubit.setNowPlayingArtworkSwipe(opt.action);
                        Navigator.pop(ctx);
                      },
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
}

void showQualityPickerSheet(
  BuildContext context,
  SettingsCubit cubit, {
  required bool isStreaming,
  required YtmAudioQuality currentQuality,
}) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  final cardColor =
      Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
  final outlineColor = Theme.of(context).colorScheme.outline;
  final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
      context.palette.textPrimary;
  final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
      context.palette.textSecondary;

  final options = [
    (
      quality: YtmAudioQuality.high,
      title: context.l10n.settingsQualityHigh,
      subtitle: isStreaming
          ? context.l10n.settingsQualityHighStreamDesc
          : context.l10n.settingsQualityHighDownloadDesc,
      icon: Icons.high_quality_rounded,
    ),
    (
      quality: YtmAudioQuality.medium,
      title: context.l10n.settingsQualityMedium,
      subtitle: isStreaming
          ? context.l10n.settingsQualityMediumStreamDesc
          : context.l10n.settingsQualityMediumDownloadDesc,
      icon: Icons.graphic_eq_rounded,
    ),
    (
      quality: YtmAudioQuality.low,
      title: context.l10n.settingsQualityLow,
      subtitle: isStreaming
          ? context.l10n.settingsQualityLowStreamDesc
          : context.l10n.settingsQualityLowDownloadDesc,
      icon: Icons.data_saver_on_rounded,
    ),
  ];

  PulsrSheetHelper.showPulsrSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s20, horizontal: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                child: Text(
                  isStreaming
                      ? context.l10n.streamingQuality
                      : context.l10n.downloadQuality,
                  style: const TextStyle(fontSize: AppFontSize.title, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...options.map((opt) {
                final isSelected = opt.quality == currentQuality;
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Material(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.12)
                        : cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r16),
                      side: BorderSide(
                        color: isSelected ? primaryColor : outlineColor,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(opt.icon,
                          color: isSelected ? primaryColor : textSecondary),
                      title: Text(opt.title,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isSelected ? primaryColor : textPrimary)),
                      subtitle: Text(opt.subtitle,
                          style: TextStyle(fontSize: AppFontSize.label, color: textSecondary)),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded, color: primaryColor)
                          : null,
                      onTap: () {
                        if (isStreaming) {
                          cubit.setStreamingQuality(opt.quality);
                        } else {
                          cubit.setDownloadQuality(opt.quality);
                        }
                        Navigator.pop(ctx);
                      },
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
}

