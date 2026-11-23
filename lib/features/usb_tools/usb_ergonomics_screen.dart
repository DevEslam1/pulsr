// lib/features/usb_tools/usb_ergonomics_screen.dart
//
// USB ergonomics: what DAC is attached, which quirk profile applies to it, the
// editor for that profile, the three diagnostics actions and an exportable JSON
// preview.
//
// The screen owns only the draft profile and transient busy flags; the service
// owns the store, the status stream and every native call, so nothing here has
// to recover from a failed channel call.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/widgets/pulsr_empty_state.dart';
import '../../core/widgets/pulsr_progress.dart';
import 'usb_ergonomics_service.dart';
import 'usb_ergonomics_strings.dart';
import 'usb_quirk_editor.dart';
import 'usb_quirk_profile.dart';

/// Per-device USB quirk editor and diagnostics for problem DACs.
class UsbErgonomicsScreen extends StatefulWidget {
  /// Creates the screen.
  ///
  /// [onExportJson] is injected by the host (for example a share-sheet
  /// implementation); when null the export action is hidden and only the
  /// clipboard copy remains.
  const UsbErgonomicsScreen({
    super.key,
    required this.service,
    this.onExportJson,
  });

  /// State owner and native bridge.
  final UsbErgonomicsService service;

  /// Optional export handler that receives the profile JSON.
  final Future<void> Function(String json)? onExportJson;

  @override
  State<UsbErgonomicsScreen> createState() => _UsbErgonomicsScreenState();
}

class _UsbErgonomicsScreenState extends State<UsbErgonomicsScreen> {
  static const JsonEncoder _json = JsonEncoder.withIndent('  ');

  UsbQuirkProfile _draft = UsbQuirkProfile.defaults;
  String? _draftKey;
  bool _loading = true;
  bool _busy = false;

