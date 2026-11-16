// lib/features/usb_tools/usb_quirk_editor.dart
//
// The per-device quirk form: silence and buffer sliders, the transfer-size
// dropdown and the three behavioural switches. It is presentation only — it
// hands a new [UsbQuirkProfile] to `onChanged` and never touches storage or the
// platform channel, so it can be exercised without a device.
//
// Every control sits on a >= 48 dp target and carries an explicit [Semantics]
// node (label, value, toggled state) because a switch tile's default semantics
// omit the surrounding explanation.

import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/theme/aura_theme.dart';
import 'usb_ergonomics_strings.dart';
import 'usb_quirk_profile.dart';

/// Editable form for one [UsbQuirkProfile].
class UsbQuirkEditor extends StatelessWidget {
  /// Creates the editor.
  const UsbQuirkEditor({
    super.key,
    required this.profile,
    required this.onChanged,
    this.enabled = true,
  });

  /// Profile currently being edited.
  final UsbQuirkProfile profile;

  /// Called with a re-validated copy on every control change.
  final ValueChanged<UsbQuirkProfile> onChanged;

  /// Whether the controls accept input.
  final bool enabled;

  /// Transfer sizes offered by the dropdown; 0 means auto.
  static const List<int> transferSizes = <int>[
    0,
    512,
    1024,
    2048,
    4096,
    8192,
    16384,
    32768,
    65536,
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _QuirkSlider(
            label: UsbErgonomicsStrings.silenceLabel,
            hint: UsbErgonomicsStrings.silenceHint,
            valueText: UsbErgonomicsStrings.silenceValue(profile.silenceMs),
            value: profile.silenceMs.toDouble(),
            max: UsbQuirkProfile.maxSilenceMs.toDouble(),
            divisions: 50,
            enabled: enabled,
            format: (v) =>
                UsbErgonomicsStrings.silenceValue(v.round()),
            onChanged: (v) =>
                onChanged(profile.copyWith(silenceMs: v.round())),
          ),
          const SizedBox(height: AppSpacing.md),
          _QuirkSlider(
            label: UsbErgonomicsStrings.bufferLabel,
            hint: UsbErgonomicsStrings.bufferHint,
            valueText: UsbErgonomicsStrings.bufferValue(profile.bufferMs),
            value: profile.bufferMs.toDouble(),
            max: UsbQuirkProfile.maxBufferMs.toDouble(),
            divisions: 50,
            enabled: enabled,
            format: (v) => UsbErgonomicsStrings.bufferValue(v.round()),
            onChanged: (v) => onChanged(profile.copyWith(bufferMs: v.round())),
          ),
          const SizedBox(height: AppSpacing.md),
          _TransferSizeField(
            value: profile.transferSizeBytes,
            enabled: enabled,
            onChanged: (bytes) =>
                onChanged(profile.copyWith(transferSizeBytes: bytes)),
          ),
          const SizedBox(height: AppSpacing.md),
          _QuirkSwitch(
            title: UsbErgonomicsStrings.altResetTitle,
            hint: UsbErgonomicsStrings.altResetHint,
            value: profile.altResetOnStop,
            enabled: enabled,
            onChanged: (v) => onChanged(profile.copyWith(altResetOnStop: v)),
          ),
          _QuirkSwitch(
            title: UsbErgonomicsStrings.force16Title,
            hint: UsbErgonomicsStrings.force16Hint,
            value: profile.force16Bit,
            enabled: enabled,
            onChanged: (v) => onChanged(profile.copyWith(force16Bit: v)),
          ),
          _QuirkSwitch(
            title: UsbErgonomicsStrings.hidTitle,
            hint: UsbErgonomicsStrings.hidHint,
            value: profile.hidEnabled,
            enabled: enabled,
            onChanged: (v) => onChanged(profile.copyWith(hidEnabled: v)),
          ),
        ],
      ),
    );
  }
}

/// Labelled slider block with a value readout and an explicit semantics node.
class _QuirkSlider extends StatelessWidget {
  const _QuirkSlider({
    required this.label,
    required this.hint,
    required this.valueText,
    required this.value,
    required this.max,
    required this.divisions,
    required this.enabled,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final String valueText;
  final double value;
  final double max;
  final int divisions;
  final bool enabled;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(label, style: text.titleSmall),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                valueText,
                style: text.labelMedium?.copyWith(
                  color: p.accent,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            hint,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
            ),
          ),
          SizedBox(
            height: AppSpacing.minTouchTarget,
            child: Slider(
              value: value.clamp(0, max),
              max: max,
              divisions: divisions,
              label: valueText,
              semanticFormatterCallback: format,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Transfer-size dropdown (auto, 512 B .. 64 kB).
class _TransferSizeField extends StatelessWidget {
  const _TransferSizeField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: UsbErgonomicsStrings.transferLabel,
      hint: UsbErgonomicsStrings.transferHint,
      enabled: enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(UsbErgonomicsStrings.transferLabel, style: text.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            UsbErgonomicsStrings.transferHint,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
            ),
          ),
          SizedBox(
            height: AppSpacing.minTouchTarget,
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              borderRadius: AppRadii.r12All,
              dropdownColor: p.surfaceContainerHigh,
              style: text.bodyMedium?.copyWith(color: p.textPrimary),
              onChanged: enabled
                  ? (selected) {
                      if (selected != null) onChanged(selected);
                    }
                  : null,
              items: <DropdownMenuItem<int>>[
                for (final size in UsbQuirkEditor.transferSizes)
                  DropdownMenuItem<int>(
                    value: size,
                    child: Text(
                      size == 0
                          ? UsbErgonomicsStrings.transferAuto
                          : UsbErgonomicsStrings.transferValue(size),
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

/// Switch row with an explicit semantics node and a 48 dp target.
class _QuirkSwitch extends StatelessWidget {
  const _QuirkSwitch({
    required this.title,
    required this.hint,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: title,
      hint: hint,
      toggled: value,
      enabled: enabled,
      onTap: enabled ? () => onChanged(!value) : null,
      child: ExcludeSemantics(
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: AppFontSize.body,
            ),
          ),
          subtitle: Text(
            hint,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
            ),
          ),
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}
