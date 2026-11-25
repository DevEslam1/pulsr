// lib/features/dlna/dlna_renderer_service.dart
//
// Orchestrates DLNA casting: discovery, device selection, serving the file over
// the local HTTP server, AVTransport commands and position polling.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/errors/app_error.dart';
import '../../core/network/remote_target_policy.dart';
import '../../core/utils/error_logger.dart';
import 'av_transport.dart';
import 'dlna_strings.dart';
import 'media_http_server.dart';
import 'ssdp_client.dart';
import 'upnp_device.dart';
import 'upnp_device_description_cache.dart';

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

  /// The renderer is transitioning or buffering media.
  buffering,

  /// Media is playing on the renderer.
  playing,

  /// Media is paused on the renderer.
  paused,

  /// Playback stopped, or the renderer has no media loaded.
  stopped,

  /// The last operation failed; [DlnaRendererService.lastError] holds details.
  error,
}

/// One item in a renderer playback queue.
class DlnaQueueTrack {
  /// Creates a local-file or stream-URL queue item.
  const DlnaQueueTrack({
    this.path,
    this.url,
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.mimeType,
  }) : assert(path != null || url != null);

  final String? path;
  final String? url;
  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final String? mimeType;
}

/// ChangeNotifier that drives one DLNA MediaRenderer.
///
/// All network and file-system failures are converted to [AppError] and exposed
/// through [lastError] while the state becomes [DlnaState.error].
class DlnaRendererService extends ChangeNotifier {
  static DlnaRendererService? _sharedInstance;

  /// App-scoped singleton resolved from GetIt when registered or shared
  /// lazily across [DlnaScreen] navigations so cast playback survives back nav.
  static DlnaRendererService get shared {
    if (GetIt.instance.isRegistered<DlnaRendererService>()) {
      return GetIt.instance<DlnaRendererService>();
    }
    final current = _sharedInstance;
    if (current != null && !current._disposed) return current;
    final created = DlnaRendererService();
    _sharedInstance = created;
    return created;
  }

  /// Disposes and clears the lazily created shared singleton (for tests).
  @visibleForTesting
  static void resetSharedForTest() {
    final existing = _sharedInstance;
    _sharedInstance = null;
    existing?.dispose();
  }

  /// Largest description document accepted from a renderer, in bytes.
  static const int maxDescriptionBytes = 256 * 1024;

  /// Number of consecutive STOPPED/NO_MEDIA polls required before transitioning
  /// active playback to stopped/idle.
  static const int maxConsecutiveStoppedPolls = 2;

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
  final UpnpDeviceDescriptionCache _descriptionCache;
  final Set<String> _allowedMediaHosts;
  final Future<List<String>> Function(String host)? _dnsLookup;

  DlnaState _state = DlnaState.idle;
  List<UpnpDeviceDescription> _devices = const <UpnpDeviceDescription>[];
  UpnpDeviceDescription? _selectedDevice;
  UpnpDeviceDescription? _pendingSelectDevice;
  AvTransportClient? _avTransport;
  String? _nowPlayingTitle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  AppError? _lastError;
  Timer? _pollTimer;
  bool _polling = false;
  int _pollFailures = 0;
  int _consecutiveStoppedPolls = 0;
  bool _pollStale = false;
  String? _token;
  String? _nextToken;
  String? _lastCastPath;
  String? _lastCastUrl;
  String? _lastCastMimeType;
  String? _lastCastTitle;
  String? _lastCastArtist;
  String? _lastCastAlbum;
  Duration? _lastCastDuration;
  List<DlnaQueueTrack> _queue = const <DlnaQueueTrack>[];
  int _queueIndex = -1;
  bool _advancingQueue = false;
  int _opSequence = 0;
  bool _disposed = false;

  /// Optional external handler invoked when [next] is pressed with no queue.
  Future<void> Function()? onNextRequested;

  /// Optional external handler invoked when [previous] is pressed with no queue.
  Future<void> Function()? onPreviousRequested;

