// lib/features/player/presentation/themes/player_theme_helpers.dart
import 'dart:ui';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_blur.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../cubit/player_state.dart';

/// Pure, zero-I/O resolver for the immediate previous and next tracks in the
/// active playback queue.
///
/// Respects [PlayerRepeatMode.all] wrap-around and falls back to
/// [PlayerState.queueHistory] for the previous track when at index 0.
({SongsTableData? prev, SongsTableData? next}) resolveQueueNeighbors(
  PlayerState state,
) {
  final queue = state.queue;
  final idx = state.currentIndex;
  final repeatAll = state.repeatMode == PlayerRepeatMode.all;

  SongsTableData? prev;
  if (idx > 0 && idx - 1 < queue.length) {
    prev = queue[idx - 1];
  } else if (repeatAll && queue.length > 1) {
    prev = queue.last;
  } else if (state.queueHistory.isNotEmpty) {
    prev = state.queueHistory.last;
  }

  SongsTableData? next;
  if (idx >= 0 && idx + 1 < queue.length) {
    next = queue[idx + 1];
  } else if (repeatAll && queue.length > 1) {
    next = queue.first;
  }

  return (prev: prev, next: next);
}

/// Single telemetry token extracted from decoded audio headers.
class PlayerAudioTelemetrySpec {
  final String label;
  final bool isFormat;

  const PlayerAudioTelemetrySpec({
    required this.label,
    this.isFormat = false,
  });
}

/// Structured audiophile telemetry formatted strictly from decoded track
/// headers and the live [AudioOutputInfo] snapshot (zero I/O).
class PlayerAudioTelemetry {
  final String? codec;
  final String? sampleRateLabel;
  final String? bitDepthLabel;
  final String? bitrateLabel;
  final String? outputLabel;
  final bool isHiRes;
  final bool isLossless;
  final bool isUsbDac;
  final bool isBitPerfect;
  final List<PlayerAudioTelemetrySpec> specs;

  /// Compact badge label (e.g. `FLAC · 24-BIT / 96.0 kHz` or `MP3 · 320 kbps`).
  final String compactBadge;

  /// Full telemetry readout including output/DAC when present
  /// (e.g. `FLAC · 24-BIT · 96.0 kHz · USB DAC`).
  final String fullLine;

  const PlayerAudioTelemetry({
    this.codec,
    this.sampleRateLabel,
    this.bitDepthLabel,
    this.bitrateLabel,
    this.outputLabel,
    this.isHiRes = false,
    this.isLossless = false,
    this.isUsbDac = false,
    this.isBitPerfect = false,
    this.specs = const [],
    this.compactBadge = '',
    this.fullLine = '',
  });

  bool get isEmpty => specs.isEmpty && outputLabel == null;
  bool get isNotEmpty => !isEmpty;
}

/// Formats honest, decoded-header-only audio telemetry for [song] and
/// [settings].
///
/// Missing header fields are omitted rather than guessed or inferred from the
/// file extension, preserving bit-perfect provenance honesty.
PlayerAudioTelemetry formatPlayerAudioTelemetry(
  SongsTableData? song,
  SettingsState settings,
) {
  final specs = <PlayerAudioTelemetrySpec>[];
  String? codecLabel;
  String? sampleRateLabel;
  String? bitDepthLabel;
  String? bitrateLabel;
  var isLossless = false;
  var isHiRes = false;

  if (song != null) {
    final rawCodec = song.codec?.trim();
    if (rawCodec != null && rawCodec.isNotEmpty) {
      codecLabel = rawCodec.toUpperCase();
      specs.add(PlayerAudioTelemetrySpec(label: codecLabel, isFormat: true));
      final lc = rawCodec.toLowerCase();
      isLossless = lc.contains('flac') ||
          lc.contains('alac') ||
          lc.contains('wav') ||
          lc.contains('pcm') ||
          lc.contains('aiff') ||
          lc.contains('dsd') ||
          lc.contains('dsf') ||
          lc.contains('dff');
    }

    final bitDepth = song.bitDepth;
    if (bitDepth != null && bitDepth > 0) {
      bitDepthLabel = '$bitDepth-BIT';
      specs.add(PlayerAudioTelemetrySpec(label: bitDepthLabel));
    }

    final sampleRate = song.sampleRate;
    if (sampleRate != null && sampleRate > 0) {
      sampleRateLabel = '${(sampleRate / 1000).toStringAsFixed(1)}\u00A0kHz';
      specs.add(PlayerAudioTelemetrySpec(label: sampleRateLabel));
    }

    final bitrateKbps = song.bitrateKbps;
    if (bitrateKbps != null && bitrateKbps > 0) {
      bitrateLabel = '$bitrateKbps\u00A0kbps';
      specs.add(PlayerAudioTelemetrySpec(label: bitrateLabel));
    }

    isHiRes = isLossless &&
        ((bitDepth != null && bitDepth >= 24) ||
            (sampleRate != null && sampleRate > 48000));
  }

  final device = settings.currentOutputDevice;
  final isUsbDac = device?.isUsbDac == true;
  final isBitPerfect = device?.isBitPerfectActive == true;
  String? outputLabel;
  if (device != null) {
    if (isUsbDac) {
      outputLabel = isBitPerfect ? 'USB DAC · BIT-PERFECT' : 'USB DAC';
    } else if (device.isBt) {
      final btCodec = device.btCodecName?.trim();
      outputLabel =
          (btCodec != null && btCodec.isNotEmpty) ? 'BT $btCodec' : 'BLUETOOTH';
    } else if (isBitPerfect) {
      outputLabel = 'BIT-PERFECT';
    }
  }

  final compactParts = <String>[
    if (codecLabel != null) codecLabel,
    if (bitDepthLabel != null && sampleRateLabel != null)
      '$bitDepthLabel / $sampleRateLabel'
    else if (sampleRateLabel != null)
      sampleRateLabel
    else if (bitDepthLabel != null)
      bitDepthLabel
    else if (bitrateLabel != null)
      bitrateLabel,
  ];
  final compactBadge = compactParts.join(' · ');

  final fullParts = <String>[
    ...specs.map((s) => s.label),
    if (outputLabel != null) outputLabel,
  ];
  final fullLine = fullParts.join(' · ');

  return PlayerAudioTelemetry(
    codec: codecLabel,
    sampleRateLabel: sampleRateLabel,
    bitDepthLabel: bitDepthLabel,
    bitrateLabel: bitrateLabel,
    outputLabel: outputLabel,
    isHiRes: isHiRes,
    isLossless: isLossless,
    isUsbDac: isUsbDac,
    isBitPerfect: isBitPerfect,
    specs: specs,
    compactBadge: compactBadge,
    fullLine: fullLine,
  );
}

