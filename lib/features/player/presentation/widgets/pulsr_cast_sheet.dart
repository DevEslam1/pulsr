// lib/features/player/presentation/widgets/pulsr_cast_sheet.dart
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_progress.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/services/cast_service.dart';
import '../../cubit/player_cubit.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/utils/pulsr_haptics.dart';

/// Whether [song] can be handed to a cast renderer: a real local file or a
/// downloaded YouTube track that already has a local path. Streaming rows
/// (YouTube, radio) and net-library files ([SongSource.remote]) have no file
/// the renderer can read, so they are filtered out.
bool isCastableLocalSong(SongsTableData song) {
  if (song.source != SongSource.local && song.isDownloaded != true) {
    return false;
  }
  final path = song.path;
  if (path.isEmpty) return false;
  final lower = path.toLowerCase();
  if (lower.startsWith('http') || lower.startsWith('ytmusic://')) {
    return false;
  }
  return true;
}

/// The castable slice of a player queue plus the offset the renderer starts at.
@immutable
class CastQueueSelection {
  const CastQueueSelection({
    required this.items,
    required this.startIndex,
    required this.startPositionMs,
  });

  /// Castable tracks in player-queue order.
  final List<SongsTableData> items;

  /// Index inside [items] the renderer must start on.
  final int startIndex;

  /// Playback offset for [startIndex].
  final int startPositionMs;

  bool get isEmpty => items.isEmpty;
}

/// Filters [queue] down to castable files and remaps the anchor.
///
/// [position] belongs to [currentSong] only. When that track is not castable
/// (a YouTube/radio row, a net-library file) the renderer would otherwise start
/// the first castable track at an offset from a different file, so the offset is
/// reset to zero and the anchor falls back to index 0.
CastQueueSelection selectCastableQueue({
  required List<SongsTableData> queue,
  SongsTableData? currentSong,
  Duration position = Duration.zero,
}) {
  final items = <SongsTableData>[];
  var startIndex = 0;
  var anchorFound = false;
  for (final song in queue) {
    if (!isCastableLocalSong(song)) continue;
    if (currentSong != null && song.id == currentSong.id) {
      startIndex = items.length;
      anchorFound = true;
    }
    items.add(song);
  }
  return CastQueueSelection(
    items: items,
    startIndex: items.isEmpty ? 0 : startIndex.clamp(0, items.length - 1),
    startPositionMs: anchorFound ? position.inMilliseconds : 0,
  );
}

class PulsrCastSheet extends StatefulWidget {
  const PulsrCastSheet({super.key});