  /// Creates the service. Every collaborator is injectable for tests.
  DlnaRendererService({
    SsdpClient? ssdpClient,
    MediaHttpServer? mediaServer,
    http.Client? httpClient,
    Duration pollInterval = const Duration(seconds: 1),
    Duration discoveryTimeout = const Duration(seconds: 3),
    Duration descriptionTimeout = const Duration(seconds: 4),
    DlnaLocalAddressResolver? localAddressResolver,
    UpnpDeviceDescriptionCache? descriptionCache,
    Set<String> allowedMediaHosts = const {},
    Future<List<String>> Function(String host)? dnsLookup,
  })  : _ssdp = ssdpClient ?? SsdpClient(),
        _mediaServer = mediaServer ?? MediaHttpServer(),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _pollInterval = pollInterval,
        _discoveryTimeout = discoveryTimeout,
        _descriptionTimeout = descriptionTimeout,
        _localAddressResolver =
            localAddressResolver ?? MediaHttpServer.localAddressFacing,
        _descriptionCache = descriptionCache ?? UpnpDeviceDescriptionCache(),
        _allowedMediaHosts =
            allowedMediaHosts.map((h) => h.trim().toLowerCase()).toSet(),
        _dnsLookup = dnsLookup;

  /// Current state.
  DlnaState get state => _state;

  /// Underlying AVTransport client for direct control point actions.
  AvTransportClient? get avTransport => _avTransport;

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

  /// Loaded cast queue, when casting from a multi-track list.
  List<DlnaQueueTrack> get queue => List<DlnaQueueTrack>.unmodifiable(_queue);

  /// Current zero-based index inside [queue], or `-1` when unqueued.
  int get currentQueueIndex => _queueIndex;

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
  /// When switching away from an active renderer, the new target is probed
  /// first so an unreachable candidate never disconnects the current renderer
  /// or loses retry state.
  Future<void> select(UpnpDeviceDescription device) async {
    if (_disposed) return;
    final op = ++_opSequence;
    _pendingSelectDevice = device;
    _state = DlnaState.connecting;
    _lastError = null;
    notifyListeners();

    final previousClient = _avTransport;
    final previousDevice = _selectedDevice;
    final switching = previousClient != null &&
        previousDevice != null &&
        previousDevice.identity != device.identity;

    final candidateClient = AvTransportClient(
      device.avTransportControlUrl,
      client: _httpClient,
    );

    try {
      final info = await candidateClient.getTransportInfo();
      if (_disposed || op != _opSequence) {
        candidateClient.close();
        return;
      }

      _stopPolling();
      if (switching) {
        await _stopRenderer(previousClient);
        previousClient.close();
        _revokeMediaTokens();
        await _shutdownMediaServer();
        _nowPlayingTitle = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _queue = const <DlnaQueueTrack>[];
        _queueIndex = -1;
      } else {
        previousClient?.close();
      }
      if (_disposed || op != _opSequence) {
        candidateClient.close();
        return;
      }

      _avTransport = candidateClient;
      _selectedDevice = device;
      _pendingSelectDevice = null;
      _consecutiveStoppedPolls = 0;
      _pollFailures = 0;
      _pollStale = false;
      _state = _stateFor(info.state);
      if (_state == DlnaState.playing ||
          _state == DlnaState.paused ||
          _state == DlnaState.buffering ||
          _nowPlayingTitle == null) {
        await _refreshMediaInfo(candidateClient, op);
      }
      if (_disposed || op != _opSequence) return;
      if (_state == DlnaState.playing ||
          _state == DlnaState.paused ||
          _state == DlnaState.buffering) {
        _startPolling();
      }
      notifyListeners();
    } catch (error, stackTrace) {
      candidateClient.close();
      if (_disposed || op != _opSequence) return;
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
  }) {
    _queue = const <DlnaQueueTrack>[];
    _queueIndex = -1;
    return _playFileInternal(
      path,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
    );
  }

