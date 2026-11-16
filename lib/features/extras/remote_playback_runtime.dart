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

  /// Registers a provider, pins the path so the cache survives eviction, and
  /// returns the loopback URL handed to the player.
  Future<Uri> prepareUri(RemoteSource source, String path) async {
    await ensureStarted();
    final provider = createRemoteProvider(
      source,
      await credentials.read(source.id),
    );
    server.registerProvider(provider);
    await cache.pin(source.id, path);
    return server.uriFor(source, path);
  }

  Future<void> dispose() async {
    final server = _server;
    _server = null;
    await server?.stop();
  }
}
