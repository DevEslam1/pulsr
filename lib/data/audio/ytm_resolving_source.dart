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
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A [StreamAudioSource] for a YouTube Music track whose stream URL is resolved
/// lazily, on the first byte request rather than up front.
///
/// Hardened with:
/// - Parsing of `expire` query timestamp (proactive re-resolve when < 300s remaining)
/// - Automatic transparent retry on 403 Forbidden / 416 Range Not Satisfiable
/// - Resilient disk cache under application support
class YtmResolvingSource extends StreamAudioSource {
  YtmResolvingSource({
    required this.videoId,
    required Future<String> Function() resolve,
    this.userAgent,
    super.tag,
  }) : resolve = (({bool forceRefresh = false}) => resolve());

  YtmResolvingSource.withRefresh({
    required this.videoId,
    required this.resolve,
    this.userAgent,
    super.tag,
  });

  /// The YouTube video id this source streams; also the disk-cache key.
  final String videoId;

  /// Resolves this track to a currently-valid, direct stream URL.
  final Future<String> Function({bool forceRefresh}) resolve;

  String? userAgent;

  LockCachingAudioSource? _inner;
  Future<LockCachingAudioSource>? _pending;
  DateTime? _resolvedExpiresAt;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    // 1. Proactive expiry check: if URL is within 5 minutes of expiring, discard & re-resolve
    if (_isExpiringSoon()) {
      debugPrint('[YtmResolvingSource] Stream URL for $videoId is expiring soon. Re-resolving...');
      _inner = null;
      _pending = null;
    }

    try {
      final inner = await _ensureInner();
      try {
        return await inner.request(start, end);
      } catch (byteErr) {
        debugPrint('[YtmResolvingSource] Byte stream error ($byteErr) for $videoId. Re-resolving fresh stream...');
        _inner = null;
        _pending = null;
        try {
          final cacheFile = await _cacheFileFor(videoId);
          if (cacheFile.existsSync()) {
            await cacheFile.delete();
          }
        } catch (_) {}
        final freshInner = await _createInner(forceRefresh: true);
        return await freshInner.request(start, end);
      }
    } catch (_) {
      _inner = null;
      _pending = null;
      rethrow;
    }
  }

  bool _isExpiringSoon() {
    final expires = _resolvedExpiresAt;
    if (expires == null) return false;
    final now = DateTime.now();
    return expires.difference(now).inSeconds < 300;
  }

  Future<LockCachingAudioSource> _ensureInner() {
    final existing = _inner;
    if (existing != null && !_isExpiringSoon()) return Future.value(existing);
    return _pending ??= _createInner();
  }

  Future<LockCachingAudioSource> _createInner({bool forceRefresh = false}) async {
    final url = await resolve(forceRefresh: forceRefresh);

    // Parse 'expire' Unix timestamp from query
    try {
      final uri = Uri.parse(url);
      final expireParam = uri.queryParameters['expire'];
      if (expireParam != null) {
        final epochSeconds = int.tryParse(expireParam);
        if (epochSeconds != null) {
          _resolvedExpiresAt = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
        }
      }
    } catch (_) {}

    final cacheFile = await _cacheFileFor(videoId);
    final inner = LockCachingAudioSource(
      Uri.parse(url),
      headers: {
        'User-Agent': userAgent ??
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
      },
      cacheFile: cacheFile,
    );
    _inner = inner;
    return inner;
  }

  static Future<File> _cacheFileFor(String videoId) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'ytm_cache'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final hash = sha256.convert(utf8.encode(videoId)).toString();
    return File(p.join(dir.path, '$hash.m4a'));
  }
}
