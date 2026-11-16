// lib/features/dlna/dlna_renderer_service.dart
//
// Orchestrates DLNA casting: discovery, device selection, serving the file over
// the local HTTP server, AVTransport commands and position polling.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/errors/app_error.dart';
import '../../core/utils/error_logger.dart';
import 'av_transport.dart';
import 'media_http_server.dart';
import 'ssdp_client.dart';
import 'upnp_device.dart';

/// High-level renderer state consumed by the DLNA screen.
enum DlnaState {
  /// Nothing discovered or selected yet.
  idle,

  /// An SSDP scan is in progress.
  discovering,

  /// A device was picked and its AVTransport service is being probed.
  connecting,

  /// Media is playing on the renderer.
  playing,

  /// Media is paused on the renderer.
  paused,

  /// Playback stopped, or the renderer has no media loaded.
  stopped,

  /// The last operation failed; [DlnaRendererService.lastError] holds details.
  error,
}

/// ChangeNotifier that drives one DLNA MediaRenderer.
///
/// All network and file-system failures are converted to [AppError] and exposed
/// through [lastError] while the state becomes [DlnaState.error].
class DlnaRendererService extends ChangeNotifier {
  final SsdpClient _ssdp;
  final MediaHttpServer _mediaServer;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration _pollInterval;
  final Duration _discoveryTimeout;
  final Duration _descriptionTimeout;

  DlnaState _state = DlnaState.idle;
  List<UpnpDeviceDescription> _devices = const <UpnpDeviceDescription>[];
  UpnpDeviceDescription? _selectedDevice;
  AvTransportClient? _avTransport;
  String? _nowPlayingTitle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  AppError? _lastError;
  Timer? _pollTimer;
  bool _polling = false;
  int _pollFailures = 0;
  int _tokenSeq = 0;
  bool _disposed = false;

  /// Creates the service. Every collaborator is injectable for tests.
  DlnaRendererService({
    SsdpClient? ssdpClient,
    MediaHttpServer? mediaServer,
    http.Client? httpClient,
    Duration pollInterval = const Duration(seconds: 1),
    Duration discoveryTimeout = const Duration(seconds: 3),
    Duration descriptionTimeout = const Duration(seconds: 4),
  })  : _ssdp = ssdpClient ?? SsdpClient(),
        _mediaServer = mediaServer ?? MediaHttpServer(),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _pollInterval = pollInterval,
        _discoveryTimeout = discoveryTimeout,
        _descriptionTimeout = descriptionTimeout;

  /// Current state.
  DlnaState get state => _state;

  /// Renderers found by the last [discover] call.
  List<UpnpDeviceDescription> get devices =>
      List<UpnpDeviceDescription>.unmodifiable(_devices);

  /// Device currently driven by this service.
  UpnpDeviceDescription? get selectedDevice => _selectedDevice;

  /// Title passed to [playFile], or the file name when none was given.
  String? get nowPlayingTitle => _nowPlayingTitle;

  /// Last known playback position.
  Duration get position => _position;

  /// Last known media duration; [Duration.zero] until the renderer reports it.
  Duration get duration => _duration;

  /// Last failure, cleared when a new operation starts.
  AppError? get lastError => _lastError;

  /// Exposed so the host can report the serving URL / port.
  MediaHttpServer get mediaServer => _mediaServer;

