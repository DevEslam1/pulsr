// lib/features/dlna/dlna_screen.dart
//
// DLNA renderer picker + now-playing surface. Every control has a 48 dp target
// and an explicit semantics label.
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/utils/safe_file_path.dart';
import '../../core/widgets/pulsr_progress.dart';
import '../../data/audio/audio_handler.dart';
import 'dlna_renderer_service.dart';
import 'dlna_strings.dart';
import 'upnp_device.dart';

/// Screen that discovers DLNA renderers and controls playback on one of them.
class DlnaScreen extends StatefulWidget {
  /// Creates the screen. [service] is optional and exists for tests / DI.
  const DlnaScreen({super.key, this.service});

  /// Injected service; when omitted the screen owns and disposes its own.
  final DlnaRendererService? service;

  @override
  State<DlnaScreen> createState() => _DlnaScreenState();
}

class _DlnaScreenState extends State<DlnaScreen> {
  /// Extensions offered by the cast-file picker and accepted from the current
  /// track. Kept in sync with MediaHttpServer.contentTypeFor.
  static const List<String> _castExtensions = <String>[
    'mp3',
    'm4a',
    'm4b',
    'mp4',
    'aac',
    'flac',
    'wav',
    'ogg',
    'oga',
    'opus',
    'wma',
    'aiff',
    'aif',
    'dsf',
    'dff',
    'ape',
    'wv',
  ];

  late final DlnaRendererService _service =
      widget.service ?? DlnaRendererService();
  late final bool _ownsService = widget.service == null;
  bool _scanned = false;
  double? _seekPreviewMs;

