// lib/features/settings/presentation/widgets/cast_section.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../domain/services/cast_service.dart';
import '../../../player/cubit/player_cubit.dart';
import 'settings_section.dart';

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

  bool get _isAndroid => PlatformCapabilities.isAndroid;

  @override
  void initState() {
    super.initState();
    if (!_isAndroid) return;
    _init();
  }

  Future<void> _init() async {
    final sdk = await _service.isSessionAvailable();
    if (!mounted) return;
    setState(() => _sdk = sdk);
    if (sdk) {
      _routeSub = _service.routesStream.listen((r) {
        if (mounted) setState(() => _routes = r);
      });
      _sessionSub = _service.sessionStream.listen((s) {
        if (mounted) setState(() => _session = s);
      });
      await _service.startSessionDiscovery();
    } else {
      _deviceSub = _service.devicesStream.listen((d) {
        if (mounted) setState(() => _devices = d);
      });
      final supported = await _service.isSupported();
      if (supported) await _service.startDiscovery();
    }
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
    final song = context.read<PlayerCubit>().state.currentSong;
    if (song == null) {
      _snack('Nothing is playing to cast');
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
          ? 'Casting "${song.title}"'
          : (result.error ?? 'Cast failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _fallbackCast(CastDevice d) async {
    final result = await _service.castTo(d.id);
    _snack(result.success
        ? 'Casting to ${d.name}'
        : (result.message ?? 'Cast failed'));
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroid) return const SizedBox.shrink();

    final p = context.palette;
    final textSecondary =
        Theme.of(context).textTheme.bodySmall?.color ?? p.textSecondary;

    return SettingsSection(
      icon: Icons.cast_rounded,
      title: 'Google Cast',
      children: [
        if (_sdk) ...[
          if (_session.connected) ...[
            ListTile(
              leading: const Icon(Icons.cast_connected_rounded),
              title: Text(_session.deviceName ?? context.l10n.castDevice),
              subtitle: Text(
                _session.playing ? 'Playing on Cast' : 'Connected',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _castCurrent,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(context.l10n.castCurrentTrack),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async => _service.disconnect(),
                    child: const Text('Stop'),
                  ),
                ],
              ),
            ),
          ] else if (_routes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 18, color: textSecondary),
                  const SizedBox(width: 12),
                  Text('Scanning for Cast devices…',
                      style: TextStyle(fontSize: 13, color: textSecondary)),
                ],
              ),
            )
          else
            ..._routes.map(
              (r) => ListTile(
                leading: const Icon(Icons.cast_rounded),
                title: Text(r.name),
                trailing: r.selected
                    ? const Icon(Icons.check_circle_rounded)
                    : null,
                onTap: _busy ? null : () => _connect(r),
              ),
            ),
        ] else ...[
          if (_devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 18, color: textSecondary),
                  const SizedBox(width: 12),
                  Text('Scanning for Cast devices…',
                      style: TextStyle(fontSize: 13, color: textSecondary)),
                ],
              ),
            )
          else
            ..._devices.map(
              (d) => ListTile(
                leading: const Icon(Icons.cast_connected_rounded),
                title: Text(d.name),
                subtitle: Text(
                  d.model.isNotEmpty ? d.model : d.host,
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
                onTap: () => _fallbackCast(d),
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            _sdk
                ? 'Uses Google\'s Default Media Receiver. Local files are served '
                    'over your LAN; remote artwork/URLs are cast directly.'
                : 'Cast sessions require the Play Services Cast SDK (only in the '
                    'dev/ytm builds). Device discovery is shown here.',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
        ),
      ],
    );
  }
}