  /// Scans the LAN and loads descriptions of discovered renderers.
  Future<void> discover() async {
    if (_disposed || _state == DlnaState.discovering) return;
    _state = DlnaState.discovering;
    _lastError = null;
    _devices = const <UpnpDeviceDescription>[];
    notifyListeners();

    try {
      final responses = await _ssdp.search(timeout: _discoveryTimeout);
      final locations = <Uri>[];
      for (final response in responses) {
        final location = _resolveLocation(response);
        if (location == null) continue;
        if (!locations.contains(location)) locations.add(location);
      }

      final found = <String, UpnpDeviceDescription>{};
      final descriptions = await Future.wait(
        locations.map(_fetchDescription),
      );
      for (final description in descriptions) {
        if (description == null) continue;
        found.putIfAbsent(description.identity, () => description);
      }

      final sorted = found.values.toList(growable: false)
        ..sort(
          (a, b) => a.friendlyName
              .toLowerCase()
              .compareTo(b.friendlyName.toLowerCase()),
        );
      if (_disposed) return;
      _devices = sorted;
      _state = DlnaState.idle;
      notifyListeners();
    } catch (error, stackTrace) {
      _fail(error, stackTrace, 'DLNA discovery failed');
    }
  }

  /// Selects [device] and probes its AVTransport state.
  Future<void> select(UpnpDeviceDescription device) async {
    if (_disposed) return;
    _state = DlnaState.connecting;
    _lastError = null;
    notifyListeners();

    final previous = _avTransport;
    _avTransport = null;
    previous?.close();

    final client = AvTransportClient(
      device.avTransportControlUrl,
      client: _httpClient,
    );
    _avTransport = client;

    try {
      final info = await client.getTransportInfo();
      if (_disposed) return;
      _selectedDevice = device;
      _nowPlayingTitle = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _state = _stateFor(info.state);
      notifyListeners();
    } catch (error, stackTrace) {
      _avTransport = null;
      client.close();
      _fail(error, stackTrace, 'DLNA connect failed');
    }
  }

  /// Serves [path] over the LAN and starts playback on the selected renderer.
  Future<void> playFile(
    String path, {
    String? title,
    String? artist,
    String? album,
  }) async {
    if (_disposed) return;
    final client = _avTransport;
    if (client == null || _selectedDevice == null) {
      _fail(
        uiError('Select a DLNA renderer first.', code: 'DLNA_NO_DEVICE'),
        StackTrace.empty,
        'DLNA play rejected',
      );
      return;
    }
    if (path.isEmpty) {
      _fail(
        uiError('The track has no local file to cast.', code: 'DLNA_NO_FILE'),
        StackTrace.empty,
        'DLNA play rejected',
      );
      return;
    }

    try {
      if (!_mediaServer.isRunning) await _mediaServer.start();
      final token = 'pulsr-${_tokenSeq++}';
      _mediaServer.register(token, MediaSource.file(path));
      final url = _mediaServer.uriFor(token).toString();
      final resolvedTitle = title ?? p.basenameWithoutExtension(path);

      final metadata = AvTransportClient.buildDidlLiteMetadata(
        url: url,
        title: resolvedTitle,
        artist: artist,
        album: album,
        mimeType: MediaHttpServer.contentTypeFor(path),
      );

      _nowPlayingTitle = resolvedTitle;
      _position = Duration.zero;
      _duration = Duration.zero;
      _lastError = null;

      await client.setAvTransportUri(url, metadata);
      await client.play();
      if (_disposed) return;
      _state = DlnaState.playing;
      _pollFailures = 0;
      notifyListeners();
      _startPolling();
    } catch (error, stackTrace) {
      _fail(error, stackTrace, 'DLNA play failed');
    }
  }

  /// Pauses playback on the renderer.
  Future<void> pause() async {
    final client = _avTransport;
    if (_disposed || client == null || _state != DlnaState.playing) return;
    try {
      await client.pause();
      if (_disposed) return;
      _state = DlnaState.paused;
      notifyListeners();
      _stopPolling();
    } catch (error, stackTrace) {
      _fail(error, stackTrace, 'DLNA pause failed');
    }
  }

  /// Resumes playback on the renderer.
  Future<void> resume() async {
    final client = _avTransport;
    if (_disposed || client == null || _state != DlnaState.paused) return;
    try {
      await client.play();
      if (_disposed) return;
      _state = DlnaState.playing;
      _pollFailures = 0;
      notifyListeners();
      _startPolling();
    } catch (error, stackTrace) {
      _fail(error, stackTrace, 'DLNA resume failed');
    }
  }

