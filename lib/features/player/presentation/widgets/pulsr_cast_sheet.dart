// lib/features/player/presentation/widgets/pulsr_cast_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../domain/services/cast_service.dart';
import '../../cubit/player_cubit.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class PulsrCastSheet extends StatefulWidget {
  const PulsrCastSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => const PulsrCastSheet(),
    );
  }

  @override
  State<PulsrCastSheet> createState() => _PulsrCastSheetState();
}

class _PulsrCastSheetState extends State<PulsrCastSheet> {
  final CastService _service = CastService();
  StreamSubscription<List<CastDevice>>? _deviceSub;
  StreamSubscription<List<CastRoute>>? _routeSub;
  StreamSubscription<CastSessionStatus>? _sessionSub;

  List<CastDevice> _devices = const [];
  List<CastRoute> _routes = const [];
  CastSessionStatus _session = CastSessionStatus.unavailable;
  bool _sdk = false;
  bool _busy = false;
  bool _scanning = false;

  bool get _isAndroid => PlatformCapabilities.isAndroid;

  @override
  void initState() {
    super.initState();
    if (_isAndroid) {
      _init();
    }
  }

  Future<void> _init() async {
    setState(() => _scanning = true);
    final sdk = await _service.isSessionAvailable();
    if (!mounted) return;
    setState(() {
      _sdk = sdk;
      if (sdk) {
        _routes = _service.routes;
        _session = _service.sessionStatus;
      } else {
        _devices = _service.devices;
      }
    });

    if (sdk) {
      _routeSub = _service.routesStream.listen((r) {
        if (mounted) {
          setState(() {
            _routes = r;
            _scanning = false;
          });
        }
      });
      _sessionSub = _service.sessionStream.listen((s) {
        if (mounted) setState(() => _session = s);
      });
      await _service.startSessionDiscovery();
    } else {
      _deviceSub = _service.devicesStream.listen((d) {
        if (mounted) {
          setState(() {
            _devices = d;
            _scanning = false;
          });
        }
      });
      final supported = await _service.isSupported();
      if (supported) await _service.startDiscovery();
    }

    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _scanning) {
        setState(() => _scanning = false);
      }
    });
  }

  Future<void> _rescan() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _scanning = true);
    if (_sdk) {
      await _service.stopSessionDiscovery();
      await _service.startSessionDiscovery();
    } else {
      await _service.stopDiscovery();
      await _service.startDiscovery();
    }
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _scanning) {
        setState(() => _scanning = false);
      }
    });
  }

  @override
  void dispose() {
    _deviceSub?.cancel();
    _routeSub?.cancel();
    _sessionSub?.cancel();
    unawaited(_service.stopSessionDiscovery());
    unawaited(_service.stopDiscovery());
    super.dispose();
  }

  String _mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/mp4';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.ogg') || lower.endsWith('.opus')) return 'audio/ogg';
    return 'audio/mpeg';
  }

  Future<void> _connect(CastRoute route) async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      if (route.selected || _session.connected) {
        await _service.disconnect();
      } else {
        await _service.connect(route.id);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _castCurrentSong() async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    final l10n = context.l10n;
    final song = context.read<PlayerCubit>().state.currentSong;
    if (song == null) {
      _showToast(l10n.settingsNothingToCast);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _service.castLocalFile(
        path: song.path,
        title: song.title,
        artist: song.artist,
        album: song.album,
        artwork: song.artworkUri,
        mime: _mimeFor(song.path),
      );
      _showToast(result.success
          ? l10n.settingsCastingTitle(song.title)
          : (result.error ?? l10n.settingsCastFailed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroid) {
      final p = context.palette;
      return SafeArea(
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.lg, AppSpacing.s20, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cast_rounded, size: 40, color: p.textTertiary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.settingsGoogleCast,
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.title,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.l10n.castAndroidOnly,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
              ),
            ],
          ),
        ),
      );
    }

    final p = context.palette;
    final l10n = context.l10n;
    final isConnected = _session.connected;
    final hasDevices = _sdk ? _routes.isNotEmpty : _devices.isNotEmpty;

    return SafeArea(
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, AppSpacing.lg),
        constraints: BoxConstraints(
          maxWidth: Adaptive.sheetConstraints(context).maxWidth,
        ),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: p.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppRadii.r2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s10),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? p.accent.withValues(alpha: 0.20)
                        : p.surfaceContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isConnected
                        ? Icons.cast_connected_rounded
                        : Icons.cast_rounded,
                    color: isConnected ? p.accent : p.textPrimary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.s14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.settingsGoogleCast,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        isConnected
                            ? (_session.deviceName ?? l10n.castConnected)
                            : (_scanning
                                ? l10n.scanningCastDevices
                                : l10n.castDevice),
                        style: TextStyle(
                          color: isConnected ? p.accent : p.textSecondary,
                          fontSize: AppFontSize.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: _scanning
                      ? SizedBox(width: AppSpacing.s18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: p.accent,
                          ),
                        )
                      : Icon(Icons.refresh_rounded, color: p.textSecondary),
                  tooltip: l10n.scanningCastDevices,
                  onPressed: _scanning || _busy ? null : _rescan,
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.s18),

            // mDNS direct-device fallback: honest capability note.
            if (!_sdk && !isConnected) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.textTertiary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.r10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: p.textTertiary),
                    const SizedBox(width: AppSpacing.s6),
                    Expanded(
                      child: Text(
                        context.l10n.castDirectDeviceMode,
                        style: TextStyle(
                            fontSize: AppFontSize.label, color: p.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            // Connected Session Controls Card
            if (isConnected) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.r18),
                  border: Border.all(color: p.accent.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _session.deviceName ?? l10n.castDevice,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.bodyLarge,
                                  color: p.textPrimary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s2),
                              Text(
                                _session.playing
                                    ? l10n.castConnected
                                    : l10n.castDevice,
                                style: TextStyle(
                                  fontSize: AppFontSize.label,
                                  color: p.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : () => _service.disconnect(),
                          icon: const Icon(Icons.stop_circle_outlined, size: 18),
                          label: Text(l10n.disconnect),
                          style: TextButton.styleFrom(
                            foregroundColor: p.error,
                            padding: const EdgeInsets.symmetric(

                                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: p.onAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        ),
                        onPressed: _busy ? null : _castCurrentSong,
                        icon: const Icon(Icons.play_circle_filled_rounded,
                            size: 20),
                        label: Text(
                          l10n.castCurrentTrack,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Device list
            if (!hasDevices && !_scanning) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.speaker_group_outlined,
                          size: 44, color: p.textTertiary),
                      const SizedBox(height: AppSpacing.s10),
                      Text(
                        l10n.scanningCastDevices,
                        style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.body),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: _rescan,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(l10n.scanningCastDevices),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Text(
                l10n.castDevice.toUpperCase(),
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  letterSpacing: AppTracking.wide,
                  fontWeight: FontWeight.w800,
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Container(
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppRadii.r18),
                  border: Border.all(color: p.hairline),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.r18),
                  child: Column(
                    children: [
                      if (_sdk) ...[
                        for (int i = 0; i < _routes.length; i++) ...[
                          if (i > 0)
                            Divider(
                                height: 1,
                                thickness: 1,
                                color: p.hairline.withValues(alpha: 0.5)),
                          ListTile(
                            leading: Icon(
                              _routes[i].selected
                                  ? Icons.cast_connected_rounded
                                  : Icons.tv_rounded,
                              color: _routes[i].selected
                                  ? p.accent
                                  : p.textPrimary,
                            ),
                            title: Text(
                              _routes[i].name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _routes[i].selected
                                    ? p.accent
                                    : p.textPrimary,
                              ),
                            ),
                            trailing: _routes[i].selected
                                ? Icon(Icons.check_circle_rounded,
                                    color: p.accent, size: 20)
                                : null,
                            onTap: _busy ? null : () => _connect(_routes[i]),
                          ),
                        ],
                      ] else ...[
                        for (int i = 0; i < _devices.length; i++) ...[
                          if (i > 0)
                            Divider(
                                height: 1,
                                thickness: 1,
                                color: p.hairline.withValues(alpha: 0.5)),
                          ListTile(
                            leading: Icon(Icons.cast_rounded, color: p.textPrimary),
                            title: Text(
                              _devices[i].name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: p.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              _devices[i].model.isNotEmpty
                                  ? _devices[i].model
                                  : _devices[i].host,
                              style: TextStyle(
                                  color: p.textSecondary, fontSize: AppFontSize.label),
                            ),
                            onTap: _busy
                                ? null
                                : () async {
                                    setState(() => _busy = true);
                                    try {
                                      await _service.castTo(_devices[i].id);
                                    } finally {
                                      if (mounted) {
                                        setState(() => _busy = false);
                                      }
                                    }
                                  },
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