  Future<void> _playFileInternal(
    String path, {
    String? title,
    String? artist,
    String? album,
    Duration? duration,
  }) async {
    if (_disposed) return;
    final op = ++_opSequence;
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

    _pendingSelectDevice = null;
    final resolvedTitle = title ?? p.basenameWithoutExtension(path);
    _lastCastPath = path;
    _lastCastUrl = null;
    _lastCastMimeType = null;
    _lastCastTitle = resolvedTitle;
    _lastCastArtist = artist;
    _lastCastAlbum = album;
    _lastCastDuration = duration;

    String? token;
    try {
      // Revoke previous tokens before any work that could fail: a new cast
      // attempt must never leave the old URL fetchable.
      _revokeMediaTokens();
      final size = await File(path).length();
      if (_disposed || op != _opSequence) return;

      final controlUrl = device.avTransportControlUrl;
      final controlPort = controlUrl.hasPort
          ? controlUrl.port
          : (controlUrl.scheme == 'https' ? 443 : 80);
      final bindAddress =
          await _localAddressResolver(controlUrl.host, controlPort);
      if (_disposed || op != _opSequence) return;
      if (_mediaServer.isRunning &&
          bindAddress != null &&
          _mediaServer.host != bindAddress.address) {
        await _mediaServer.stop();
        if (_disposed || op != _opSequence) return;
      }
      if (!_mediaServer.isRunning) {
        await _mediaServer.start(bindAddress: bindAddress);
        if (_disposed || op != _opSequence) return;
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
      _duration = duration ?? Duration.zero;
      _lastError = null;
      _consecutiveStoppedPolls = 0;

      await client.setAvTransportUri(url, metadata);
      if (_disposed || op != _opSequence) {
        _mediaServer.unregister(token);
        if (_token == token) _token = null;
        return;
      }
      await client.play();
      if (_disposed || op != _opSequence) {
        _mediaServer.unregister(token);
        if (_token == token) _token = null;
        return;
      }
      _state = DlnaState.playing;
      _pollFailures = 0;
      _pollStale = false;
      notifyListeners();
      _startPolling();
      await _preQueueNextTrack();
    } catch (error, stackTrace) {
      if (op != _opSequence) return;
      if (token != null) {
        _mediaServer.unregister(token);
        if (_token == token) _token = null;
      }
      _fail(error, stackTrace, 'DLNA play failed');
    }
  }

  /// Plays an arbitrary stream [url] (e.g. from a remote stream) on the
  /// selected renderer after validating it against [RemoteTargetPolicy].
  Future<void> playUrl(
    String url, {
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? mimeType,
  }) {
    _queue = const <DlnaQueueTrack>[];
    _queueIndex = -1;
    return _playUrlInternal(
      url,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      mimeType: mimeType,
    );
  }

  Future<void> _playUrlInternal(
    String url, {
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? mimeType,
  }) async {
    if (_disposed) return;
    final op = ++_opSequence;
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
    if (!await _isAllowedMediaUrl(url, device: device)) {
      if (_disposed || op != _opSequence) return;
      _fail(
        uiError('Invalid DLNA stream URL: $url', code: 'DLNA_INVALID_URL'),
        StackTrace.empty,
        'DLNA play rejected',
      );
      return;
    }
    if (_disposed || op != _opSequence) return;

    _pendingSelectDevice = null;
    final resolvedTitle = title ?? url;
    _lastCastPath = null;
    _lastCastUrl = url;
    _lastCastMimeType = mimeType;
    _lastCastTitle = resolvedTitle;
    _lastCastArtist = artist;
    _lastCastAlbum = album;
    _lastCastDuration = duration;

    try {
      _revokeMediaTokens();
      final metadata = AvTransportClient.buildDidlLiteMetadata(
        url: url,
        title: resolvedTitle,
        artist: artist,
        album: album,
        mimeType: mimeType ?? 'audio/mpeg',
        duration: duration,
      );

      _nowPlayingTitle = resolvedTitle;
      _position = Duration.zero;
      _duration = duration ?? Duration.zero;
      _lastError = null;
      _consecutiveStoppedPolls = 0;

      await client.setAvTransportUri(url, metadata);
      if (_disposed || op != _opSequence) return;
      await client.play();
      if (_disposed || op != _opSequence) return;
      _state = DlnaState.playing;
      _pollFailures = 0;
      _pollStale = false;
      notifyListeners();
      _startPolling();
      await _preQueueNextTrack();
    } catch (error, stackTrace) {
      if (op != _opSequence) return;
      _fail(error, stackTrace, 'DLNA playUrl failed');
    }
  }

  /// Casts [tracks] starting at [startIndex] and wires [next]/[previous] to
  /// step through the queue while pre-queuing each upcoming track.
  Future<void> playQueue(
    List<DlnaQueueTrack> tracks, {
    int startIndex = 0,
  }) async {
    if (_disposed || tracks.isEmpty) return;
    _queue = List<DlnaQueueTrack>.unmodifiable(tracks);
    _queueIndex = startIndex.clamp(0, tracks.length - 1);
    await _playQueueTrack(_queue[_queueIndex]);
  }

  Future<void> _playQueueTrack(DlnaQueueTrack track) async {
    final path = track.path;
    if (path != null && path.isNotEmpty) {
      await _playFileInternal(
        path,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
      );
      return;
    }
    final url = track.url;
    if (url != null && url.isNotEmpty) {
      await _playUrlInternal(
        url,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        mimeType: track.mimeType,
      );
    }
  }

  Future<void> _preQueueNextTrack() async {
    if (_disposed || _queue.isEmpty || _queueIndex + 1 >= _queue.length) return;
    final client = _avTransport;
    final device = _selectedDevice;
    if (client == null || device == null) return;
    final upcoming = _queue[_queueIndex + 1];
    try {
      String? nextUrl = upcoming.url;
      String? mime = upcoming.mimeType;
      int? size;
      var trustedLocalMedia = false;
      if ((nextUrl == null || nextUrl.isEmpty) &&
          upcoming.path != null &&
          _mediaServer.isRunning) {
        final file = File(upcoming.path!);
        if (!await file.exists()) return;
        size = await file.length();
        final nextToken = MediaHttpServer.newToken();
        _mediaServer.register(nextToken, MediaSource.file(upcoming.path!));
        if (_nextToken != null) _mediaServer.unregister(_nextToken!);
        _nextToken = nextToken;
        nextUrl = _mediaServer.uriFor(nextToken).toString();
        mime ??= MediaHttpServer.contentTypeFor(upcoming.path!);
        trustedLocalMedia = true;
      }
      if (nextUrl == null ||
          (!trustedLocalMedia &&
              !await _isAllowedMediaUrl(nextUrl, device: device))) {
        return;
      }
      final metadata = AvTransportClient.buildDidlLiteMetadata(
        url: nextUrl,
        title: upcoming.title ?? nextUrl,
        artist: upcoming.artist,
        album: upcoming.album,
        mimeType: mime ?? 'audio/mpeg',
        size: size,
        duration: upcoming.duration,
      );
      await client.setNextAvTransportUri(nextUrl, metadata);
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA SetNextAVTransportURI failed',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
    }
  }

  Future<bool> _isAllowedMediaUrl(
    String url, {
    required UpnpDeviceDescription device,
  }) async {
    final parsed = Uri.tryParse(url);
    final scheme = parsed?.scheme.toLowerCase();
    if (parsed == null ||
        (scheme != 'http' && scheme != 'https') ||
        parsed.host.isEmpty) {
      return false;
    }
    final allowed = <String>{
      device.location.host.toLowerCase(),
      device.avTransportControlUrl.host.toLowerCase(),
      if (_mediaServer.isRunning &&
          _mediaServer.host != InternetAddress.loopbackIPv4.address)
        _mediaServer.host.toLowerCase(),
      ..._allowedMediaHosts,
    };
    if (RemoteTargetPolicy.classify(url, allowedHostSuffixes: allowed) !=
        RemoteTargetVerdict.allowed) {
      return false;
    }
    if (!RemoteTargetPolicy.hostMatchesAnySuffix(parsed.host, allowed) &&
        !RemoteTargetPolicy.isIpLiteral(parsed.host)) {
      return RemoteTargetPolicy.isSafeHost(parsed.host, lookup: _dnsLookup);
    }
    return true;
  }

  /// Queues [url] as the next track via SetNextAVTransportURI.
  Future<void> queueUrl(
    String url, {
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? mimeType,
  }) async {
    if (_disposed) return;
    final client = _avTransport;
    final device = _selectedDevice;
    if (client == null || device == null) return;
    if (!await _isAllowedMediaUrl(url, device: device)) {
      _fail(
        uiError('Invalid DLNA stream URL: $url', code: 'DLNA_INVALID_URL'),
        StackTrace.empty,
        'DLNA queue rejected',
      );
      return;
    }
    try {
      final metadata = AvTransportClient.buildDidlLiteMetadata(
        url: url,
        title: title ?? url,
        artist: artist,
        album: album,
        mimeType: mimeType ?? 'audio/mpeg',
        duration: duration,
      );
      await client.setNextAvTransportUri(url, metadata);
    } catch (error, stackTrace) {
      _fail(error, stackTrace, 'DLNA queueUrl failed');
    }
  }

  /// Advances to the next track in the loaded queue or asks the renderer.
  Future<void> next() async {
    final client = _avTransport;
    if (_disposed || client == null) return;
    if (_queue.isNotEmpty && _queueIndex + 1 < _queue.length) {
      _queueIndex++;
      await _playQueueTrack(_queue[_queueIndex]);
      return;
    }
    final callback = onNextRequested;
    if (callback != null) {
      await callback();
      return;
    }
    try {
      await client.next();
    } catch (error, stackTrace) {
      _fail(error, stackTrace, 'DLNA next failed');
    }
  }

  /// Returns to the previous track in the loaded queue or asks the renderer.
  Future<void> previous() async {
    final client = _avTransport;
    if (_disposed || client == null) return;
    if (_queue.isNotEmpty && _queueIndex > 0) {
      _queueIndex--;
      await _playQueueTrack(_queue[_queueIndex]);
      return;
    }
    final callback = onPreviousRequested;
    if (callback != null) {
      await callback();
      return;
    }
    try {
      await client.previous();
    } catch (error, stackTrace) {
      _fail(error, stackTrace, 'DLNA previous failed');
    }
  }

  /// Pauses playback on the renderer while keeping polling active to observe
  /// remote resume or stop events on the renderer.
  Future<void> pause() async {
    final client = _avTransport;
    if (_disposed || client == null) return;
    if (_state != DlnaState.playing && _state != DlnaState.buffering) return;
    try {
      await client.pause();
      if (_disposed) return;
      _state = DlnaState.paused;
      _consecutiveStoppedPolls = 0;
      notifyListeners();
      if (_pollTimer == null) _startPolling();
    } catch (error, stackTrace) {
      _fail(error, stackTrace, 'DLNA pause failed');
    }
  }

  /// Resumes playback on the renderer.
  Future<void> resume() async {
    final client = _avTransport;
    if (_disposed || client == null) return;
    if (_state != DlnaState.paused && _state != DlnaState.buffering) return;
    try {
      await client.play();
      if (_disposed) return;
      _state = DlnaState.playing;
      _pollFailures = 0;
      _consecutiveStoppedPolls = 0;
      notifyListeners();
      _startPolling();
    } catch (error, stackTrace) {
      _fail(error, stackTrace, 'DLNA resume failed');
    }
  }

  /// Stops playback on the renderer and revokes the media token.
  Future<void> stop() async {
    if (_disposed) return;
    final op = ++_opSequence;
    final client = _avTransport;
    if (client == null) {
      _revokeMediaTokens();
      return;
    }
    _stopPolling();
    try {
      await client.stop();
      if (_disposed || op != _opSequence) return;
      _state = DlnaState.stopped;
      _nowPlayingTitle = null;
      _position = Duration.zero;
      _queue = const <DlnaQueueTrack>[];
      _queueIndex = -1;
      _consecutiveStoppedPolls = 0;
      notifyListeners();
    } catch (error, stackTrace) {
      if (op != _opSequence) return;
      _fail(error, stackTrace, 'DLNA stop failed');
    } finally {
      _revokeMediaTokens();
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
  /// Retries a pending device selection if connect/switch failed, re-casts the
  /// current file/URL when casting failed, or falls back to discovery.
  Future<void> retry() async {
    if (_disposed) return;
    final pendingSelect = _pendingSelectDevice;
    if (pendingSelect != null) {
      await select(pendingSelect);
      return;
    }
    final path = _lastCastPath;
    if (path != null && _avTransport != null && _selectedDevice != null) {
      await _playFileInternal(
        path,
        title: _lastCastTitle,
        artist: _lastCastArtist,
        album: _lastCastAlbum,
        duration: _lastCastDuration,
      );
      return;
    }
    final url = _lastCastUrl;
    if (url != null && _avTransport != null && _selectedDevice != null) {
      await _playUrlInternal(
        url,
        title: _lastCastTitle,
        artist: _lastCastArtist,
        album: _lastCastAlbum,
        duration: _lastCastDuration,
        mimeType: _lastCastMimeType,
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

  Future<void> _refreshMediaInfo(AvTransportClient client, int op) async {
    try {
      final media = await client.getMediaInfo();
      if (_disposed || op != _opSequence) return;
      if (_nowPlayingTitle == null && media.title != null) {
        _nowPlayingTitle = media.title;
      }
      if (_duration == Duration.zero && media.mediaDuration != null) {
        _duration = media.mediaDuration!;
      }
    } catch (_) {
      // Optional action: renderers that return 501/500 must not break select/poll.
    }
  }

  Future<void> _pollOnce() async {
    if (_disposed || _polling) return;
    final client = _avTransport;
    if (client == null) return;
    final op = _opSequence;
    _polling = true;
    try {
      final position = await client.getPositionInfo();
      final transport = await client.getTransportInfo();
      if (_disposed || op != _opSequence) return;
      _pollFailures = 0;
      if (_pollStale) {
        _pollStale = false;
        _lastError = null;
      }
      final reported = position.position;
      if (reported != null) _position = reported;
      final reportedDuration = position.trackDuration;
      if (reportedDuration != null) _duration = reportedDuration;
      if (_nowPlayingTitle == null || _duration == Duration.zero) {
        await _refreshMediaInfo(client, op);
        if (_disposed || op != _opSequence) return;
      }

      final nextState = _stateFor(transport.state);
      if (nextState == DlnaState.stopped || nextState == DlnaState.idle) {
        final wasActive = _state == DlnaState.playing ||
            _state == DlnaState.paused ||
            _state == DlnaState.buffering;
        if (wasActive) {
          _consecutiveStoppedPolls += 1;
          if (_consecutiveStoppedPolls >= maxConsecutiveStoppedPolls) {
            if (transport.state == TransportState.stopped &&
                !_advancingQueue &&
                _queue.isNotEmpty &&
                _queueIndex + 1 < _queue.length) {
              _consecutiveStoppedPolls = 0;
              _advancingQueue = true;
              try {
                _queueIndex++;
                await _playQueueTrack(_queue[_queueIndex]);
              } finally {
                _advancingQueue = false;
              }
              return;
            }
            _state = nextState;
            _stopPolling();
          }
        } else {
          _state = nextState;
          _stopPolling();
        }
      } else {
        _consecutiveStoppedPolls = 0;
        _state = nextState;
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
        !SsdpClient.isAllowedDescriptionLocation(
            parsed, response.sourceAddress)) {
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
    return _descriptionCache.getOrFetchDeviceDescription(
      location,
      client: _httpClient,
      timeout: _descriptionTimeout,
    );
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
        // Renderer is loading/buffering; keep polling and keep controls responsive.
        return DlnaState.buffering;
      case TransportState.unknown:
        // A renderer reporting UNKNOWN stays in connecting/polling state.
        return DlnaState.connecting;
      case TransportState.stopped:
        return DlnaState.stopped;
    }
  }

  void _revokeMediaTokens() {
    final token = _token;
    _token = null;
    if (token != null) _mediaServer.unregister(token);
    final nextToken = _nextToken;
    _nextToken = null;
    if (nextToken != null) _mediaServer.unregister(nextToken);
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
