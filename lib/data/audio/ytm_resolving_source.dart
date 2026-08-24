// lib/data/audio/ytm_resolving_source.dart
//
// just_audio marks StreamAudioSource / LockCachingAudioSource / StreamAudioResponse
// @experimental. We depend on them deliberately (pinned at just_audio 0.9.46) to
// get lazy resolution + byte caching for YTM inside a ConcatenatingAudioSource.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A [StreamAudioSource] for a YouTube Music track whose stream URL is resolved
/// lazily, on the first byte request rather than up front.
///
/// YTM URLs expire within hours and are pinned to the device IP, so resolving
/// an entire queue eagerly is both wasteful and fragile. Deferring resolution
/// to the moment ExoPlayer actually asks for bytes keeps the URL fresh. Once
/// resolved, byte streaming, HTTP range support and on-disk caching are handed
/// off to just_audio's own [LockCachingAudioSource], so a backward seek after
/// buffering is served from the cache instead of re-hitting a (possibly
/// expired) URL. Because this presents as a plain [StreamAudioSource], a YTM
/// track can live inside a [ConcatenatingAudioSource] and join gaplessly,
/// exactly like a local file.
class YtmResolvingSource extends StreamAudioSource {
  YtmResolvingSource({
    required this.videoId,
    required this.resolve,
    super.tag,
  });

  /// The YouTube video id this source streams; also the disk-cache key.
  final String videoId;

  /// Resolves this track to a currently-valid, direct stream URL. Injected by
  /// the audio handler so this class stays free of YTM-service and settings
  /// concerns — offline/Wi-Fi/quality gating and URL memoization all live in
  /// the resolver, which may throw (e.g. `YtmException`) to fail the request.
  final Future<String> Function() resolve;

  LockCachingAudioSource? _inner;
  Future<LockCachingAudioSource>? _pending;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    try {
      final inner = await _ensureInner();
      return await inner.request(start, end);
    } catch (_) {
      // Drop the resolved source so the next request re-resolves a fresh URL
      // instead of retrying a dead/expired one forever.
      _inner = null;
      _pending = null;
      rethrow;
    }
  }

  Future<LockCachingAudioSource> _ensureInner() {
    final existing = _inner;
    if (existing != null) return Future.value(existing);
    return _pending ??= _createInner();
  }

  Future<LockCachingAudioSource> _createInner() async {
    final url = await resolve();
    final cacheFile = await _cacheFileFor(videoId);
    final inner = LockCachingAudioSource(Uri.parse(url), cacheFile: cacheFile);
    _inner = inner;
    return inner;
  }

  /// A durable, per-track cache file. Lives under application support (not the
  /// OS temp dir) so a fetched track survives storage pressure and remains
  /// available for offline back-seek / replay.
  static Future<File> _cacheFileFor(String videoId) async {
    final base = await getApplicationSupportDirectory();
    final hash = sha256.convert(utf8.encode(videoId)).toString();
    return File(p.join(base.path, 'ytm_cache', '$hash.m4a'));
  }
}
