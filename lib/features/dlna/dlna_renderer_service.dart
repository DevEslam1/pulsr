// lib/features/dlna/dlna_renderer_service.dart
//
// Orchestrates DLNA casting: discovery, device selection, serving the file over
// the local HTTP server, AVTransport commands and position polling.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/errors/app_error.dart';
import '../../core/utils/error_logger.dart';
import 'av_transport.dart';
import 'dlna_strings.dart';
import 'media_http_server.dart';
import 'ssdp_client.dart';
import 'upnp_device.dart';

/// Resolves the local address that faces a renderer host and port.
typedef DlnaLocalAddressResolver = Future<InternetAddress?> Function(
  String host,
  int port,
);

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
  /// Largest description document accepted from a renderer, in bytes.
  static const int maxDescriptionBytes = 256 * 1024;

  final SsdpClient _ssdp;
  final MediaHttpServer _mediaServer;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  /// Consecutive poll failures after which the loop stops and the UI shows the
  /// stale banner instead of pretending playback is still live.
  static const int maxConsecutivePollFailures = 3;

  final Duration _pollInterval;
  final Duration _discoveryTimeout;
  final Duration _descriptionTimeout;
  final DlnaLocalAddressResolver _localAddressResolver;

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
  bool _pollStale = false;
  String? _token;
  String? _lastCastPath;
  String? _lastCastTitle;
  String? _lastCastArtist;
  String? _lastCastAlbum;
  Duration? _lastCastDuration;
  bool _disposed = false;

  /// Creates the service. Every collaborator is injectable for tests.
  DlnaRendererService({
    SsdpClient? ssdpClient,
    MediaHttpServer? mediaServer,
    http.Client? httpClient,
    Duration pollInterval = const Duration(seconds: 1),
    Duration discoveryTimeout = const Duration(seconds: 3),
    Duration descriptionTimeout = const Duration(seconds: 4),
    DlnaLocalAddressResolver? localAddressResolver,
  })  : _ssdp = ssdpClient ?? SsdpClient(),
        _mediaServer = mediaServer ?? MediaHttpServer(),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _pollInterval = pollInterval,
        _discoveryTimeout = discoveryTimeout,
        _descriptionTimeout = descriptionTimeout,
        _localAddressResolver =
            localAddressResolver ?? MediaHttpServer.localAddressFacing;

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

  /// True when polling gave up after repeated failures.
  ///
  /// The transport state on screen is the last one the renderer reported, so it
  /// may no longer be true (a renderer that stopped answering used to keep the
  /// UI on "Playing" with a position that never advanced). [retryPolling]
  /// clears it and resumes the loop.
  bool get isPollStale => _pollStale;

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
  ///
  /// Switching to a different renderer first stops the previous one, drops its
  /// media token and shuts the media server down so the next cast can bind the
  /// interface facing the new device.
  Future<void> select(UpnpDeviceDescription device) async {
    if (_disposed) return;
    _state = DlnaState.connecting;
    _lastError = null;
    notifyListeners();

    final previousClient = _avTransport;
    final previousDevice = _selectedDevice;
    _avTransport = null;
    _stopPolling();

    final switching = previousClient != null &&
        previousDevice != null &&
        previousDevice.identity != device.identity;
    if (switching) {
      await _stopRenderer(previousClient);
    }
    previousClient?.close();

    if (switching) {
      _selectedDevice = null;
      _nowPlayingTitle = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _revokeMediaToken();
      await _shutdownMediaServer();
    }
    if (_disposed) return;

    final client = AvTransportClient(
      device.avTransportControlUrl,
      client: _httpClient,
    );
    _avTransport = client;

    try {
      final info = await client.getTransportInfo();
      if (_disposed) return;
      _selectedDevice = device;
      if (switching) {
        _nowPlayingTitle = null;
        _position = Duration.zero;
        _duration = Duration.zero;
      }
      _state = _stateFor(info.state);
      notifyListeners();
    } catch (error, stackTrace) {
      _avTransport = null;
      client.close();
      _fail(error, stackTrace, 'DLNA connect failed');
    }
  }

  /// Serves [path] over the LAN and starts playback on the selected renderer.
  ///
  /// [duration] is embedded in the DIDL metadata when the caller already knows
  /// it. The previous token is revoked before the new one is registered.
  Future<void> playFile(
    String path, {
    String? title,
    String? artist,
    String? album,
    Duration? duration,
  }) async {
    if (_disposed) return;
    final client = _avTransport;
    final device = _selectedDevice;
    if (client == null || device == null) {
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

    final resolvedTitle = title ?? p.basenameWithoutExtension(path);
    _lastCastPath = path;
    _lastCastTitle = resolvedTitle;
    _lastCastArtist = artist;
    _lastCastAlbum = album;
    _lastCastDuration = duration;

    String? token;
    try {
      // Revoke the previous token before any work that could fail: a new cast
      // attempt must never leave the old URL fetchable.
      _revokeMediaToken();
      final size = await File(path).length();
      if (!_mediaServer.isRunning) {
        final controlUrl = device.avTransportControlUrl;
        final controlPort = controlUrl.hasPort
            ? controlUrl.port
            : (controlUrl.scheme == 'https' ? 443 : 80);
        final bindAddress =
            await _localAddressResolver(controlUrl.host, controlPort);
        await _mediaServer.start(bindAddress: bindAddress);
      }

      token = MediaHttpServer.newToken();
      _mediaServer.register(token, MediaSource.file(path));
      _token = token;
      final url = _mediaServer.uriFor(token).toString();

      final metadata = AvTransportClient.buildDidlLiteMetadata(
        url: url,
        title: resolvedTitle,
        artist: artist,
        album: album,
        mimeType: MediaHttpServer.contentTypeFor(path),
        size: size,
        duration: duration,
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
      if (token != null) {
        _mediaServer.unregister(token);
        if (_token == token) _token = null;
      }
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

  /// Stops playback on the renderer and revokes the media token.
  Future<void> stop() async {
    if (_disposed) return;
    final client = _avTransport;
    if (client == null) {
      _revokeMediaToken();
      return;
    }
    _stopPolling();
    try {
      await client.stop();
      if (_disposed) return;
      _state = DlnaState.stopped;
      _nowPlayingTitle = null;
      _position = Duration.zero;
      notifyListeners();
    } catch (error, stackTrace) {
      _fail(error, stackTrace, 'DLNA stop failed');
    } finally {
      _revokeMediaToken();
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

  /// Retries the last failed operation.
  ///
  /// When a file was already cast this re-casts that same file instead of
  /// reconnecting to the renderer.
  Future<void> retry() async {
    if (_disposed) return;
    final path = _lastCastPath;
    if (path != null && _avTransport != null && _selectedDevice != null) {
      await playFile(
        path,
        title: _lastCastTitle,
        artist: _lastCastArtist,
        album: _lastCastAlbum,
        duration: _lastCastDuration,
      );
      return;
    }
    final device = _selectedDevice;
    if (device != null) {
      await select(device);
      return;
    }
    await discover();
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
      if (_pollStale) {
        _pollStale = false;
        _lastError = null;
      }
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
      if (_pollFailures >= maxConsecutivePollFailures && !_pollStale) {
        // Stop hammering a renderer that stopped answering and surface the
        // stale state instead of freezing "Playing" silently.
        _stopPolling();
        _pollStale = true;
        _lastError = NetworkError(
          code: 'dlna-poll-stale',
          userMessage: DlnaStrings.pollLost,
          cause: error,
          stackTrace: stackTrace,
        );
        notifyListeners();
      }
    } finally {
      _polling = false;
    }
  }

  /// Clears a stale poll and resumes position polling.
  ///
  /// Called by the screen's Retry action on the stale banner. Returns whether a
  /// poll loop was restarted (false when no renderer is selected).
  Future<bool> retryPolling() async {
    if (_disposed) return false;
    final client = _avTransport;
    if (client == null) return false;
    _pollFailures = 0;
    _pollStale = false;
    _lastError = null;
    notifyListeners();
    _startPolling();
    await _pollOnce();
    return true;
  }

  Uri? _resolveLocation(SsdpResponse response) {
    final parsed = Uri.tryParse(response.location);
    if (parsed == null ||
        !SsdpClient.isAllowedDescriptionLocation(parsed, response.sourceAddress)) {
      ErrorLogger.log(
        'DLNA response has an invalid or untrusted LOCATION: '
        '${response.location} (from ${response.sourceAddress})',
        category: 'DLNA',
      );
      return null;
    }
    return parsed;
  }

  Future<UpnpDeviceDescription?> _fetchDescription(Uri location) async {
    try {
      final request = http.Request('GET', location)..followRedirects = false;
      final streamed =
          await _httpClient.send(request).timeout(_descriptionTimeout);
      if (streamed.statusCode != HttpStatus.ok) {
        await _discardBody(streamed.stream);
        ErrorLogger.log(
          'DLNA description returned HTTP ${streamed.statusCode} for $location',
          category: 'DLNA',
        );
        return null;
      }

      final declaredLength = streamed.contentLength;
      if (declaredLength != null && declaredLength > maxDescriptionBytes) {
        await _discardBody(streamed.stream);
        ErrorLogger.log(
          'DLNA description for $location is too large '
          '($declaredLength bytes)',
          category: 'DLNA',
        );
        return null;
      }

      final bytes = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream.timeout(_descriptionTimeout)) {
        if (bytes.length + chunk.length > maxDescriptionBytes) {
          ErrorLogger.log(
            'DLNA description for $location exceeded '
            '$maxDescriptionBytes bytes',
            category: 'DLNA',
          );
          return null;
        }
        bytes.add(chunk);
      }

      final body = utf8.decode(bytes.takeBytes(), allowMalformed: true);
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

  Future<void> _discardBody(Stream<List<int>> stream) async {
    try {
      await stream.drain<void>().timeout(_descriptionTimeout);
    } catch (_) {
      // The response is being discarded; a failed drain has no consequence.
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
      case TransportState.transitioning:
      case TransportState.unknown:
        // A renderer changing state is still on its way; keep polling instead
        // of declaring playback stopped.
        return DlnaState.connecting;
      case TransportState.stopped:
        return DlnaState.stopped;
    }
  }

  void _revokeMediaToken() {
    final token = _token;
    _token = null;
    if (token != null) _mediaServer.unregister(token);
  }

  Future<void> _stopRenderer(AvTransportClient client) async {
    try {
      await client.stop().timeout(_descriptionTimeout);
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA stop of previous renderer failed',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
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
    final client = _avTransport;
    _avTransport = null;
    unawaited(_shutdown(client, closeHttpClient: _ownsHttpClient));
    super.dispose();
  }

  /// Sends Stop to the renderer, then releases the client and media server.
  Future<void> _shutdown(
    AvTransportClient? client, {
    required bool closeHttpClient,
  }) async {
    if (client != null) {
      try {
        await client.stop().timeout(const Duration(seconds: 2));
      } catch (error, stackTrace) {
        ErrorLogger.log(
          'DLNA renderer stop on dispose failed',
          error: error,
          stackTrace: stackTrace,
          category: 'DLNA',
        );
      }
      client.close();
    }
    if (closeHttpClient) _httpClient.close();
    await _shutdownMediaServer();
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
