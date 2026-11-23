// lib/core/services/ytm_service_dart_resolve.dart
//
// Split out of ytm_service.dart: the pure-Dart InnerTube stream resolver
// used when the native extractor is absent, refused, or out of budget. A
// file split rather than a new abstraction boundary — the extension lives
// in the same library, so it still reaches the service’s clock, channel
// guard, poToken state and URL cache.
part of 'ytm_service.dart';

extension YtmServiceDartResolve on YtmService {
  Future<YtmStream?> _resolveStreamDart(String videoId,
      {String quality = 'high', bool preferM4a = false}) async {
    String apiKey = YtmClientVersionResolver.fallbackApiKey;
    String androidVersion = '19.44.38';
    String androidVrVersion = '1.63.27';
    if (getIt.isRegistered<YtmClientVersionResolver>()) {
      final resolver = getIt<YtmClientVersionResolver>();
      apiKey = resolver.apiKey;
      androidVersion = resolver.androidVersion;
      androidVrVersion = resolver.androidVrVersion;
    }

    String? guestPoToken;
    String? playerPoToken;
    String? guestVisitorData;
    try {
      final poStateFuture =
          getPoTokenState().timeout(const Duration(seconds: 2));
      final playerPoFuture =
          getPlayerPoToken(videoId).timeout(const Duration(seconds: 2));
      final poState = await poStateFuture;
      guestPoToken = poState?['streamingPoToken'] as String?;
      guestVisitorData = poState?['visitorData'] as String?;
      try {
        playerPoToken = await playerPoFuture;
      } catch (e, st) {
        ErrorLogger.log('Non-critical getPlayerPoToken failed',
            error: e, stackTrace: st, category: 'YTM');
      }
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
    }
    final effectivePoToken =
        (playerPoToken != null && playerPoToken.isNotEmpty)
            ? playerPoToken
            : guestPoToken;

    final effectiveAndroidVersion =
        androidVersion == '19.44.38' ? '21.26.364' : androidVersion;
    final List<_DartPlayerClient> clients = [
      (
        name: 'ANDROID',
        version: effectiveAndroidVersion,
        clientNameId: '3',
        ua: 'com.google.android.youtube/$effectiveAndroidVersion (Linux; U; Android 11; en_US) gzip',
        host: 'https://www.youtube.com',
      ),
      (
        name: 'ANDROID_VR',
        version: androidVrVersion,
        clientNameId: '28',
        ua: 'com.google.android.apps.youtube.vr/$androidVrVersion (Linux; U; Android 14; en_US) gzip',
        host: 'https://www.youtube.com',
      ),
      (
        name: 'WEB_EMBEDDED_PLAYER',
        version: '1.20241009.01.00',
        clientNameId: '56',
        ua: 'Mozilla/5.0 (PlayStation; PlayStation 5/2.26) AppleWebKit/605.1.15 (KHTML, like Gecko)',
        host: 'https://www.youtube.com',
      ),
      (
        name: 'TVHTML5_SIMPLY',
        version: '1.0',
        clientNameId: '75',
        ua: 'Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko)',
        host: 'https://www.youtube.com',
      ),
    ];

    Future<YtmStream> attempt(_DartPlayerClient client) async {
      final isEmbed = client.name.contains('EMBED');
      final clientContext = <String, dynamic>{
        'client': {
          'clientName': client.name,
          'clientVersion': client.version,
          'hl': YtmLocale.hl(),
          'gl': YtmLocale.gl(),
          if (guestVisitorData != null && guestVisitorData.isNotEmpty)
            'visitorData': guestVisitorData,
        },
        if (isEmbed)
          'thirdParty': {
            'embedUrl': 'https://www.youtube.com/watch?v=$videoId',
          },
      };

      final body = jsonEncode({
        'context': clientContext,
        'videoId': videoId,
        'racyCheckOk': true,
        'contentCheckOk': true,
        if (isEmbed)
          'thirdParty': {
            'embedUrl': 'https://www.youtube.com/watch?v=$videoId',
          },
        'playbackContext': {
          'contentPlaybackContext': {
            'html5Preference': 'HTML5_PREF_WANTS',
            if (effectivePoToken != null && effectivePoToken.isNotEmpty)
              'poToken': effectivePoToken,
          },
        },
      });

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'User-Agent': client.ua,
        'X-Goog-Api-Key': apiKey,
        'x-youtube-client-name': client.clientNameId,
        'x-youtube-client-version': client.version,
        if (guestVisitorData != null && guestVisitorData.isNotEmpty)
          'X-Goog-Visitor-Id': guestVisitorData,
      };

      final response = await _httpClient
          .post(
            Uri.parse(
                '${client.host}/youtubei/v1/player?prettyPrint=false&key=$apiKey'),
            headers: headers,
            body: body,
          )
          // FIX-C06: 12s timeout per client in _resolveStreamDart
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw YtmException('YTM_HTTP_${response.statusCode}',
            'Dart client ${client.name} answered HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final playability = data['playabilityStatus'] as Map<String, dynamic>?;
      final status = playability?['status'] as String? ?? '';
      if (status == 'LOGIN_REQUIRED' ||
          status == 'UNPLAYABLE' ||
          status.contains('BOT')) {
        final reason = playability?['reason'] as String? ?? '';
        final reasonLower = reason.toLowerCase();
        final isAgeGate = status == 'LOGIN_REQUIRED' &&
            (reasonLower.contains('confirm your age') ||
                reasonLower.contains('confirm you are 18') ||
                reasonLower.contains("confirm you're 18") ||
                reasonLower.contains('age-restricted') ||
                reasonLower.contains('age restricted') ||
                reasonLower.contains('age verification') ||
                reasonLower.contains('inappropriate for some users') ||
                reasonLower.contains('mature content') ||
                reasonLower.contains('over 18'));
        final isBotBlock = !isAgeGate &&
            (status.contains('BOT') ||
                reasonLower.contains('not a bot') ||
                reasonLower.contains('robot') ||
                reasonLower.contains('recaptcha') ||
                reasonLower.contains('automated queries') ||
                reasonLower.contains('unusual traffic') ||
                reasonLower.contains('botguard') ||
                reasonLower.contains('verification required'));
        final errorCode = isAgeGate
            ? 'AGE_RESTRICTED'
            : (isBotBlock
                ? 'BOT_CHALLENGE'
                : (status == 'LOGIN_REQUIRED'
                    ? 'LOGIN_REQUIRED'
                    : 'YTM_UNAVAILABLE'));
        throw YtmException(
          errorCode,
          'Dart client ${client.name} answered playability $status'
          '${reason.isEmpty ? '' : ': $reason'}',
        );
      }

      final streamingData = data['streamingData'] as Map<String, dynamic>?;
      if (streamingData == null) {
        throw YtmException('YTM_UNAVAILABLE',
            'Dart client ${client.name} returned no streamingData');
      }

      final adaptive =
          (streamingData['adaptiveFormats'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();

      final audioFormats = <({Map<String, dynamic> format, String url})>[];
      for (final f in adaptive) {
        final mime = f['mimeType'] as String? ?? '';
        final streamUrl = f['url'] as String?;
        if (mime.startsWith('audio/') &&
            streamUrl != null &&
            streamUrl.isNotEmpty) {
          audioFormats.add((format: f, url: streamUrl));
        }
      }

      if (audioFormats.isEmpty) {
        final formats = (streamingData['formats'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        for (final f in formats) {
          final streamUrl = f['url'] as String?;
          if (streamUrl != null && streamUrl.isNotEmpty) {
            audioFormats.add((format: f, url: streamUrl));
          }
        }
      }

      if (audioFormats.isEmpty) {
        throw YtmException('YTM_UNAVAILABLE',
            'Dart client ${client.name} returned no audio formats');
      }

      final m4a = audioFormats
          .where(
              (f) => ((f.format['mimeType'] as String?) ?? '').contains('mp4'))
          .toList();
      final opus = audioFormats
          .where((f) {
            final mime = ((f.format['mimeType'] as String?) ?? '').toLowerCase();
            return mime.contains('webm') || mime.contains('opus');
          })
          .toList();
      final pool = preferM4a
          ? (m4a.isNotEmpty ? m4a : audioFormats)
          : (opus.isNotEmpty ? opus : (m4a.isNotEmpty ? m4a : audioFormats));

      final selected = switch (quality.toLowerCase()) {
        'low' => pool.reduce((a, b) => ((a.format['bitrate'] as num?) ?? 0) <
                ((b.format['bitrate'] as num?) ?? 0)
            ? a
            : b),
        'medium' => pool.reduce((a, b) =>
            (((a.format['bitrate'] as num?) ?? 128000) - 128000).abs() <
                    (((b.format['bitrate'] as num?) ?? 128000) - 128000).abs()
                ? a
                : b),
        _ => pool.reduce((a, b) => ((a.format['bitrate'] as num?) ?? 0) >
                ((b.format['bitrate'] as num?) ?? 0)
            ? a
            : b),
      };

      final mime = selected.format['mimeType'] as String? ?? 'audio/mp4';
      final bitrate = (selected.format['bitrate'] as num?)?.toInt() ?? 128000;
      final durationMs = int.tryParse(
              selected.format['approxDurationMs']?.toString() ?? '0') ??
          0;
      final details = data['videoDetails'] as Map<String, dynamic>?;
      final audioConfig =
          data['playerConfig']?['audioConfig'] as Map<String, dynamic>?;
      final loudnessDb = (audioConfig?['loudnessDb'] as num?)?.toDouble() ??
          (audioConfig?['perVideoLoudnessDb'] as num?)?.toDouble();

      return YtmStream(
        videoId: videoId,
        url: selected.url,
        mimeType: mime.split(';').first.trim(),
        container: mime.contains('mp4') ? 'm4a' : 'webm',
        bitrateKbps: (bitrate / 1000).round(),
        duration: Duration(milliseconds: durationMs),
        title: details?['title'] as String? ?? '',
        artist: details?['author'] as String? ?? '',
        artworkUrl: null,
        userAgent: client.ua,
        loudnessDb: loudnessDb,
      ).withResolvedExpiry();
    }

    // The three clients are each a full round trip that can hang for its whole
    // 12s budget. Run them as a staggered race instead of back-to-back so one
    // unresponsive client no longer holds the chain hostage: the first client
    // to return usable formats wins and the rest are abandoned. A block or an
    // An empty payload throws (ignored by the race), so only a real success
    // wins; when every client fails this tier answers null, as before.
    try {
      return await HedgedStreamResolver.race<YtmStream>(
        [for (final client in clients) () => attempt(client)],
        hedgeDelay: const Duration(milliseconds: 300),
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      debugPrint('[YTM_SERVICE] Dart InnerTube client race exhausted: $e');
      if (e is YtmException &&
          (e.code == 'BOT_CHALLENGE' ||
              e.code == 'AGE_RESTRICTED' ||
              e.code == 'LOGIN_REQUIRED')) {
        rethrow;
      }
    }

    return null;
  }
}
