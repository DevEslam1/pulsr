// lib/features/usb_tools/usb_quirk_editor.dart
//
// The per-device quirk form. Only settings with a real consumer are rendered:
// the HID consumer-control claim. It is presentation only — it hands a new
// [UsbQuirkProfile] to `onChanged` and never touches storage or the platform
// channel, so it can be exercised without a device.
//
// The switch sits on a >= 48 dp target and carries an explicit [Semantics] node
// (label, hint, toggled state) because a switch tile's default semantics omit
// the surrounding explanation.

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
