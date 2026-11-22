import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/pulsr_pressable.dart';
import '../../../../core/widgets/pulsr_scroll_edge_fade.dart';
import '../../../../core/widgets/source_scope_switcher.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/services/hires_audio_service.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/presentation/widgets/audio_quality_sheet.dart';
import '../../../settings/cubit/settings_cubit.dart';
import 'discovery_chip.dart';

export '../../../../core/widgets/source_scope_switcher.dart' show SourceScope;

/// Compact Active Audio Output Pill (e.g., `USB DAC · 96kHz`, `LDAC`, or `Speaker`).
///
/// Displays current physical or wireless output routing and sample rate.
/// Tapping opens [AudioQualitySheet] with the live DSP routing and hardware diagnostics.
class ActiveAudioOutputPill extends StatelessWidget {
  final VoidCallback? onTap;

  const ActiveAudioOutputPill({
    super.key,
    this.onTap,
  });

  static ({IconData icon, String label, Color? accentColor, bool isHiRes})
      resolveOutputDetails(BuildContext context, AudioOutputInfo? info) {
    final p = context.palette;
    if (info == null) {
      return (
        icon: Icons.speaker_rounded,
        label: context.l10n.dspSpeaker,
        accentColor: null,
        isHiRes: false,
      );
    }

    // 1. USB DAC
    if (info.isUsb || info.isUsbDac) {
      final rate = info.sinkSampleRate > 0
          ? info.sinkSampleRate
          : (info.sampleRate > 0 ? info.sampleRate : 0);
      String rateSuffix = '';
      if (rate > 0) {
        final inKhz = rate >= 1000 ? rate / 1000.0 : rate.toDouble();
        final formatted =
            inKhz.toStringAsFixed(inKhz.truncateToDouble() == inKhz ? 0 : 1);
        rateSuffix = ' · ${formatted}kHz';
      }
      final rawLabel = info.usbDacLabel?.trim();
      final dacName = (rawLabel != null && rawLabel.isNotEmpty)
          ? rawLabel
          : 'USB DAC';
      return (
        icon: Icons.album_rounded,
        label: '$dacName$rateSuffix',
        accentColor: p.warning,
        isHiRes: true,
      );
    }

    // 2. Bluetooth (LDAC, aptX HD, AAC, SBC, etc.)
    if (info.isBt || info.isBluetooth) {
      final codec = info.btCodecName?.trim();
      final hasCodec = codec != null && codec.isNotEmpty;
      final upper = codec?.toUpperCase() ?? '';
      final isHiResBt = upper.contains('LDAC') ||
          upper.contains('APTX HD') ||
          upper.contains('APTX-HD') ||
          upper.contains('LHDC');
      return (
        icon: Icons.bluetooth_audio_rounded,
        label: hasCodec ? codec : 'Bluetooth',
        accentColor: isHiResBt ? p.accent : null,
        isHiRes: isHiResBt,
      );
    }

    // 3. Wired Headphones / Line Out
    if (info.isHeadphones) {
      final rate = info.sinkSampleRate > 0 ? info.sinkSampleRate : 0;
      String rateSuffix = '';
      if (rate > 0) {
        final inKhz = rate >= 1000 ? rate / 1000.0 : rate.toDouble();
        final formatted =
            inKhz.toStringAsFixed(inKhz.truncateToDouble() == inKhz ? 0 : 1);
        rateSuffix = ' · ${formatted}kHz';
      }
      return (
        icon: Icons.headphones_rounded,
        label: '${context.l10n.wizardWiredTitle}$rateSuffix',
        accentColor: null,
        isHiRes: false,
      );
    }

    // 4. Built-in Speaker / Default
    return (
      icon: Icons.speaker_rounded,
      label: context.l10n.dspSpeaker,
      accentColor: null,
      isHiRes: false,
    );
  }