/// Accessible >= 48dp interactive icon button for decoupled full-screen themes.
///
/// Supports optional frosted glass backdrop blur (gated via [AppBlur.canBlur]
/// and [AppBlur.clampSigma]) and an optional active indicator dot.
class PlayerIconActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? iconColor;
  final Color? activeColor;
  final Color? surfaceColor;
  final Color? borderColor;
  final double iconSize;
  final double blurSigma;
  final bool showActiveDot;

  const PlayerIconActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.iconColor,
    this.activeColor,
    this.surfaceColor,
    this.borderColor,
    this.iconSize = 22,
    this.blurSigma = 0.0,
    this.showActiveDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final resolvedActive = activeColor ?? p.accent;
    final resolvedIconColor =
        isActive ? resolvedActive : (iconColor ?? p.textPrimary);
    final allowBlur = blurSigma > 0.0 && AppBlur.canBlur(context);
    final clampedSigma = AppBlur.clampSigma(blurSigma);

    Widget buttonBody = Material(
      color: surfaceColor ?? Colors.transparent,
      shape: CircleBorder(
        side: borderColor != null
            ? BorderSide(color: borderColor!, width: 1.0)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                PulsrHaptics.selectionClick();
                onTap!();
              },
        child: SizedBox(
          width: AppSpacing.minTouchTarget,
          height: AppSpacing.minTouchTarget,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(icon, size: iconSize, color: resolvedIconColor),
                if (showActiveDot && isActive)
                  Positioned(
                    bottom: -6,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: resolvedActive,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (allowBlur) {
      buttonBody = ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: clampedSigma, sigmaY: clampedSigma),
          child: buttonBody,
        ),
      );
    }

    return Semantics(
      button: true,
      toggled: isActive,
      enabled: onTap != null,
      label: tooltip,
      excludeSemantics: true,
      child: buttonBody,
    );
  }
}

/// Minimal customizable top bar for full-screen player themes.
///
/// Enforces >= 48dp hit targets and lets each theme pass its own center title
/// or badge widget, custom foreground/surface colors, and trailing actions.
class PlayerCompactTopBar extends StatelessWidget {
  final Widget? center;
  final List<Widget> trailing;
  final VoidCallback? onDismiss;
  final Color? foregroundColor;
  final Color? buttonSurfaceColor;
  final Color? buttonBorderColor;
  final double blurSigma;
  final EdgeInsetsGeometry padding;
  final bool showDismiss;

  const PlayerCompactTopBar({
    super.key,
    this.center,
    this.trailing = const [],
    this.onDismiss,
    this.foregroundColor,
    this.buttonSurfaceColor,
    this.buttonBorderColor,
    this.blurSigma = 0.0,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    this.showDismiss = true,
  });

  void _defaultDismiss(BuildContext context) {
    try {
      final router = GoRouter.of(context);
      if (router.canPop()) {
        router.pop();
        return;
      }
      router.go('/');
    } catch (_) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = foregroundColor ?? p.textPrimary;

    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (showDismiss)
            PlayerIconActionButton(
              icon: Icons.keyboard_arrow_down_rounded,
              tooltip: context.l10n.close,
              iconColor: fg,
              surfaceColor: buttonSurfaceColor,
              borderColor: buttonBorderColor,
              iconSize: 26,
              blurSigma: blurSigma,
              onTap: onDismiss ?? () => _defaultDismiss(context),
            )
          else
            const SizedBox(
              width: AppSpacing.minTouchTarget,
              height: AppSpacing.minTouchTarget,
            ),
          Expanded(
            child: center != null
                ? Center(child: center!)
                : const SizedBox.shrink(),
          ),
          if (trailing.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: trailing,
            )
          else
            const SizedBox(
              width: AppSpacing.minTouchTarget,
              height: AppSpacing.minTouchTarget,
            ),
        ],
      ),
    );
  }
}
