// lib/features/extras/remote_playback_runtime.dart
//
// App-scoped owner of the network-library playback bridge. The loopback server,
// cache and credential store must outlive the Extras screen: the player keeps a
// stream URL open after the user navigates away, and a screen-scoped server
// used to kill playback on back navigation.
import 'dart:async';

import '../../domain/models/remote_source.dart';
import '../remote_sources/remote_cache_store.dart';
import '../remote_sources/remote_credentials_store.dart';
import '../remote_sources/remote_provider_factory.dart';
import '../remote_sources/remote_stream_server.dart';

/// Owns one [RemoteStreamServer] and its cache for the process lifetime.
class RemotePlaybackRuntime {
  RemotePlaybackRuntime({
    RemoteCacheStore? cache,
    RemoteStreamServer? server,
    RemoteCredentialsStore? credentials,
  })  : cache = cache ?? RemoteCacheStore(),
        credentials = credentials ?? RemoteCredentialsStore(),
        _server = server;

  final RemoteCacheStore cache;
  final RemoteCredentialsStore credentials;
  RemoteStreamServer? _server;
  Future<void>? _starting;
  final Map<String, String> _providerSignatures = <String, String>{};
  final Map<String, Future<void>> _inFlightRegistrations =
      <String, Future<void>>{};

  RemoteStreamServer get server => _server ??= RemoteStreamServer(cache: cache);

  bool get isRunning => _server?.isRunning ?? false;

  /// Starts the loopback server once; safe to call concurrently.
  Future<void> ensureStarted() {
    if (_server?.isRunning ?? false) return Future<void>.value();
    final existing = _starting;
    if (existing != null) return existing;
    final future = _start();
    _starting = future;
    return future.whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    final server = this.server;
    await cache.ensureInitialized();
    await server.start();
  }

  /// Registers a provider (reusing unchanged active instances), marks [path]
  /// pinned for caching, and returns the loopback URL handed to the player.
  Future<Uri> prepareUri(RemoteSource source, String path) async {
    await ensureStarted();
    await _ensureProviderRegistered(source);
    await cache.pin(source.id, path);
    return server.uriFor(source, path, pin: true);
  }

  Future<void> _ensureProviderRegistered(RemoteSource source) async {
    final pending = _inFlightRegistrations[source.id];
    if (pending != null) {
      await pending;
      if (server.hasProvider(source.id)) return;
    }
    final future = () async {
      final creds = await credentials.read(source.id);
      final sig = _signatureFor(source, creds);
      if (server.hasProvider(source.id) &&
          _providerSignatures[source.id] == sig) {
        return;
      }
      final provider = createRemoteProvider(source, creds);
      await server.registerProvider(provider);
      _providerSignatures[source.id] = sig;
    }();
    _inFlightRegistrations[source.id] = future;
    try {
      await future;
    } finally {
      if (identical(_inFlightRegistrations[source.id], future)) {
        _inFlightRegistrations.remove(source.id);
      }
    }
  }

  /// Drops any cached provider registration for [sourceId] after an edit.
  Future<void> invalidateSource(String sourceId) async {
    _providerSignatures.remove(sourceId);
    final srv = _server;
    if (srv != null && srv.hasProvider(sourceId)) {
      await srv.unregisterSource(sourceId);
    }
  }

  static String _signatureFor(RemoteSource source, RemoteCredentials? creds) =>
      '${source.kind.name}|${source.authority}|${source.rootPath}|'
      '${source.useTls}|${source.username ?? ''}|'
      '${creds?.username ?? ''}|${creds?.password ?? ''}';

  Future<void> dispose() async {
    final server = _server;
    _server = null;
    _providerSignatures.clear();
    _inFlightRegistrations.clear();
    await server?.stop();
  }
}
