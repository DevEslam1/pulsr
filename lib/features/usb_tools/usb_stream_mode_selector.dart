// lib/features/usb_tools/usb_stream_mode_selector.dart
//
// Presentational clock-architecture selector for the direct USB path.
//
// It shows three things and never invents a fourth:
//   1. the domain the native sink actually reports (bitPerfectLocked / asrc /
//      bestEffort / unknown);
//   2. the per-DAC request the user may change while idle;
//   3. the measured evidence behind the label (drift, buffer fill, feedback).
//
// The widget owns no storage and no platform channel: the settings section
// persists the choice and reloads the status. That makes every state reachable
// in a widget test without a DAC.

import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/theme/aura_theme.dart';
import '../../data/services/usb_exclusive_service.dart';
import 'usb_stream_mode.dart';

/// Strings for the selector. Kept next to the widget because USB tools use
/// their own compact copy rather than the global ARB surface.
class UsbStreamModeStrings {
  const UsbStreamModeStrings._();

  static const String title = 'Clock architecture';
  static const String subtitle =
      'How the direct USB path keeps time with this DAC.';
  static const String bitPerfectPull = 'Bit-perfect (pull)';
  static const String bitPerfectPullHint =
      'Pulls PCM at the DAC clock from a buffered reservoir. Only this mode may '
      'report bit-perfect, and only when the source matches the wire format.';
  static const String clockSyncAsrc = 'Clock sync (ASRC)';
  static const String clockSyncAsrcHint =
      'Resamples to follow the DAC feedback ratio. Always reported as resampled, '
      'never as bit-perfect.';
  static const String bestEffort = 'Best effort';
  static const String bestEffortHint =
      'Real-time producer with ±1% steering and underrun/overrun counters.';
  static const String flagDisabled = 'Experimental — disabled by rollout flag';
  static const String feedbackRequired =
      'Requires an asynchronous feedback endpoint; this DAC has none';
  static const String streamingLocked =
      'Stop streaming before changing the clock architecture.';
  static const String unknownDomain =
      'No active stream. The domain is reported only while streaming.';
  static const String evidence = 'Measured evidence';
}

/// Clock-architecture card.
class UsbStreamModeSelector extends StatelessWidget {
  const UsbStreamModeSelector({
    super.key,
    required this.status,
    required this.selected,
    required this.pullFlagEnabled,
    required this.asrcFlagEnabled,
    required this.streamingActive,
    this.onChanged,
  });

  final UsbExclusiveStatus status;
  final UsbStreamMode selected;
  final bool pullFlagEnabled;
  final bool asrcFlagEnabled;
  final bool streamingActive;
  final ValueChanged<UsbStreamMode>? onChanged;

  bool _available(UsbStreamMode mode) => switch (mode) {
        UsbStreamMode.bestEffort => true,
        UsbStreamMode.bitPerfectPull => pullFlagEnabled,
        UsbStreamMode.clockSyncAsrc =>
          asrcFlagEnabled && status.feedbackPresent,
      };

  String? _disabledReason(UsbStreamMode mode) {
    if (_available(mode)) return null;
    if (mode == UsbStreamMode.clockSyncAsrc && !status.feedbackPresent) {
      return UsbStreamModeStrings.feedbackRequired;
    }
    return UsbStreamModeStrings.flagDisabled;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = !streamingActive && onChanged != null;
    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.timelapse_rounded, size: 18, color: p.accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  UsbStreamModeStrings.title,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _DomainPill(domain: status.clockDomain),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            UsbStreamModeStrings.subtitle,
            style: TextStyle(
                color: p.textSecondary, fontSize: AppFontSize.caption),
          ),
          const SizedBox(height: AppSpacing.sm),
          KeyedSubtree(
            key: ValueKey<UsbStreamMode>(selected),
            child: DropdownButtonFormField<UsbStreamMode>(
              key: const ValueKey<String>('usb-stream-mode-dropdown'),
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: UsbStreamMode.values.map((mode) {
                final reason = _disabledReason(mode);
                return DropdownMenuItem<UsbStreamMode>(
                  value: mode,
                  enabled: enabled && reason == null,
                  child: Text(
                    reason == null ? _label(mode) : '${_label(mode)} — $reason',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: enabled
                  ? (mode) {
                      if (mode == null || !_available(mode)) return;
                      onChanged!(mode);
                    }
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _hint(selected),
            style: TextStyle(
                color: p.textSecondary, fontSize: AppFontSize.caption),
          ),
          if (streamingActive) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              UsbStreamModeStrings.streamingLocked,
              style: TextStyle(color: p.warning, fontSize: AppFontSize.caption),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _Evidence(status: status),
        ],
      ),
    );
  }

  static String _label(UsbStreamMode mode) => switch (mode) {
        UsbStreamMode.bitPerfectPull => UsbStreamModeStrings.bitPerfectPull,
        UsbStreamMode.clockSyncAsrc => UsbStreamModeStrings.clockSyncAsrc,
        UsbStreamMode.bestEffort => UsbStreamModeStrings.bestEffort,
      };

  static String _hint(UsbStreamMode mode) => switch (mode) {
        UsbStreamMode.bitPerfectPull => UsbStreamModeStrings.bitPerfectPullHint,
        UsbStreamMode.clockSyncAsrc => UsbStreamModeStrings.clockSyncAsrcHint,
        UsbStreamMode.bestEffort => UsbStreamModeStrings.bestEffortHint,
      };
}

/// Domain pill. Color is semantic: bit-perfect only when verified, ASRC is a
/// warning (resampled), best effort is neutral.
class _DomainPill extends StatelessWidget {
  const _DomainPill({required this.domain});

  final UsbClockDomain domain;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = switch (domain) {
      UsbClockDomain.bitPerfectLocked => p.success,
      UsbClockDomain.asrc => p.warning,
      UsbClockDomain.bestEffort => p.textSecondary,
      UsbClockDomain.unknown => p.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadii.r12All,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        domain.toShortLabel(),
        style: TextStyle(
          color: color,
          fontSize: AppFontSize.caption,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Evidence rows: drift, buffer fill, feedback presence, under/overruns.
class _Evidence extends StatelessWidget {
  const _Evidence({required this.status});

  final UsbExclusiveStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style =
        TextStyle(color: p.textSecondary, fontSize: AppFontSize.caption);
    final rows = <String>[
      if (!status.streamingActive) UsbStreamModeStrings.unknownDomain,
      if (status.streamingActive) ...<String>[
        'Session ${status.sessionState}',
        'Drift ${status.clockDriftPpm} ppm',
        'Buffer ${status.ringFillMs} ms',
        status.feedbackPresent
            ? 'Feedback endpoint present'
            : 'No feedback endpoint',
        'Underruns ${status.underrunCount} · Overruns ${status.overrunCount}',
        if (status.quirkApplied.isNotEmpty)
          'Quirks ${status.quirkApplied.join(", ")}',
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          UsbStreamModeStrings.evidence,
          style: style.copyWith(
            color: p.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final row in rows) Text(row, style: style),
        if (status.quirkBitPerfectAffected)
          Text(
            'Bit-perfect limited: '
            '${status.quirkBitPerfectReason ?? "device quirk"}',
            style:
                style.copyWith(color: p.warning, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}