  static Future<void> show(BuildContext context) {
    PulsrHaptics.lightImpact();
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
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
  bool _initialized = false;
  bool _ownsDiscovery = false;
  Timer? _scanTimeoutTimer;

  bool get _isAndroid => PlatformCapabilities.isAndroid;

  @override
  void initState() {
    super.initState();
    if (_isAndroid) {
      _volumeLoading = true;
      _init();
    }
  }

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;
    _ownsDiscovery = true;
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

    // AUDIT-FIX: Reflect the receiver's real volume or mark unknown with loading indicator
    final remoteVolume = await _service.getVolume();
    if (mounted) {
      setState(() {
        _volumeLoading = false;
        if (remoteVolume != null) {
          _castVolume = remoteVolume;
          _volumeUnknown = false;
        } else {
          _volumeUnknown = true;
        }
      });
    }

    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _scanning) {
        setState(() => _scanning = false);
      }
    });
  }

  Future<void> _rescan() async {
    if (_busy) return;
    PulsrHaptics.lightImpact();
    _ownsDiscovery = true;
    setState(() => _scanning = true);
    if (_sdk) {
      await _service.stopSessionDiscovery();
      await _service.startSessionDiscovery();
    } else {
      await _service.stopDiscovery();
      await _service.startDiscovery();
    }
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _scanning) {
        setState(() => _scanning = false);
      }
    });
  }

  @override
  void dispose() {
    _scanTimeoutTimer?.cancel();
    _deviceSub?.cancel();
    _routeSub?.cancel();
    _sessionSub?.cancel();
    if (_ownsDiscovery) {
      unawaited(_service.stopSessionDiscovery());
      unawaited(_service.stopDiscovery());
    }
    super.dispose();
  }

  /// B12: only real local files can be handed to a cast receiver. YT Music
  /// sentinels (`ytmusic://`) and HTTP streams are not castable.
  bool _isCastableLocal(SongsTableData song) => isCastableLocalSong(song);

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
    PulsrHaptics.selectionClick();
    setState(() => _busy = true);
    try {
      if (route.selected) {
        await _service.disconnect();
      } else {
        if (_session.connected) {
          await _service.disconnect();
        }
        await _service.connect(route.id);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    PulsrHaptics.selectionClick();
    setState(() => _busy = true);
    try {
      await _service.disconnect();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // AUDIT-FIX: Track volume fetch loading and unknown state
  double _castVolume = 1.0;
  bool _volumeLoading = false;
  bool _volumeUnknown = false;

  Future<void> _castCurrentQueue() async {
    if (_busy) return;
    PulsrHaptics.mediumImpact();
    final l10n = context.l10n;
    final playerState = context.read<PlayerCubit>().state;
    final queue = playerState.queue;
    if (queue.isEmpty) {
      if (playerState.currentSong != null) {
        await _castCurrentSong();
      } else {
        _showToast(context.l10n.settingsNothingToCast);
      }
      return;
    }
    // B12: filter to castable local files and remap the start index. The
    // start offset is only meaningful when the current track itself is cast.
    final selection = selectCastableQueue(
      queue: queue,
      currentSong: playerState.currentSong,
      position: playerState.position,
    );
    final castable = selection.items;
    if (selection.isEmpty) {
      _showToast(context.l10n.castNoLocalItems);
      return;
    }
    setState(() => _busy = true);
    try {
      final items = castable
          .map((s) => <String, dynamic>{
                'path': s.path,
                'title': s.title,
                'artist': s.artist,
                'album': s.album,
                'artwork': s.remoteArtworkUrl ?? s.artworkUri,
                'mime': _mimeFor(s.path),
              })
          .toList();
      final result = await _service.castQueue(
        queueItems: items,
        startIndex: selection.startIndex,
        startPositionMs: selection.startPositionMs,
      );
      _showToast(result.success
          ? l10n.settingsCastingQueueTo(_session.deviceName ?? l10n.castDefaultDevice)
          : (result.error ?? l10n.settingsCastFailed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _castCurrentSong() async {
    if (_busy) return;
    PulsrHaptics.mediumImpact();
    final l10n = context.l10n;
    final song = context.read<PlayerCubit>().state.currentSong;
    if (song == null) {
      _showToast(l10n.settingsNothingToCast);
      return;
    }
    if (!_isCastableLocal(song)) {
      _showToast(l10n.castNoLocalItems);
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
    PulsrToast.show(context, message: message);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroid) {
      final p = context.palette;
      return SafeArea(
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.s20, AppSpacing.lg, AppSpacing.s20, AppSpacing.xl),
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
                style: TextStyle(
                    color: p.textSecondary, fontSize: AppFontSize.bodySmall),
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
        padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, AppSpacing.lg),
        constraints: BoxConstraints(
          maxWidth: Adaptive.sheetConstraints(context).maxWidth,
        ),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
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
                  borderRadius: AppRadii.r2All,
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
                  constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget),
                  icon: _scanning
                      ? PulsrProgressBar.circular(
                          size: AppSpacing.s18,
                          strokeWidth: 2,
                          color: p.accent,
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
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.textTertiary.withValues(alpha: 0.12),
                  borderRadius: AppRadii.r10All,
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
                            fontSize: AppFontSize.label,
                            color: p.textSecondary),
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
                  borderRadius: AppRadii.r18All,
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
                          onPressed: _busy ? null : _disconnect,
                          icon:
                              const Icon(Icons.stop_circle_outlined, size: 18),
                          label: Text(l10n.disconnect),
                          style: TextButton.styleFrom(
                            foregroundColor: p.error,
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs),
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
                            borderRadius: AppRadii.r12All,
                          ),
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm),
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
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: p.textPrimary,
                          side: BorderSide(
                              color: p.accent.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadii.r12All,
                          ),
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs),
                        ),
                        onPressed: _busy ? null : _castCurrentQueue,
                        icon: const Icon(Icons.queue_music_rounded, size: 18),
                        label: Text(context.l10n.castEntireQueue,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    if (_session.title != null || _session.playing || _session.paused) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: AppRadii.r12All,
                          border: Border.all(color: p.hairline),
                        ),
                        child: Column(
                          children: [
                            if (_session.title != null) ...[
                              Text(
                                _session.title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary,
                                ),
                              ),
                              if (_session.artist != null)
                                Text(
                                  _session.artist!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppFontSize.label,
                                    color: p.textSecondary,
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.xxs),
                            ],
                            if (_session.durationMs > 0)
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  trackHeight: 3,
                                ),
                                child: Slider(
                                  value: _session.positionMs.toDouble().clamp(0.0, _session.durationMs.toDouble()),
                                  max: _session.durationMs.toDouble(),
                                  activeColor: p.accent,
                                  onChanged: (v) => _service.seek(Duration(milliseconds: v.round())),
                                ),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: context.l10n.previous,
                                  icon: const Icon(Icons.skip_previous_rounded),
                                  onPressed: _busy ? null : () => _service.previous(),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                IconButton(
                                  tooltip: _session.playing ? context.l10n.pause : context.l10n.play,
                                  iconSize: 36,
                                  color: p.accent,
                                  icon: Icon(_session.playing
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_filled_rounded),
                                  onPressed: _busy
                                      ? null
                                      : () => _session.playing ? _service.pause() : _service.play(),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                IconButton(
                                  tooltip: context.l10n.stopCast,
                                  icon: const Icon(Icons.stop_rounded),
                                  onPressed: _busy ? null : () => _service.stop(),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                IconButton(
                                  tooltip: context.l10n.next,
                                  icon: const Icon(Icons.skip_next_rounded),
                                  onPressed: _busy ? null : () => _service.next(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    // AUDIT-FIX: Loading indicator and unknown tooltip on volume slider
                    Row(
                      children: [
                        Icon(Icons.volume_down_rounded,
                            size: 18, color: p.textSecondary),
                        Expanded(
                          child: _volumeLoading
                              ? Center(
                                  child: PulsrProgressBar.circular(
                                    size: 16,
                                    strokeWidth: 2,
                                  ),
                                )
                              : _volumeUnknown
                                  ? Tooltip(
                                      message:
                                          context.l10n.receiverVolumeUnknown,
                                      child: Slider(
                                        value: _castVolume,
                                        activeColor:
                                            p.accent.withValues(alpha: 0.5),
                                        onChanged: (v) {
                                          setState(() {
                                            _castVolume = v;
                                            _volumeUnknown = false;
                                          });
                                          _service.setVolume(v);
                                        },
                                      ),
                                    )
                                  : Slider(
                                      value: _castVolume,
                                      activeColor: p.accent,
                                      onChanged: (v) {
                                        setState(() => _castVolume = v);
                                        _service.setVolume(v);
                                      },
                                    ),
                        ),
                        Icon(Icons.volume_up_rounded,
                            size: 18, color: p.textSecondary),
                      ],
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
                        style: TextStyle(
                            color: p.textSecondary, fontSize: AppFontSize.body),
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
              Material(
                color: p.surfaceContainer,
                // AUDIT-FIX: Material forbids shape + borderRadius together (debug
                // assert; borderRadius is ignored in release). The shape below
                // already carries the same radius plus the hairline border side.
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.r18All,
                  side: BorderSide(color: p.hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    if (_sdk) ...[
                      for (int i = 0; i < _routes.length; i++) ...[
                        if (i > 0)
                          Divider(
                              height: 1,
                              thickness: 1,
                              color: p.hairline),
                        ListTile(
                          leading: Icon(
                            _routes[i].selected
                                ? Icons.cast_connected_rounded
                                : Icons.tv_rounded,
                            color:
                                _routes[i].selected ? p.accent : p.textPrimary,
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
                              color: p.hairline),
                        ListTile(
                          leading:
                              Icon(Icons.cast_rounded, color: p.textPrimary),
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
                                color: p.textSecondary,
                                fontSize: AppFontSize.label),
                          ),
                          onTap: _busy
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  try {
                                    final deviceName = _devices[i].name;
                                    final res =
                                        await _service.castTo(_devices[i].id);
                                    if (!context.mounted) return;
                                    final msg = res.success
                                        ? l10n.settingsCastingTo(deviceName)
                                        : (res.message ??
                                            l10n.settingsCastFailed);
                                    PulsrToast.show(
                                      context,
                                      message: msg,
                                      isSuccess: res.success,
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() => _busy = false);
                                    }
                                  }
                                },
                        ),
                      ],
                      Container(
                        margin: const EdgeInsets.all(AppSpacing.sm),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: p.surfaceContainerHigh.withValues(alpha: 0.4),
                          borderRadius: AppRadii.r10All,
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 15, color: p.textTertiary),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                l10n.settingsCastNoSdkDesc,
                                style: TextStyle(
                                  fontSize: AppFontSize.label,
                                  color: p.textTertiary,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
