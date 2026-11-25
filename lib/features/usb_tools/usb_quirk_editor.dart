// lib/features/usb_tools/usb_quirk_editor.dart
//
// The per-device quirk form: HID consumer-control claim plus the direct-path
// audio transport knobs. It is presentation only — it hands a new
// [UsbQuirkProfile] to `onChanged` and never touches storage or the platform
// channel, so every state can be exercised without a device.
//
// Numeric fields only emit a profile when the typed value is inside the range
// the model accepts; an intermediate keystroke ("", "-") is ignored instead of
// throwing. Controls sit on >= 48 dp targets and carry explicit semantics.

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
          _QuirkSwitch(
            title: UsbErgonomicsStrings.hidTitle,
            hint: UsbErgonomicsStrings.hidHint,
            value: profile.hidEnabled,
            enabled: enabled,
            onChanged: (v) => onChanged(profile.copyWith(hidEnabled: v)),
          ),
          const Divider(height: AppSpacing.lg),
          Text(
            UsbErgonomicsStrings.audioSectionTitle,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            UsbErgonomicsStrings.audioSectionHint,
            style: TextStyle(
                color: p.textSecondary, fontSize: AppFontSize.caption),
          ),
          const SizedBox(height: AppSpacing.sm),
          _QuirkSwitch(
            title: UsbErgonomicsStrings.force16Title,
            hint: UsbErgonomicsStrings.force16Hint,
            value: profile.force16Bit,
            enabled: enabled,
            onChanged: (v) => onChanged(profile.copyWith(force16Bit: v)),
          ),
          _QuirkSwitch(
            title: UsbErgonomicsStrings.altResetTitle,
            hint: UsbErgonomicsStrings.altResetHint,
            value: profile.altResetOnStop,
            enabled: enabled,
            onChanged: (v) => onChanged(profile.copyWith(altResetOnStop: v)),
          ),
          _QuirkSwitch(
            title: UsbErgonomicsStrings.disableFeedbackTitle,
            hint: UsbErgonomicsStrings.disableFeedbackHint,
            value: profile.disableExplicitFeedback,
            enabled: enabled,
            onChanged: (v) =>
                onChanged(profile.copyWith(disableExplicitFeedback: v)),
          ),
          _QuirkSwitch(
            title: UsbErgonomicsStrings.uac1ReassertTitle,
            hint: UsbErgonomicsStrings.uac1ReassertHint,
            value: profile.uac1ReassertAfterAlt,
            enabled: enabled,
            onChanged: (v) =>
                onChanged(profile.copyWith(uac1ReassertAfterAlt: v)),
          ),
          _QuirkSwitch(
            title: UsbErgonomicsStrings.disableClockSwitchTitle,
            hint: UsbErgonomicsStrings.disableClockSwitchHint,
            value: profile.disableUac2ClockSwitch,
            enabled: enabled,
            onChanged: (v) =>
                onChanged(profile.copyWith(disableUac2ClockSwitch: v)),
          ),
          const SizedBox(height: AppSpacing.sm),
          _QuirkNumberField<int>(
            label: UsbErgonomicsStrings.silenceLabel,
            initialValue: profile.silenceMs == 0 ? '' : '${profile.silenceMs}',
            enabled: enabled,
            allowBlank: true,
            min: 0,
            max: UsbQuirkProfile.maxSilenceMs,
            onValue: (value) {
              onChanged(profile.copyWith(silenceMs: value ?? 0));
            },
          ),
          _QuirkNumberField<int>(
            label: UsbErgonomicsStrings.bufferLabel,
            initialValue: profile.bufferMs == 0 ? '' : '${profile.bufferMs}',
            enabled: enabled,
            allowBlank: true,
            min: 0,
            max: UsbQuirkProfile.maxBufferMs,
            onValue: (value) {
              onChanged(profile.copyWith(bufferMs: value ?? 0));
            },
          ),
          _QuirkNumberField<int>(
            label: UsbErgonomicsStrings.transferSizeLabel,
            initialValue: profile.transferSizeBytes == 0
                ? ''
                : '${profile.transferSizeBytes}',
            enabled: enabled,
            allowBlank: true,
            isValid: (v) =>
                v == 0 ||
                (v >= 64 && v <= UsbQuirkProfile.maxTransferSizeBytes),
            onValue: (value) {
              onChanged(profile.copyWith(transferSizeBytes: value ?? 0));
            },
          ),
          _QuirkNumberField<int>(
            label: UsbErgonomicsStrings.selectorPinLabel,
            initialValue: profile.preferredSelectorPin?.toString() ?? '',
            enabled: enabled,
            allowBlank: true,
            min: 0,
            max: 255,
            onValue: (value) {
              onChanged(profile.copyWith(preferredSelectorPin: value));
            },
          ),
          _QuirkNumberField<double>(
            label: UsbErgonomicsStrings.volumeCalibrationLabel,
            initialValue: profile.volumeCalibrationDb == 0.0
                ? ''
                : profile.volumeCalibrationDb.toStringAsFixed(1),
            enabled: enabled,
            allowBlank: true,
            min: -24.0,
            max: 24.0,
            onValue: (value) {
              onChanged(profile.copyWith(volumeCalibrationDb: value ?? 0.0));
            },
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
        child: Material(
          type: MaterialType.transparency,
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
      ),
    );
  }
}

/// Numeric quirk field. Empty input means "automatic" for the knobs that allow
/// it; out-of-range input surfaces [UsbErgonomicsStrings.numberInvalid].
class _QuirkNumberField<T extends num> extends StatefulWidget {
  const _QuirkNumberField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.enabled,
    required this.onValue,
    this.allowBlank = true,
    this.min,
    this.max,
    this.isValid,
  });

  final String label;
  final String initialValue;
  final bool enabled;
  final ValueChanged<T?> onValue;
  final bool allowBlank;
  final T? min;
  final T? max;
  final bool Function(T value)? isValid;

  @override
  State<_QuirkNumberField<T>> createState() => _QuirkNumberFieldState<T>();
}

class _QuirkNumberFieldState<T extends num>
    extends State<_QuirkNumberField<T>> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(_QuirkNumberField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue;
      if (_errorText != null) {
        setState(() => _errorText = null);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  T? _parse(String text) {
    if (T == double) {
      return double.tryParse(text) as T?;
    }
    return int.tryParse(text) as T?;
  }

  void _onChanged(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      if (_errorText != null) {
        setState(() => _errorText = null);
      }
      if (widget.allowBlank) {
        widget.onValue(null);
      }
      return;
    }
    if (trimmed == '-' ||
        (T == double && (trimmed == '.' || trimmed == '-.'))) {
      if (_errorText != null) {
        setState(() => _errorText = null);
      }
      return;
    }
    final parsed = _parse(trimmed);
    if (parsed == null) {
      setState(() => _errorText = UsbErgonomicsStrings.numberInvalid);
      return;
    }
    if ((widget.min != null && parsed < widget.min!) ||
        (widget.max != null && parsed > widget.max!) ||
        (widget.isValid != null && !widget.isValid!(parsed))) {
      setState(() => _errorText = UsbErgonomicsStrings.numberInvalid);
      return;
    }
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
    widget.onValue(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
      child: TextField(
        controller: _controller,
        enabled: widget.enabled,
        keyboardType: T == double
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.number,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: _errorText,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: _onChanged,
      ),
    );
  }
}