  UsbErgonomicsService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _service.start();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _syncDraft();
    });
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(_syncDraft);
  }

  /// Seeds the draft from the attached device when the device changes, without
  /// overwriting edits in progress on the same device.
  void _syncDraft() {
    final state = _service.state;
    final key = state.attached
        ? UsbQuirkProfile.deviceKey(
            state.deviceVid ?? 0,
            state.devicePid ?? 0,
          )
        : 'none';
    if (key == _draftKey) return;
    _draftKey = key;
    if (!state.attached) {
      _draft = UsbQuirkProfile.defaults;
      return;
    }
    final base = state.quirk ?? UsbQuirkProfile.defaults;
    _draft = base.copyWith(
      vid: state.deviceVid ?? 0,
      pid: state.devicePid ?? 0,
      label: state.deviceLabel ?? UsbErgonomicsStrings.unknownDevice,
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _service.saveQuirk(_draft);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(
      ok ? UsbErgonomicsStrings.saved : UsbErgonomicsStrings.saveFailed,
      isError: !ok,
    );
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _service.deleteQuirk();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _draftKey = null;
      _syncDraft();
    });
    _snack(
      ok ? UsbErgonomicsStrings.deleted : UsbErgonomicsStrings.deleteFailed,
      isError: !ok,
    );
  }

  Future<void> _probe() async {
    if (_busy) return;
    setState(() => _busy = true);
    final mbps = await _service.probeBusSpeed();
    if (!mounted) return;
    setState(() => _busy = false);
    if (mbps == null) {
      _snack(UsbErgonomicsStrings.busSpeedUnavailable, isError: true);
    }
  }

  Future<void> _resetAlt() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _service.resetAltSetting();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _snack(UsbErgonomicsStrings.resetAltFailed, isError: true);
    }
  }

  Future<void> _copyJson() async {
    await Clipboard.setData(ClipboardData(text: _draftJson));
    if (!mounted) return;
    _snack(UsbErgonomicsStrings.copied);
  }

  Future<void> _exportJson() async {
    final handler = widget.onExportJson;
    if (handler == null) return;
    await handler(_draftJson);
  }

  String get _draftJson => _json.convert(_draft.toJson());

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? context.palette.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _service.state;
    return Scaffold(
      appBar: AppBar(
        title: Text(UsbErgonomicsStrings.screenTitle),
        actions: <Widget>[
          _SemIconButton(
            tooltip: UsbErgonomicsStrings.copyTooltip,
            icon: Icons.copy_all_rounded,
            onPressed: _copyJson,
          ),
          if (widget.onExportJson != null)
            _SemIconButton(
              tooltip: UsbErgonomicsStrings.exportTooltip,
              icon: Icons.ios_share_rounded,
              onPressed: () => unawaited(_exportJson()),
            ),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const PulsrProgressBar(height: 2)
            : state.attached
                ? _buildContent(context, state)
                : PulsrEmptyState(
                    icon: Icons.usb_off_rounded,
                    title: UsbErgonomicsStrings.noDeviceTitle,
                    subtitle: UsbErgonomicsStrings.noDeviceSubtitle,
                    primaryActionLabel: UsbErgonomicsStrings.refreshAction,
                    primaryActionIcon: Icons.refresh_rounded,
                    onPrimaryAction: () => unawaited(_service.refresh()),
                  ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ErgonomicsState state) {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      children: <Widget>[
        _DeviceSummary(state: state),
        const SizedBox(height: AppSpacing.lg),
        _SectionHeader(UsbErgonomicsStrings.sectionQuirks),
        const SizedBox(height: AppSpacing.xs),
        UsbQuirkEditor(
          profile: _draft,
          enabled: !_busy,
          onChanged: (next) => setState(() => _draft = next),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: _busy ? null : () => unawaited(_save()),
          icon: const Icon(Icons.save_rounded),
          label: Text(UsbErgonomicsStrings.saveAction),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => unawaited(_delete()),
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(UsbErgonomicsStrings.deleteAction),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionHeader(UsbErgonomicsStrings.sectionDiagnostics),
        const SizedBox(height: AppSpacing.xs),
        _DiagnosticsCard(
          state: state,
          busy: _busy,
          onProbe: () => unawaited(_probe()),
          onResetAlt: () => unawaited(_resetAlt()),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionHeader(UsbErgonomicsStrings.sectionJson),
        const SizedBox(height: AppSpacing.xs),
        _JsonPreview(json: _draftJson),
      ],
    );
  }
}

/// Device name, ids and the profile that is actually in force.
class _DeviceSummary extends StatelessWidget {
  const _DeviceSummary({required this.state});

  final ErgonomicsState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final vid = state.deviceVid;
    final pid = state.devicePid;
    final quirk = state.quirk;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceContainerHigh,
        borderRadius: AppRadii.r18All,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.usb_rounded, color: p.accent, size: AppSpacing.lg),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  state.deviceLabel ?? UsbErgonomicsStrings.unknownDevice,
                  style: text.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (vid != null && pid != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              UsbErgonomicsStrings.ids(vid, pid),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.label,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            UsbErgonomicsStrings.activeProfileLabel,
            style: TextStyle(
              color: p.textTertiary,
              fontSize: AppFontSize.caption,
              letterSpacing: AppTracking.overline,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            quirk == null
                ? UsbErgonomicsStrings.noProfileStored
                : quirk.describe(),
            style: TextStyle(
              color: p.textPrimary,
              fontSize: AppFontSize.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Probe / HID status / alt-setting reset.
class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.state,
    required this.busy,
    required this.onProbe,
    required this.onResetAlt,
  });

  final ErgonomicsState state;
  final bool busy;
  final VoidCallback onProbe;
  final VoidCallback onResetAlt;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final mbps = state.busSpeedMbps;
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
          OutlinedButton.icon(
            onPressed: busy ? null : onProbe,
            icon: const Icon(Icons.speed_rounded),
            label: Text(UsbErgonomicsStrings.probeAction),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            mbps == null
                ? UsbErgonomicsStrings.busSpeedUnknown
                : UsbErgonomicsStrings.busSpeed(mbps),
            style: text.labelMedium?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            UsbErgonomicsStrings.hidStatusLabel,
            style: text.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            state.hid.describe(),
            style: TextStyle(
              color: state.hid.claimed ? p.success : p.textSecondary,
              fontSize: AppFontSize.bodySmall,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: busy ? null : onResetAlt,
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(UsbErgonomicsStrings.resetAltAction),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            ),
          ),
          if (state.lastError != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.lastError!,
              style: TextStyle(
                color: p.error,
                fontSize: AppFontSize.caption,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Read-only JSON preview of the draft profile.
class _JsonPreview extends StatelessWidget {
  const _JsonPreview({required this.json});

  final String json;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r12All,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SelectableText(
            json,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: AppFontSize.label,
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            UsbErgonomicsStrings.jsonHint,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: TextStyle(
          color: context.palette.textPrimary,
          fontSize: AppFontSize.body,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Icon button with a tooltip and a single explicit semantics node.
class _SemIconButton extends StatelessWidget {
  const _SemIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