  @override
  void dispose() {
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanned = true;
      _seekPreviewMs = null;
    });
    await _service.discover();
  }

  Future<void> _connect(UpnpDeviceDescription device) async {
    setState(() => _seekPreviewMs = null);
    await _service.select(device);
  }

  Future<void> _retry() async {
    setState(() => _seekPreviewMs = null);
    // A stale poll is retried by restarting the loop; anything else goes
    // through the normal reconnect/re-cast path.
    if (_service.isPollStale) {
      await _service.retryPolling();
      return;
    }
    await _service.retry();
  }

  Future<void> _pickAndCast() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        dialogTitle: DlnaStrings.castFile,
        type: FileType.custom,
        allowedExtensions: _castExtensions,
      );
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA file pick failed',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
      return;
    }
    final file = SafeFilePath.validate(
      picked?.path,
      allowedExtensions: _castExtensions,
    );
    if (file == null || !mounted) return;

    await _pauseLocalPlayback();
    if (!mounted) return;
    await _service.playFile(
      file.path,
      title: p.basenameWithoutExtension(file.path),
    );
  }

  Future<void> _castCurrentTrack(_LocalTrack track) async {
    final file = SafeFilePath.validate(
      track.path,
      allowedExtensions: _castExtensions,
    );
    if (file == null) return;
    await _pauseLocalPlayback();
    if (!mounted) return;
    await _service.playFile(
      file.path,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
    );
  }

  /// Pauses on-device playback so the same audio is not played twice. The
  /// local player is never resumed automatically when casting stops.
  Future<void> _pauseLocalPlayback() async {
    try {
      final registry = GetIt.instance;
      if (!registry.isRegistered<PulsrAudioHandler>()) return;
      await registry<PulsrAudioHandler>().pause();
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA local playback pause failed',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
    }
  }

  /// Resolves the current track only when the handler exposes an actual
  /// local file path in its media item extras. Streams and remote tracks have
  /// no such path and therefore offer no cast action.
  _LocalTrack? _currentLocalTrack() {
    final registry = GetIt.instance;
    if (!registry.isRegistered<PulsrAudioHandler>()) return null;
    final item = registry<PulsrAudioHandler>().mediaItem.value;
    final extras = item?.extras;
    if (item == null || extras == null) return null;
    final rawPath = extras['path'];
    if (rawPath is! String) return null;
    final path = rawPath.trim();
    if (path.isEmpty || path.contains('://')) return null;
    return _LocalTrack(
      path: path,
      title: item.title,
      artist: item.artist,
      album: item.album,
      duration: item.duration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: Text(
          DlnaStrings.title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: palette.textPrimary),
        ),
      ),
      body: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: _buildContent(context, palette),
          );
        },
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, PulsrPalette palette) {
    final state = _service.state;
    final busy =
        state == DlnaState.discovering || state == DlnaState.connecting;
    final devices = _service.devices;
    final selected = _service.selectedDevice;
    final error = _service.lastError;
    final title = _service.nowPlayingTitle;
    final localTrack = _currentLocalTrack();

    final children = <Widget>[
      Text(
        DlnaStrings.subtitle,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: palette.textSecondary),
      ),
      const SizedBox(height: AppSpacing.md),
      SizedBox(
        height: 48,
        width: double.infinity,
        child: Semantics(
          button: true,
          enabled: !busy,
          label: DlnaStrings.scanSemantics,
          child: FilledButton.icon(
            onPressed: busy ? null : _scan,
            icon: const Icon(Icons.wifi_find_rounded),
            label: Text(
              state == DlnaState.discovering
                  ? DlnaStrings.scanning
                  : DlnaStrings.scan,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.onAccent,
            ),
          ),
        ),
      ),
    ];

    children.addAll(<Widget>[
      const SizedBox(height: AppSpacing.sm),
      SizedBox(
        height: 48,
        width: double.infinity,
        child: Semantics(
          button: true,
          enabled: !busy && selected != null,
          label: DlnaStrings.castFileSemantics,
          child: OutlinedButton.icon(
            onPressed:
                busy || selected == null ? null : _pickAndCast,
            icon: const Icon(Icons.audio_file_rounded),
            label: const Text(DlnaStrings.castFile),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.accent,
              minimumSize: const Size(0, 48),
            ),
          ),
        ),
      ),
      if (selected != null && localTrack != null) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 48,
          width: double.infinity,
          child: Semantics(
            button: true,
            enabled: !busy,
            label: DlnaStrings.castCurrentSemantics,
            child: OutlinedButton.icon(
              onPressed: busy ? null : () => _castCurrentTrack(localTrack),
              icon: const Icon(Icons.cast_connected_rounded),
              label: const Text(DlnaStrings.castCurrentTrack),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.accent,
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
        ),
      ],
    ]);

    if (state == DlnaState.discovering) {
      children.addAll(<Widget>[
        const SizedBox(height: AppSpacing.md),
        const PulsrProgressBar(height: 3),
      ]);
    }

    if (error != null) {
      children.addAll(<Widget>[
        const SizedBox(height: AppSpacing.md),
        _ErrorBanner(message: error.userMessage, onRetry: _retry),
      ]);
    }

    if (devices.isNotEmpty) {
      children.add(const SizedBox(height: AppSpacing.lg));
      for (final device in devices) {
        children.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
            child: _DeviceTile(
              device: device,
              selected: selected?.identity == device.identity,
              onConnect: () => _connect(device),
            ),
          ),
        );
      }
    } else if (_scanned && !busy) {
      children.addAll(<Widget>[
        const SizedBox(height: AppSpacing.lg),
        Text(
          DlnaStrings.noDevices,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: palette.textTertiary),
        ),
      ]);
    }

    if (selected != null && title != null) {
      children.addAll(<Widget>[
        const SizedBox(height: AppSpacing.lg),
        _NowPlayingCard(
          title: title,
          state: state,
          stale: _service.isPollStale,
          position: _service.position,
          duration: _service.duration,
          previewMs: _seekPreviewMs,
          onPreview: (value) => setState(() => _seekPreviewMs = value),
          onSeek: (value) {
            setState(() => _seekPreviewMs = null);
            unawaited(_service.seek(Duration(milliseconds: value.round())));
          },
          onPause: () => unawaited(_service.pause()),
          onResume: () => unawaited(_service.resume()),
          onStop: () => unawaited(_service.stop()),
        ),
      ]);
    }

    return children;
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: palette.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadii.tile),
          border: Border.all(color: palette.error),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, color: palette.error),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    DlnaStrings.errorTitle,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: palette.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    message,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Semantics(
              button: true,
              label: context.l10n.retry,
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  minimumSize: const Size(72, 48),
                  foregroundColor: palette.accent,
                ),
                child: Text(context.l10n.retry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.selected,
    required this.onConnect,
  });

  final UpnpDeviceDescription device;
  final bool selected;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final model = device.modelName ?? device.manufacturer;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(
          color: selected ? palette.accent : palette.hairline,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.cast_rounded, color: palette.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              label: DlnaStrings.deviceRow(device.friendlyName, model),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    device.friendlyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: palette.textPrimary),
                  ),
                  if (model != null && model.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (selected)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
              child: Text(
                DlnaStrings.connected,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: palette.accent),
              ),
            )
          else
            Semantics(
              button: true,
              label: DlnaStrings.connectTo(device.friendlyName),
              child: TextButton(
                onPressed: onConnect,
                style: TextButton.styleFrom(
                  minimumSize: const Size(88, 48),
                  foregroundColor: palette.accent,
                ),
                child: Text(DlnaStrings.connect),
              ),
            ),
        ],
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.title,
    required this.state,
    required this.stale,
    required this.position,
    required this.duration,
    required this.previewMs,
    required this.onPreview,
    required this.onSeek,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final String title;
  final DlnaState state;

  /// The poll is lost: show that instead of freezing the last transport label.
  final bool stale;
  final Duration position;
  final Duration duration;
  final double? previewMs;
  final ValueChanged<double> onPreview;
  final ValueChanged<double> onSeek;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final durationMs = duration.inMilliseconds;
    final maxMs = durationMs > 0 ? durationMs.toDouble() : 1.0;
    final value = (previewMs ?? position.inMilliseconds.toDouble())
        .clamp(0.0, maxMs)
        .toDouble();
    final canSeek = durationMs > 0;
    final paused = state == DlnaState.paused;
    final canPause = state == DlnaState.playing || paused;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: palette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            DlnaStrings.nowPlaying,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: palette.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            stale ? DlnaStrings.stateStale : DlnaStrings.stateLabel(state),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: palette.accent),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            slider: true,
            label: DlnaStrings.seek,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: palette.accent,
                inactiveTrackColor: palette.hairline,
                thumbColor: palette.accent,
              ),
              child: Slider(
                value: value,
                max: maxMs,
                onChanged: canSeek ? onPreview : null,
                onChangeEnd: canSeek ? onSeek : null,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                _formatDuration(
                  Duration(milliseconds: value.round()),
                ),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
              Text(
                _formatDuration(duration),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Semantics(
                button: true,
                label: paused ? DlnaStrings.resume : DlnaStrings.pause,
                child: IconButton(
                  onPressed: canPause
                      ? (paused ? onResume : onPause)
                      : null,
                  tooltip: paused ? DlnaStrings.resume : DlnaStrings.pause,
                  icon: Icon(
                    paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: palette.accentContainer,
                    foregroundColor: palette.accent,
                    minimumSize: const Size(48, 48),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Semantics(
                button: true,
                label: DlnaStrings.stop,
                child: IconButton(
                  onPressed: onStop,
                  tooltip: DlnaStrings.stop,
                  icon: const Icon(Icons.stop_rounded),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration value) {
    final seconds = value.inSeconds;
    final minutes = seconds ~/ 60;
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    if (minutes < 60) return '$minutes:$remainder';
    final hours = minutes ~/ 60;
    final minutePart = (minutes % 60).toString().padLeft(2, '0');
    return '$hours:$minutePart:$remainder';
  }
}

/// A local file that can be cast, resolved from the audio handler's media item.
class _LocalTrack {
  const _LocalTrack({
    required this.path,
    this.title,
    this.artist,
    this.album,
    this.duration,
  });

  final String path;
  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;
}
