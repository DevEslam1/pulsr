// lib/features/diagnostics/diagnostics_screen.dart
//
// On-device support view: what output device is active, which DSP stages and
// output paths are live, whether safe mode tripped, and a one-tap export of the
// redacted bundle. The screen only reads services, it never touches the engine.

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/di/injection.dart';
import '../../core/errors/app_error.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/error_logger.dart';
import '../../core/widgets/pulsr_empty_state.dart';
import '../../core/widgets/pulsr_progress.dart';
import '../settings/cubit/settings_cubit.dart';
import 'diagnostics_bundle_service.dart';
import 'diagnostics_strings.dart';
import 'safe_mode_controller.dart';

/// Shows the collected diagnostics, the safe-mode state and the export actions.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    this.bundleService,
    this.safeMode,
    this.deviceLabel,
    this.deviceKey,
    this.selfTest,
  });

  /// Builds and exports the bundle.
  final DiagnosticsBundleService? bundleService;

  /// Tracks and clears safe mode for the active device.
  final SafeModeController? safeMode;

  /// Human label of the active output device.
  final String? Function()? deviceLabel;

  /// Stable key of the active output device; defaults to [deviceLabel].
  final String Function()? deviceKey;

  /// Optional replacement for the built-in self test.
  final Future<String> Function()? selfTest;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  DiagnosticsBundle? _bundle;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _selfTestMessage;
  bool _safeModeActive = false;
  int _safeModeFailures = 0;
  String? _safeModeReason;
  DiagnosticsBundleService? _localBundleService;
  SafeModeController? _localSafeMode;

  DiagnosticsBundleService get _effectiveBundleService {
    final s = widget.bundleService ?? _localBundleService;
    if (s == null) {
      throw StateError('DiagnosticsBundleService not initialized');
    }
    return s;
  }

  SafeModeController? get _effectiveSafeMode {
    if (widget.safeMode != null) return widget.safeMode;
    if (_localSafeMode != null) return _localSafeMode;
    return getIt.isRegistered<SafeModeController>()
        ? getIt<SafeModeController>()
        : null;
  }

  @override
  void initState() {
    super.initState();
    if (_effectiveSafeMode != null) {
      _syncSafeMode();
    }
    _refresh();
  }

  static Map<String, Object?> _defaultOutputDeviceSnapshot() {
    if (!getIt.isRegistered<SettingsCubit>()) {
      return const {'name': 'Unknown output device', 'type': 'unknown'};
    }
    final device = getIt<SettingsCubit>().state.currentOutputDevice;
    if (device == null) {
      return const {'name': 'Unknown output device', 'type': 'unknown'};
    }
    return {
      'name': device.deviceName,
      'type': device.isUsb
          ? 'usb'
          : device.isBluetooth
              ? 'bluetooth'
              : 'wired',
      'sampleRate': device.sampleRate,
      'bitDepth': device.bitDepth,
      'bitPerfect': device.isBitPerfectActive,
    };
  }

  String? _resolvedDeviceLabel() {
    final explicit = widget.deviceLabel?.call();
    if (explicit != null && explicit.trim().isNotEmpty) return explicit;
    if (getIt.isRegistered<SettingsCubit>()) {
      final name = getIt<SettingsCubit>().state.currentOutputDevice?.deviceName;
      if (name != null && name.trim().isNotEmpty) return name;
    }
    return null;
  }

  String _currentDeviceKey() {
    final explicit = widget.deviceKey?.call();
    if (explicit != null && explicit.trim().isNotEmpty) return explicit;
    final label = _resolvedDeviceLabel();
    if (label != null && label.trim().isNotEmpty) return label;
    return 'default';
  }

  void _syncSafeMode() {
    final sm = _effectiveSafeMode;
    if (sm == null) return;
    final key = _currentDeviceKey();
    _safeModeActive = sm.isFallbackActive(key);
    _safeModeFailures = sm.consecutiveFailures(key);
    _safeModeReason = sm.lastFailureReason(key);
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if ((widget.bundleService == null && _localBundleService == null) ||
          (widget.safeMode == null && _localSafeMode == null)) {
        final prefs = await SharedPreferences.getInstance();
        _localSafeMode ??= getIt.isRegistered<SafeModeController>()
            ? getIt<SafeModeController>()
            : SafeModeController(prefs: prefs);
        _localBundleService ??= DiagnosticsBundleService(
          prefs: prefs,
          outputDevice: _defaultOutputDeviceSnapshot,
        );
        _syncSafeMode();
      }
      final bundle = await _effectiveBundleService.build();
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _loading = false;
        _syncSafeMode();
      });
    } catch (e, st) {
      ErrorLogger.log(
        'Building the diagnostics bundle failed',
        error: e,
        stackTrace: st,
        category: 'DiagnosticsScreen',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            e is AppError ? e.userMessage : DiagnosticsStrings.errorSubtitle;
      });
    }
  }

  @override
  void dispose() {
    // Never leave a redacted bundle behind if the user leaves the screen
    // without sharing, or if the share future completed just before teardown.
    unawaited(widget.bundleService?.cleanupExport() ??
        _localBundleService?.cleanupExport() ??
        Future.value());
    super.dispose();
  }

  Future<void> _exportBundle() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final errorColor = context.palette.error;
    setState(() => _busy = true);
    try {
      final files = await _effectiveBundleService.export(bundle: _bundle);
      await SharePlus.instance.share(
        ShareParams(
          files: files,
          text: DiagnosticsStrings.shareText,
        ),
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Exporting the diagnostics bundle failed',
        error: e,
        stackTrace: st,
        category: 'DiagnosticsScreen',
      );
      messenger?.showSnackBar(
        SnackBar(
          content: Text(DiagnosticsStrings.exportFailed),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      // The bundle contains paths and preferences; do not let it accumulate in
      // the cache directory after the share sheet has it.
      await _effectiveBundleService.cleanupExport();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterSafeMode() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final errorColor = context.palette.error;
    setState(() => _busy = true);
    try {
      await _effectiveSafeMode?.applyFallback(_currentDeviceKey());
      if (!mounted) return;
      setState(_syncSafeMode);
      messenger?.showSnackBar(
        SnackBar(content: Text(DiagnosticsStrings.safeModeEntered)),
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Entering safe mode failed',
        error: e,
        stackTrace: st,
        category: 'DiagnosticsScreen',
      );
      messenger?.showSnackBar(
        SnackBar(
          content: Text(DiagnosticsStrings.safeModeResetFailed),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exitSafeMode() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final errorColor = context.palette.error;
    setState(() => _busy = true);
    try {
      await _effectiveSafeMode?.reset(_currentDeviceKey());
      if (!mounted) return;
      setState(_syncSafeMode);
      messenger?.showSnackBar(
        SnackBar(content: Text(DiagnosticsStrings.safeModeExited)),
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Exiting safe mode failed',
        error: e,
        stackTrace: st,
        category: 'DiagnosticsScreen',
      );
      messenger?.showSnackBar(
        SnackBar(
          content: Text(DiagnosticsStrings.safeModeResetFailed),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSelfTest() async {
    final runner = widget.selfTest ?? _defaultSelfTest;
    setState(() {
      _busy = true;
      _selfTestMessage = DiagnosticsStrings.selfTestRunning;
    });
    try {
      final message = await runner();
      if (!mounted) return;
      setState(() => _selfTestMessage = message);
    } catch (e, st) {
      ErrorLogger.log(
        'Diagnostics self test failed',
        error: e,
        stackTrace: st,
        category: 'DiagnosticsScreen',
      );
      if (!mounted) return;
      setState(
        () => _selfTestMessage = DiagnosticsStrings.selfTestFailed(
          e is AppError ? e.userMessage : 'unknown error',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _defaultSelfTest() async {
    final watch = Stopwatch()..start();
    final bundle = await _effectiveBundleService.build();
    watch.stop();
    final sections = <String>[
      if (bundle.app.isNotEmpty) 'app',
      if (bundle.outputDevice.isNotEmpty) 'device',
      if (bundle.dspStages.isNotEmpty) 'dsp',
      if (bundle.outputPathCounters.isNotEmpty) 'paths',
      if (bundle.preferences.isNotEmpty) 'prefs',
    ];
    return DiagnosticsStrings.selfTestPassed(
      sections.length,
      watch.elapsedMilliseconds,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(DiagnosticsStrings.screenTitle),
        actions: <Widget>[
          IconButton(
            tooltip: DiagnosticsStrings.refreshTooltip,
            onPressed: _loading ? null : () => _refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(width: 160, child: PulsrProgressBar()),
      );
    }
    if (_error != null || _bundle == null) {
      return PulsrEmptyState(
        icon: Icons.error_outline_rounded,
        title: DiagnosticsStrings.errorTitle,
        subtitle: _error ?? DiagnosticsStrings.errorSubtitle,
        primaryActionLabel: DiagnosticsStrings.retry,
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: () => _refresh(),
      );
    }
    final bundle = _bundle!;
    return ListView(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      children: <Widget>[
        _SummaryCard(bundle: bundle, deviceLabel: _resolvedDeviceLabel),
        const SizedBox(height: AppSpacing.sm),
        _CountersCard(bundle: bundle),
        const SizedBox(height: AppSpacing.sm),
        _DspCard(bundle: bundle),
        const SizedBox(height: AppSpacing.sm),
        _SafeModeCard(
          active: _safeModeActive,
          failures: _safeModeFailures,
          reason: _safeModeReason,
          busy: _busy,
          onEnter: _enterSafeMode,
          onExit: _exitSafeMode,
        ),
        const SizedBox(height: AppSpacing.sm),
        _LogCard(lines: bundle.logLines),
        const SizedBox(height: AppSpacing.md),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        _A11yButton(
          label: DiagnosticsStrings.exportAction,
          enabled: !_busy,
          child: FilledButton.icon(
            onPressed: _busy ? null : _exportBundle,
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(DiagnosticsStrings.exportAction),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _A11yButton(
          label: DiagnosticsStrings.selfTestAction,
          enabled: !_busy,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _runSelfTest,
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: Text(DiagnosticsStrings.selfTestAction),
          ),
        ),
        if (_selfTestMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _selfTestMessage!,
            style: TextStyle(
              fontSize: AppFontSize.bodySmall,
              color: context.palette.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.bundle, required this.deviceLabel});

  final DiagnosticsBundle bundle;
  final String? Function()? deviceLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final version = '${bundle.app['appVersion'] ?? '?'}';
    final platform = '${bundle.app['platform'] ?? '?'}';
    final mode = '${bundle.app['buildMode'] ?? '?'}';
    final device = deviceLabel?.call();
    final deviceText = device == null || device.trim().isEmpty
        ? DiagnosticsStrings.deviceUnknown
        : device;
    final usb = bundle.usb.isEmpty || bundle.usb['status'] == 'unavailable'
        ? DiagnosticsStrings.usbUnavailable
        : '${bundle.usb.length} USB fields reported';
    return _Card(
      title: DiagnosticsStrings.deviceTitle,
      icon: Icons.speaker_rounded,
      accentColor: p.accent,
      children: <Widget>[
        _Row(label: 'Device', value: deviceText),
        _Row(
          label: 'App',
          value: DiagnosticsStrings.appSummary(version, platform, mode),
        ),
        _Row(label: 'USB', value: usb),
        _Row(
          label: 'Built',
          value: _formatTimestamp(bundle.generatedAt),
          muted: true,
        ),
      ],
    );
  }
}

class _CountersCard extends StatelessWidget {
  const _CountersCard({required this.bundle});

  final DiagnosticsBundle bundle;

  @override
  Widget build(BuildContext context) {
    final reported = bundle.outputPathCounters['reported'] == true;
    final paths = <String, Map<String, Object?>>{};
    final raw = bundle.outputPathCounters['paths'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is Map) {
          paths['${entry.key}'] = Map<String, Object?>.from(value);
        }
      }
    }
    return _Card(
      title: DiagnosticsStrings.pathsTitle,
      icon: Icons.speed_rounded,
      children: <Widget>[
        for (final entry in paths.entries)
          _Row(
            label: entry.key,
            value: DiagnosticsStrings.counterSummary(
              _asInt(entry.value['xruns']),
              _asInt(entry.value['underruns']),
            ),
          ),
        if (paths.isEmpty)
          _Row(label: 'paths', value: DiagnosticsStrings.pathsUnavailable),
        _Row(
          label: 'source',
          value: DiagnosticsStrings.countersReported(reported),
          muted: true,
        ),
        if (!reported)
          Text(
            DiagnosticsStrings.pathsUnavailable,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: context.palette.textTertiary,
            ),
          ),
      ],
    );
  }
}

class _DspCard extends StatelessWidget {
  const _DspCard({required this.bundle});

  final DiagnosticsBundle bundle;

  @override
  Widget build(BuildContext context) {
    final enabled = bundle.dspStages
        .where((stage) => stage['enabled'] == true)
        .map((stage) => '${stage['stage']}')
        .toList(growable: false);
    return _Card(
      title: DiagnosticsStrings.dspTitle,
      icon: Icons.graphic_eq_rounded,
      children: <Widget>[
        _Row(
          label: 'stages',
          value: DiagnosticsStrings.dspSummary(
            enabled.length,
            bundle.dspStages.length,
          ),
        ),
        Text(
          enabled.isEmpty ? DiagnosticsStrings.dspNone : enabled.join(', '),
          style: TextStyle(
            fontSize: AppFontSize.bodySmall,
            color: context.palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _SafeModeCard extends StatelessWidget {
  const _SafeModeCard({
    required this.active,
    required this.failures,
    required this.reason,
    required this.busy,
    required this.onEnter,
    required this.onExit,
  });

  final bool active;
  final int failures;
  final String? reason;
  final bool busy;
  final VoidCallback onEnter;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = active ? p.warning : p.success;
    return _Card(
      title: DiagnosticsStrings.safeModeTitle,
      icon: Icons.shield_outlined,
      accentColor: tone,
      children: <Widget>[
        _Row(
          label: 'status',
          value: active
              ? DiagnosticsStrings.safeModeOn
              : DiagnosticsStrings.safeModeOff,
        ),
        _Row(
          label: 'failures',
          value: DiagnosticsStrings.safeModeFailures(failures),
        ),
        if (reason != null) _Row(label: 'reason', value: reason!, muted: true),
        Text(
          DiagnosticsStrings.safeModeThreshold(
            SafeModeController.failureThreshold,
          ),
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: p.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _A11yButton(
          label: active
              ? DiagnosticsStrings.safeModeExit
              : DiagnosticsStrings.safeModeEnter,
          enabled: !busy,
          child: OutlinedButton.icon(
            onPressed: busy ? null : (active ? onExit : onEnter),
            icon: Icon(
              active ? Icons.restart_alt_rounded : Icons.shield_rounded,
            ),
            label: Text(
              active
                  ? DiagnosticsStrings.safeModeExit
                  : DiagnosticsStrings.safeModeEnter,
            ),
          ),
        ),
      ],
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tail = lines.length <= 6 ? lines : lines.sublist(lines.length - 6);
    return _Card(
      title: DiagnosticsStrings.logsTitle,
      icon: Icons.article_outlined,
      children: <Widget>[
        if (tail.isEmpty)
          Text(
            DiagnosticsStrings.logsEmpty,
            style: TextStyle(
              fontSize: AppFontSize.bodySmall,
              color: p.textSecondary,
            ),
          )
        else
          for (final line in tail)
            Text(
              line,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                height: 1.35,
                color: p.textSecondary,
                fontFamily: 'monospace',
                fontFamilyFallback: const <String>['Menlo', 'Courier'],
              ),
            ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.children,
    this.accentColor,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: accentColor ?? p.accent),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: TextStyle(
                  fontSize: AppFontSize.bodyLarge,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: p.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: AppFontSize.bodySmall,
                color: muted ? p.textSecondary : p.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Exposes one explicit accessibility label per control.
class _A11yButton extends StatelessWidget {
  const _A11yButton({
    required this.label,
    required this.child,
    this.enabled = true,
  });

  final String label;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      enabled: enabled,
      excludeSemantics: true,
      child: child,
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} $hour:$minute:$second';
}