  void _handleTap(BuildContext context) {
    PulsrHaptics.lightImpact();
    if (onTap != null) {
      onTap!();
      return;
    }

    final p = context.palette;
    final playerState = context.read<PlayerCubit?>()?.state;
    final currentSong = playerState?.currentSong ??
        SongsTableData(
          id: 0,
          title: context.l10n.settingsHardwareAudioOutput,
          artist: context.l10n.settingsMasterAudioEngine,
          album: context.l10n.settingsInternalUsbDac,
          durationMs: 0,
          path: '',
          source: SongSource.local,
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
        );
    AudioQualitySheet.show(context, currentSong, p.accent);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settingsCubit = context.watch<SettingsCubit?>();
    final info = settingsCubit?.state.currentOutputDevice ??
        (getIt.isRegistered<HiResAudioService>()
            ? getIt<HiResAudioService>().currentOutputInfo
            : null);

    final details = resolveOutputDetails(context, info);

    return Semantics(
      button: true,
      label: '${context.l10n.settingsHardwareAudioOutput}: ${details.label}',
      child: PulsrPressable(
        key: const ValueKey('active_audio_output_pill'),
        enableHaptics: false,
        onTap: () => _handleTap(context),
        child: AnimatedContainer(
          duration: context.motion(PulsrDurations.state),
          curve: context.motionCurve(Curves.easeOutCubic),
          constraints: const BoxConstraints(
            minHeight: 34.0,
            maxHeight: 38.0,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s10,
            vertical: AppSpacing.s6,
          ),
          decoration: BoxDecoration(
            color: details.accentColor != null
                ? details.accentColor!.withValues(alpha: 0.12)
                : p.surfaceContainerHigh,
            borderRadius: AppRadii.full,
            border: Border.all(
              color: details.accentColor != null
                  ? details.accentColor!.withValues(alpha: 0.38)
                  : p.hairline,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                details.icon,
                size: 15,
                color: details.accentColor ?? p.textSecondary,
              ),
              const SizedBox(width: AppSpacing.s6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140.0),
                child: Text(
                  details.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: details.accentColor ?? p.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.expand_more_rounded,
                size: 14,
                color: (details.accentColor ?? p.textSecondary)
                    .withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact segmented `Local / Online` switcher aligned cleanly near the header.
///
/// Replaces the oversized full-width toggle with a sleek, space-efficient pill.
/// Persists scope selection to [SharedPreferences] matching [SourceScopeSwitcher].
class CompactSourceScopeSwitcher extends StatelessWidget {
  final SourceScope selectedScope;
  final ValueChanged<SourceScope> onChanged;
  final String persistKey;

  const CompactSourceScopeSwitcher({
    super.key,
    required this.selectedScope,
    required this.onChanged,
    this.persistKey = 'home',
  });

  Future<void> _persistScope(SourceScope scope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SourceScopeSwitcher.storageKey(persistKey),
        scope.name,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isOnline = selectedScope == SourceScope.online;

    return Semantics(
      container: true,
      label: isOnline ? context.l10n.online : context.l10n.local,
      child: Container(
        key: const ValueKey('compact_source_scope_switcher'),
        height: 34.0,
        decoration: BoxDecoration(
          color: p.surfaceContainerHigh,
          borderRadius: AppRadii.full,
          border: Border.all(color: p.hairline),
        ),
        padding: const EdgeInsets.all(3.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CompactScopeSegment(
              key: const ValueKey('scope_segment_local'),
              label: context.l10n.local,
              icon: Icons.folder_rounded,
              isSelected: !isOnline,
              onTap: () {
                if (isOnline) {
                  PulsrHaptics.selectionClick();
                  unawaited(_persistScope(SourceScope.local));
                  onChanged(SourceScope.local);
                }
              },
            ),
            const SizedBox(width: AppSpacing.xxs),
            _CompactScopeSegment(
              key: const ValueKey('scope_segment_online'),
              label: context.l10n.online,
              icon: Icons.cloud_rounded,
              isSelected: isOnline,
              onTap: () {
                if (!isOnline) {
                  PulsrHaptics.selectionClick();
                  unawaited(_persistScope(SourceScope.online));
                  onChanged(SourceScope.online);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactScopeSegment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _CompactScopeSegment({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return PulsrPressable(
      pressedScale: 0.96,
      enableHaptics: false,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: context.motion(PulsrDurations.state),
        curve: context.motionCurve(Curves.easeOutCubic),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: isSelected ? p.accent : Colors.transparent,
          borderRadius: AppRadii.full,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? p.onAccent : p.textSecondary,
            ),
            const SizedBox(width: AppSpacing.s4),
            Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? p.onAccent : p.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The refined discovery header on Home.
///
/// Integrates:
/// 1. Greeting and date
/// 2. Compact Active Audio Output Pill (tapping opens output/DSP routing sheet)
/// 3. Compact `Local / Online` switcher aligned cleanly near the header
/// 4. Preserves horizontal shortcut chips row when [onMore] or [showShortcuts] is present.
class QuickDiscoveryHeader extends StatelessWidget {
  final bool online;
  final bool showYtm;
  final VoidCallback? onMore;

  final SourceScope? scope;
  final ValueChanged<SourceScope>? onScopeChanged;
  final bool showOnlineTab;
  final bool offlineOnly;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onAudioOutputTap;
  final bool showHeaderRow;
  final bool showScopeSwitcher;
  final bool showShortcuts;

  const QuickDiscoveryHeader({
    super.key,
    this.onMore,
    this.online = false,
    this.showYtm = true,
    this.scope,
    this.onScopeChanged,
    this.showOnlineTab = true,
    this.offlineOnly = false,
    this.onSettingsTap,
    this.onAudioOutputTap,
    this.showHeaderRow = true,
    this.showScopeSwitcher = true,
    this.showShortcuts = true,
  });

  String _getGreeting(BuildContext context) {
    final hour = clock.now().hour;
    if (hour < 12) return context.l10n.goodMorning;
    if (hour < 17) return context.l10n.goodAfternoon;
    return context.l10n.goodEvening;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final effectiveScope = scope ?? (online ? SourceScope.online : SourceScope.local);

    final items = <({IconData icon, String label, VoidCallback onTap})>[
      if (online) ...[
        (
          icon: Icons.explore_rounded,
          label: context.l10n.ytmExplore,
          onTap: () => context.push('/ytm-explore'),
        ),
        (
          icon: Icons.downloading_rounded,
          label: context.l10n.downloadsTitle,
          onTap: () => context.push('/downloads'),
        ),
      ] else ...[
        (
          icon: Icons.person_rounded,
          label: context.l10n.artists,
          onTap: () => context.push('/library?tab=artists'),
        ),
        (
          icon: Icons.album_rounded,
          label: context.l10n.albums,
          onTap: () => context.push('/library?tab=albums'),
        ),
        (
          icon: Icons.folder_rounded,
          label: context.l10n.folders,
          onTap: () => context.push('/library?tab=folders'),
        ),
        (
          icon: Icons.calendar_month_rounded,
          label: context.l10n.decades,
          onTap: () => context.push('/year'),
        ),
        if (showYtm)
          (
            icon: Icons.downloading_rounded,
            label: context.l10n.downloadsTitle,
            onTap: () => context.push('/downloads'),
          ),
      ],
      (
        icon: Icons.radio_rounded,
        label: context.l10n.radioTitle,
        onTap: () => context.push('/radio'),
      ),
      (
        icon: Icons.queue_music_rounded,
        label: context.l10n.queue,
        onTap: () => context.push('/queue'),
      ),
      (
        icon: Icons.group_rounded,
        label: context.l10n.partyListenTogether,
        onTap: () => context.push('/party'),
      ),
    ];

    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6);
    final railHeight = math.max(48.0, (48.0 * textScale).roundToDouble());

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeaderRow) ...[
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              Adaptive.pagePadding(context),
              AppSpacing.md,
              Adaptive.pagePadding(context),
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        MaterialLocalizations.of(context)
                            .formatMediumDate(clock.now())
                            .toUpperCase(),
                        style: TextStyle(
                          color: p.textTertiary,
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        _getGreeting(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                      ),
                    ],
                  ),
                ),
                if (offlineOnly)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                          end: AppSpacing.xs),
                      child: Chip(
                        avatar: Icon(Icons.wifi_off_rounded,
                            size: 14, color: p.accent),
                        label: Text(
                          context.l10n.offlineOnlyMode,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w700,
                            color: p.accent,
                          ),
                        ),
                        backgroundColor: p.accentContainer,
                        side: BorderSide(color: p.hairline),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ActiveAudioOutputPill(onTap: onAudioOutputTap),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  key: const ValueKey('home_settings_button'),
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  icon: Icon(
                    Icons.settings_outlined,
                    color: p.textSecondary,
                    size: 22,
                  ),
                  tooltip: context.l10n.settings,
                  onPressed: onSettingsTap ?? () => context.push('/settings'),
                ),
              ],
            ),
          ),
        ],

        // Sleek compact segmented switcher aligned cleanly near the header
        if (showScopeSwitcher && showOnlineTab && onScopeChanged != null) ...[
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              Adaptive.pagePadding(context),
              AppSpacing.sm,
              Adaptive.pagePadding(context),
              0,
            ),
            child: CompactSourceScopeSwitcher(
              selectedScope: effectiveScope,
              onChanged: onScopeChanged!,
            ),
          ),
        ],

        if (showShortcuts && onMore != null) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: railHeight,
            child: Row(
              children: [
                Expanded(
                  child: PulsrScrollEdgeFade(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsetsDirectional.only(
                        start: Adaptive.pagePadding(context),
                        end: AppSpacing.sm,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: AppSpacing.s8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Center(
                          child: DiscoveryChip(
                            icon: item.icon,
                            label: item.label,
                            iconColor: p.accent,
                            onTap: item.onTap,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: Adaptive.pagePadding(context),
                  ),
                  child: SizedBox(
                    height: railHeight,
                    child: Center(
                      child: DiscoveryChip(
                        icon: Icons.apps_rounded,
                        label: context.l10n.browseMoreTools,
                        iconColor: p.textSecondary,
                        onTap: onMore!,
                        compact: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