  /// Stops playback on the renderer.
  Future<void> stop() async {
    final client = _avTransport;
    if (_disposed || client == null) return;
    try {
      await client.stop();
      if (_disposed) return;
      _stopPolling();
      _state = DlnaState.stopped;
      _nowPlayingTitle = null;
      _position = Duration.zero;
      notifyListeners();
    } catch (error, stackTrace) {
      _fail(error, stackTrace, 'DLNA stop failed');
    }
  }

  /// Seeks the renderer to [target].
  Future<void> seek(Duration target) async {
    final client = _avTransport;
    if (_disposed || client == null) return;
    final clamped = target.isNegative ? Duration.zero : target;
    try {
      await client.seek(clamped);
      if (_disposed) return;
      _position = clamped;
      notifyListeners();
    } catch (error, stackTrace) {
      _fail(error, stackTrace, 'DLNA seek failed');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_pollOnce());
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollOnce() async {
    if (_disposed || _polling) return;
    final client = _avTransport;
    if (client == null) return;
    _polling = true;
    try {
      final position = await client.getPositionInfo();
      final transport = await client.getTransportInfo();
      if (_disposed) return;
      _pollFailures = 0;
      final reported = position.position;
      if (reported != null) _position = reported;
      final reportedDuration = position.trackDuration;
      if (reportedDuration != null) _duration = reportedDuration;
      _state = _stateFor(transport.state);
      if (_state == DlnaState.stopped || _state == DlnaState.idle) {
        _stopPolling();
      }
      notifyListeners();
    } catch (error, stackTrace) {
      _pollFailures += 1;
      ErrorLogger.log(
        'DLNA position poll failed',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
      if (_pollFailures >= 3) _stopPolling();
    } finally {
      _polling = false;
    }
  }

  Uri? _resolveLocation(SsdpResponse response) {
    final parsed = Uri.tryParse(response.location);
    if (parsed == null) {
      ErrorLogger.log(
        'DLNA response has an invalid LOCATION: ${response.location}',
        category: 'DLNA',
      );
      return null;
    }
    if (parsed.hasScheme) return parsed;
    return Uri.parse('http://${response.sourceAddress}/').resolveUri(parsed);
  }

  Future<UpnpDeviceDescription?> _fetchDescription(Uri location) async {
    try {
      final response =
          await _httpClient.get(location).timeout(_descriptionTimeout);
      if (response.statusCode != 200) {
        ErrorLogger.log(
          'DLNA description returned HTTP ${response.statusCode} for $location',
          category: 'DLNA',
        );
        return null;
      }
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      return UpnpDeviceDescription.parse(body, location: location);
    } on UpnpParseError catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA description rejected for $location',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
      return null;
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA description fetch failed for $location',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
      return null;
    }
  }

  DlnaState _stateFor(TransportState state) {
    switch (state) {
      case TransportState.playing:
        return DlnaState.playing;
      case TransportState.paused:
      case TransportState.pausedRecording:
        return DlnaState.paused;
      case TransportState.noMedia:
        return DlnaState.idle;
      case TransportState.stopped:
      case TransportState.transitioning:
      case TransportState.unknown:
        return DlnaState.stopped;
    }
  }

  void _fail(Object error, StackTrace stackTrace, String message) {
    final appError = resolveAppError(error, stackTrace);
    _lastError = appError;
    _state = DlnaState.error;
    ErrorLogger.log(
      message,
      error: appError,
      stackTrace: stackTrace,
      category: 'DLNA',
    );
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    _avTransport?.close();
    _avTransport = null;
    if (_ownsHttpClient) _httpClient.close();
    unawaited(_shutdownMediaServer());
    super.dispose();
  }

  Future<void> _shutdownMediaServer() async {
    try {
      await _mediaServer.stop();
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA media server shutdown failed',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
    }
  }
}
