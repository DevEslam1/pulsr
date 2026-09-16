// lib/features/settings/presentation/widgets/cast_section.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../core/widgets/pulsr_pressable.dart';
import '../../../../domain/services/cast_service.dart';
import '../../../player/cubit/player_cubit.dart';
import 'settings_section.dart';
import 'settings_tiles.dart';

/// Google Cast control.
///
/// When the Play Services Cast framework is available (dev/ytm builds) this
/// lists MediaRouter routes, starts/stops a session, and can cast the current
/// track (local files are bridged through a native HTTP server). Otherwise it
/// falls back to honest mDNS discovery only.
class CastSection extends StatefulWidget {
  const CastSection({super.key});

  @override
  State<CastSection> createState() => _CastSectionState();
}

class _CastSectionState extends State<CastSection> {
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
    if (!_isAndroid) return;
    _init();
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

    // Safety timeout for the scanning spinner
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _scanning) {
        setState(() => _scanning = false);
      }
    });
  }

  Future<void> _rescan() async {
    if (_busy) return;
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

  Future<void> _castCurrent() async {
    if (_busy) return;
    final l10n = context.l10n;
    final song = context.read<PlayerCubit>().state.currentSong;
    if (song == null) {
      _snack(l10n.settingsNothingToCast);
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
      _snack(result.success
          ? l10n.settingsCastingTitle(song.title)
          : (result.error ?? l10n.settingsCastFailed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _fallbackCast(CastDevice d) async {
    final l10n = context.l10n;
    final result = await _service.castTo(d.id);
    _snack(result.success
        ? l10n.settingsCastingTo(d.name)
        : (result.message ?? l10n.settingsCastFailed));
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroid) return const SizedBox.shrink();

    final p = context.palette;
    final l10n = context.l10n;

    return SettingsSection(
      icon: Icons.cast_rounded,
      title: l10n.settingsGoogleCast,
      subtitle: _session.connected
          ? (_session.deviceName ?? l10n.castConnected)
          : null,
      trailing: IconButton(
        icon: _scanning
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: p.accent,
                ),
              )
            : Icon(
                Icons.refresh_rounded,
                size: 19,
                color: p.textSecondary,
              ),
        tooltip: l10n.scanningCastDevices,
        visualDensity: VisualDensity.compact,
        onPressed: _scanning || _busy ? null : _rescan,
      ),
      children: [
        // Connected Session Banner
        if (_session.connected) ...[
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.accentContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppRadii.tile),
              border: Border.all(color: p.accent.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.cast_connected_rounded,
                          color: p.accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _session.deviceName ?? l10n.castDevice,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: p.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _session.playing
                                ? l10n.playingOnCast
                                : l10n.castConnected,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: p.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        context.l10n.settingsActiveBadge,
                        style: TextStyle(
                          color: p.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: p.onAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: _busy ? null : _castCurrent,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(
                          l10n.castCurrentTrack,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: p.hairline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                      onPressed:
                          _busy ? null : () async => _service.disconnect(),
                      child: Text(
                        l10n.stopCast,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          settingsCardDivider(p),
        ],

        // Routes or Devices list
        if (_sdk) ...[
          if (_routes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  if (_scanning)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: p.accent,
                      ),
                    )
                  else
                    Icon(Icons.search_rounded, size: 20, color: p.textTertiary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.scanningCastDevices,
                      style: TextStyle(fontSize: 13, color: p.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._routes.asMap().entries.map(
              (entry) {
                final i = entry.key;
                final r = entry.value;
                final isSelected = r.selected || (_session.connected && _session.deviceName == r.name);

                return Column(
                  children: [
                    if (i > 0) settingsCardDivider(p),
                    PulsrPressable(
                      pressedScale: 0.988,
                      onTap: _busy ? null : () => _connect(r),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 2),
                        leading: SettingsIconBox(
                          isSelected
                              ? Icons.cast_connected_rounded
                              : Icons.cast_rounded,
                        ),
                        title: Text(
                          r.name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            fontSize: 14.5,
                            color: isSelected ? p.accent : p.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          isSelected ? l10n.castConnected : l10n.castDevice,
                          style: TextStyle(
                            color: isSelected ? p.accent : p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        trailing: isSelected
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: p.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_rounded,
                                        size: 14, color: p.accent),
                                    const SizedBox(width: 4),
                                    Text(
                                      l10n.castConnected.toUpperCase(),
                                      style: TextStyle(
                                        color: p.accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Icon(
                                Icons.chevron_right_rounded,
                                color: p.textTertiary.withValues(alpha: 0.6),
                                size: 20,
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ] else ...[
          if (_devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  if (_scanning)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: p.accent,
                      ),
                    )
                  else
                    Icon(Icons.search_rounded, size: 20, color: p.textTertiary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.scanningCastDevices,
                      style: TextStyle(fontSize: 13, color: p.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._devices.asMap().entries.map(
              (entry) {
                final i = entry.key;
                final d = entry.value;

                return Column(
                  children: [
                    if (i > 0) settingsCardDivider(p),
                    PulsrPressable(
                      pressedScale: 0.988,
                      onTap: () => _fallbackCast(d),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 2),
                        leading: const SettingsIconBox(Icons.cast_rounded),
                        title: Text(
                          d.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                          ),
                        ),
                        subtitle: Text(
                          d.model.isNotEmpty ? d.model : d.host,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: p.textTertiary.withValues(alpha: 0.6),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],

        // Footnote info card
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: p.surfaceContainerHigh.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 15, color: p.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _sdk
                      ? l10n.settingsCastSdkDesc
                      : l10n.settingsCastNoSdkDesc,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: p.textTertiary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
