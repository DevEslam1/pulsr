// lib/features/dlna/av_transport.dart
//
// AVTransport:1 SOAP client. Envelopes are built by pure static functions so
// tests can assert the exact bytes sent to a renderer, and responses are read
// with a namespace-tolerant local-name lookup.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/errors/app_error_base.dart';
import 'upnp_entities.dart';

/// Renderer transport state as reported by `GetTransportInfo`.
enum TransportState {
  /// Media is playing.
  playing('PLAYING'),

  /// Playback is paused (playback pause).
  paused('PAUSED_PLAYBACK'),

  /// Recording is paused; some renderers report it instead of playback pause.
  pausedRecording('PAUSED_RECORDING'),

  /// Playback stopped.
  stopped('STOPPED'),

  /// Renderer is changing state.
  transitioning('TRANSITIONING'),

  /// No media is loaded.
  noMedia('NO_MEDIA_PRESENT'),

  /// State missing from the response or not recognised.
  unknown('UNKNOWN');

  /// The literal value used on the wire.
  final String upnpValue;

  const TransportState(this.upnpValue);

  /// Maps a wire value to a state, defaulting to [unknown].
  static TransportState fromUpnp(String? raw) {
    final value = (raw ?? '').trim().toUpperCase();
    for (final state in TransportState.values) {
      if (state.upnpValue == value) return state;
    }
    return TransportState.unknown;
  }

  /// True for both pause flavours a renderer may report.
  bool get isPaused => this == paused || this == pausedRecording;
}

/// Result of `GetTransportInfo`.
class TransportInfo {
  /// Current state reported by the renderer.
  final TransportState state;

  const TransportInfo({required this.state});
}

/// Result of `GetPositionInfo`.
class PositionInfo {
  /// Current playback position (`RelTime`).
  final Duration? position;

  /// Total media duration (`TrackDuration`).
  final Duration? trackDuration;

  /// URI the renderer is playing (`CurrentTrackURI`).
  final String? trackUri;

  const PositionInfo({
    this.position,
    this.trackDuration,
    this.trackUri,
  });
}

/// Result of `GetMediaInfo`.
class MediaInfo {
  /// Currently loaded media URI (`CurrentURI`).
  final String? currentUri;

  /// Raw DIDL-Lite metadata (`CurrentURIMetaData`).
  final String? currentUriMetadata;

  /// Reported duration (`MediaDuration`).
  final Duration? mediaDuration;

  /// Track title decoded from DIDL-Lite metadata when present.
  final String? title;

  /// Artist decoded from DIDL-Lite metadata when present.
  final String? artist;

  /// Album decoded from DIDL-Lite metadata when present.
  final String? album;

  const MediaInfo({
    this.currentUri,
    this.currentUriMetadata,
    this.mediaDuration,
    this.title,
    this.artist,
    this.album,
  });
}

/// A typed failure returned by a UPnP action, including its `errorCode`.
class UpnpActionError extends AppError {
  /// Numeric UPnP error code, e.g. `714`.
  final int? errorCode;

  /// `errorDescription` from the SOAP fault, when present.
  final String? errorDescription;

  /// Action that failed, e.g. `Seek`.
  final String? action;

  const UpnpActionError({
    required super.code,
    required super.userMessage,
    this.errorCode,
    this.errorDescription,
    this.action,
    super.cause,
    super.stackTrace,
  });
}

/// Client for the UPnP `AVTransport:1` service of one renderer.
class AvTransportClient {
  /// AVTransport service type used in `SOAPACTION` and the envelope namespace.
  static const String serviceType =
      'urn:schemas-upnp-org:service:AVTransport:1';

  /// Instance identifier used by every single-instance renderer.
  static const String defaultInstanceId = '0';

  final Uri controlUrl;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;

  /// Creates a client for [controlUrl]. [client] is optional; when omitted the
  /// client creates (and closes) its own HTTP client.
  AvTransportClient(
    this.controlUrl, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _timeout = timeout;

  /// Releases the HTTP client when this instance created it.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Loads [uri] on the renderer with DIDL-Lite [didlMetadata].
  Future<void> setAvTransportUri(String uri, String didlMetadata) async {
    await _invoke(
      'SetAVTransportURI',
      buildSetAvTransportUriEnvelope(uri: uri, didlMetadata: didlMetadata),
    );
  }

  /// Sets the next track URI on the renderer with DIDL-Lite [nextDidlMetadata] for seamless queueing.
  Future<void> setNextAvTransportUri(
      String nextUri, String nextDidlMetadata) async {
    await _invoke(
      'SetNextAVTransportURI',
      buildSetNextAvTransportUriEnvelope(
          nextUri: nextUri, nextDidlMetadata: nextDidlMetadata),
    );
  }

  /// Advances to the next track on the renderer.
  Future<void> next() async {
    await _invoke('Next', buildNextEnvelope());
  }

  /// Returns to the previous track on the renderer.
  Future<void> previous() async {
    await _invoke('Previous', buildPreviousEnvelope());
  }

  /// Starts playback at [speed] (`1` is normal speed).
  Future<void> play({String speed = '1'}) async {
    await _invoke('Play', buildPlayEnvelope(speed: speed));
  }

  /// Pauses playback.
  Future<void> pause() async {
    await _invoke('Pause', buildPauseEnvelope());
  }

  /// Stops playback.
  Future<void> stop() async {
    await _invoke('Stop', buildStopEnvelope());
  }

  /// Seeks to [position] using `REL_TIME`.
  Future<void> seek(Duration position) async {
    await _invoke(
      'Seek',
      buildSeekEnvelope(position: position),
    );
  }

  /// Reads the renderer's current transport state.
  Future<TransportInfo> getTransportInfo() async {
    final body = await _invoke(
      'GetTransportInfo',
      buildGetTransportInfoEnvelope(),
    );
    final state = elementText(body, 'CurrentTransportState');
    return TransportInfo(state: TransportState.fromUpnp(state));
  }

  /// Reads position, duration and current track URI.
  Future<PositionInfo> getPositionInfo() async {
    final body = await _invoke(
      'GetPositionInfo',
      buildGetPositionInfoEnvelope(),
    );
    return PositionInfo(
      position: parseUpnpDuration(elementText(body, 'RelTime')),
      trackDuration: parseUpnpDuration(elementText(body, 'TrackDuration')),
      trackUri: elementText(body, 'CurrentTrackURI'),
    );
  }

  /// Reads current track URI, metadata and total media duration.
  Future<MediaInfo> getMediaInfo() async {
    final body = await _invoke(
      'GetMediaInfo',
      buildGetMediaInfoEnvelope(),
    );
    final metadata = elementText(body, 'CurrentURIMetaData');
    final rawTitle = metadata == null ? null : elementText(metadata, 'title');
    final rawArtist = metadata == null
        ? null
        : (elementText(metadata, 'artist') ?? elementText(metadata, 'creator'));
    final rawAlbum = metadata == null ? null : elementText(metadata, 'album');
    return MediaInfo(
      currentUri: elementText(body, 'CurrentURI'),
      currentUriMetadata: metadata,
      mediaDuration: parseUpnpDuration(elementText(body, 'MediaDuration')),
      title: (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : null,
      artist: (rawArtist != null && rawArtist.isNotEmpty) ? rawArtist : null,
      album: (rawAlbum != null && rawAlbum.isNotEmpty) ? rawAlbum : null,
    );
  }

  Future<String> _invoke(String action, String envelope) async {
    final request = http.Request('POST', controlUrl)
      ..followRedirects = false
      ..headers['Content-Type'] = 'text/xml; charset="utf-8"'
      ..headers['SOAPACTION'] = soapAction(action)
      ..bodyBytes = utf8.encode(envelope);

    final streamed = await _client.send(request).timeout(_timeout);
    const maxBytes = 256 * 1024;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream.timeout(_timeout)) {
      if (builder.length + chunk.length > maxBytes) {
        throw UpnpActionError(
          code: 'DLNA_RESPONSE_TOO_LARGE',
          userMessage: 'The renderer returned an oversized response ($action).',
          action: action,
        );
      }
      builder.add(chunk);
    }
    final bodyBytes = builder.takeBytes();
    final body = utf8.decode(bodyBytes, allowMalformed: true);

    final fault = _faultFrom(body, action);
    if (streamed.statusCode >= 400) {
      if (fault != null) throw fault;
      throw UpnpActionError(
        code: 'DLNA_HTTP_${streamed.statusCode}',
        userMessage:
            'The renderer rejected $action (HTTP ${streamed.statusCode}).',
        action: action,
      );
    }
    if (fault != null) throw fault;
    if (streamed.statusCode != 200) {
      throw UpnpActionError(
        code: 'DLNA_HTTP_${streamed.statusCode}',
        userMessage:
            'The renderer rejected $action (HTTP ${streamed.statusCode}).',
        action: action,
      );
    }
    return body;
  }

  /// Builds the `SOAPACTION` header value, quotes included, exactly as UPnP
  /// renderers expect it.
  static String soapAction(String action) => '"$serviceType#$action"';

  /// Wraps [arguments] in a SOAP 1.1 envelope for [action].
  static String buildSoapEnvelope({
    required String action,
    required String arguments,
  }) {
    return '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
        ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:$action xmlns:u="$serviceType">$arguments</u:$action>'
        '</s:Body>'
        '</s:Envelope>';
  }

  /// Envelope for `SetAVTransportURI`.
  static String buildSetAvTransportUriEnvelope({
    required String uri,
    required String didlMetadata,
    String instanceId = defaultInstanceId,
  }) {
    return buildSoapEnvelope(
      action: 'SetAVTransportURI',
      arguments: '<InstanceID>$instanceId</InstanceID>'
          '<CurrentURI>${escapeXml(uri)}</CurrentURI>'
          '<CurrentURIMetaData>${escapeXml(didlMetadata)}'
          '</CurrentURIMetaData>',
    );
  }

  /// Envelope for `SetNextAVTransportURI`.
  static String buildSetNextAvTransportUriEnvelope({
    required String nextUri,
    required String nextDidlMetadata,
    String instanceId = defaultInstanceId,
  }) {
    return buildSoapEnvelope(
      action: 'SetNextAVTransportURI',
      arguments: '<InstanceID>$instanceId</InstanceID>'
          '<NextURI>${escapeXml(nextUri)}</NextURI>'
          '<NextURIMetaData>${escapeXml(nextDidlMetadata)}'
          '</NextURIMetaData>',
    );
  }

  /// Envelope for `Next`.
  static String buildNextEnvelope({
    String instanceId = defaultInstanceId,
  }) {
    return buildSoapEnvelope(
      action: 'Next',
      arguments: '<InstanceID>$instanceId</InstanceID>',
    );
  }

  /// Envelope for `Previous`.
  static String buildPreviousEnvelope({
    String instanceId = defaultInstanceId,
  }) {
    return buildSoapEnvelope(
      action: 'Previous',
      arguments: '<InstanceID>$instanceId</InstanceID>',
    );
  }

  /// Envelope for `Play`.
  static String buildPlayEnvelope({
    String speed = '1',
    String instanceId = defaultInstanceId,
  }) {
    return buildSoapEnvelope(
      action: 'Play',
      arguments: '<InstanceID>$instanceId</InstanceID>'
          '<Speed>${escapeXml(speed)}</Speed>',
    );
  }

  /// Envelope for `Pause`.
  static String buildPauseEnvelope({
    String instanceId = defaultInstanceId,
  }) {
    return buildSoapEnvelope(
      action: 'Pause',
      arguments: '<InstanceID>$instanceId</InstanceID>',
    );
  }

  /// Envelope for `Stop`.
  static String buildStopEnvelope({String instanceId = defaultInstanceId}) {
    return buildSoapEnvelope(
      action: 'Stop',
      arguments: '<InstanceID>$instanceId</InstanceID>',
    );
  }

  /// Envelope for `Seek` with a `REL_TIME` target of [position].
  static String buildSeekEnvelope({
    required Duration position,
    String unit = 'REL_TIME',
    String instanceId = defaultInstanceId,
  }) {
    return buildSoapEnvelope(
      action: 'Seek',
      arguments: '<InstanceID>$instanceId</InstanceID>'
          '<Unit>${escapeXml(unit)}</Unit>'
          '<Target>${formatUpnpDuration(position)}</Target>',
    );
  }

  /// Envelope for `GetTransportInfo`.
  static String buildGetTransportInfoEnvelope({
    String instanceId = defaultInstanceId,
  }) {
    return buildSoapEnvelope(
      action: 'GetTransportInfo',
      arguments: '<InstanceID>$instanceId</InstanceID>',
    );
  }

  /// Envelope for `GetPositionInfo`.
  static String buildGetPositionInfoEnvelope({
    String instanceId = defaultInstanceId,
  }) {
    return buildSoapEnvelope(
      action: 'GetPositionInfo',
      arguments: '<InstanceID>$instanceId</InstanceID>',
    );
  }

  /// Envelope for `GetMediaInfo`.
  static String buildGetMediaInfoEnvelope({
    String instanceId = defaultInstanceId,
  }) {
    return buildSoapEnvelope(
      action: 'GetMediaInfo',
      arguments: '<InstanceID>$instanceId</InstanceID>',
    );
  }

  /// Builds DIDL-Lite metadata for one audio item served at [url].
  ///
  /// [size] and [duration] become `<res>` attributes when known. Every text
  /// value and attribute is escaped.
  static String buildDidlLiteMetadata({
    required String url,
    String? title,
    String? artist,
    String? album,
    String? mimeType,
    int? size,
    Duration? duration,
    String itemId = '0',
  }) {
    final type =
        (mimeType == null || mimeType.isEmpty) ? 'audio/mpeg' : mimeType;
    final buffer = StringBuffer()
      ..write('<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"')
      ..write(' xmlns:dc="http://purl.org/dc/elements/1.1/"')
      ..write(' xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">')
      ..write('<item id="${escapeXml(itemId)}" parentID="0" restricted="1">');
    if (title != null && title.isNotEmpty) {
      buffer.write('<dc:title>${escapeXml(title)}</dc:title>');
    }
    if (artist != null && artist.isNotEmpty) {
      buffer
        ..write('<dc:creator>${escapeXml(artist)}</dc:creator>')
        ..write('<upnp:artist>${escapeXml(artist)}</upnp:artist>');
    }
    if (album != null && album.isNotEmpty) {
      buffer.write('<upnp:album>${escapeXml(album)}</upnp:album>');
    }
    buffer
      ..write('<upnp:class>object.item.audioItem.musicTrack</upnp:class>')
      ..write('<res protocolInfo="http-get:*:${escapeXml(type)}:*"');
    if (size != null && size >= 0) {
      buffer.write(' size="$size"');
    }
    if (duration != null) {
      buffer.write(' duration="${formatUpnpDuration(duration)}"');
    }
    buffer
      ..write('>')
      ..write(escapeXml(url))
      ..write('</res>')
      ..write('</item>')
      ..write('</DIDL-Lite>');
    return buffer.toString();
  }

  /// Escapes text for embedding in XML character data or attributes.
  static String escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// Formats [value] as `HH:MM:SS`, the `REL_TIME` wire format.
  static String formatUpnpDuration(Duration value) {
    final safe = value.isNegative ? Duration.zero : value;
    final hours = safe.inHours.toString().padLeft(2, '0');
    final minutes = (safe.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (safe.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  /// Parses `H:MM:SS`, `HH:MM:SS` or `MM:SS` (fractional seconds allowed).
  /// Returns `null` for placeholders such as `NOT_IMPLEMENTED`.
  static Duration? parseUpnpDuration(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final secondsPart = parts.last.split('.').first;
    final hours = parts.length == 3 ? int.tryParse(parts[0]) : 0;
    final minutes = int.tryParse(parts[parts.length - 2]);
    final seconds = int.tryParse(secondsPart);
    if (hours == null ||
        minutes == null ||
        seconds == null ||
        hours < 0 ||
        minutes < 0 ||
        seconds < 0) {
      return null;
    }
    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }

  /// Reads the text of the first element with local name [localName],
  /// ignoring namespace prefixes. Entity references are decoded.
  static String? elementText(String xml, String localName) {
    final normalized = xml
        .replaceAll(RegExp(r'<\s*/\s*[A-Za-z_][\w.-]*:'), '</')
        .replaceAll(RegExp(r'<\s*[A-Za-z_][\w.-]*:'), '<');
    final match = RegExp(
      '<$localName\\b[^>]*>(.*?)</$localName\\s*>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match == null) return null;
    return _decodeEntities((match.group(1) ?? '').trim());
  }

  /// Human-readable message for a UPnP error code.
  static String messageForErrorCode(int? errorCode) {
    switch (errorCode) {
      case 401:
        return 'The renderer rejected the request.';
      case 402:
        return 'The renderer reported an invalid request argument.';
      case 501:
        return 'The renderer does not support this action.';
      case 701:
        return 'The renderer cannot change to that state right now.';
      case 702:
        return 'The renderer rejected the media.';
      case 714:
        return 'The renderer rejected that seek position.';
      case 715:
        return 'The renderer does not support seeking in this media.';
      case 716:
        return 'The renderer cannot seek to that position.';
      case 718:
        return 'The renderer rejected the request.';
      default:
        return errorCode == null
            ? 'The renderer reported an error.'
            : 'The renderer reported error $errorCode.';
    }
  }

  static UpnpActionError? _faultFrom(String body, String action) {
    // Only a real `<Fault>` element (optionally namespace-prefixed) or a
    // numeric errorCode counts as a UPnP fault; the word "Fault" elsewhere in
    // a normal response must not be treated as one.
    final hasFaultTag =
        RegExp(r'<\s*(?:[A-Za-z_][\w.-]*:)?Fault(?:\s|>)').hasMatch(body);
    final code = int.tryParse(elementText(body, 'errorCode') ?? '');
    if (!hasFaultTag && code == null) return null;
    final description = elementText(body, 'errorDescription');
    return UpnpActionError(
      code: code == null ? 'DLNA_UPNP_ERROR' : 'DLNA_UPNP_ERROR_$code',
      userMessage: messageForErrorCode(code),
      errorCode: code,
      errorDescription: description,
      action: action,
    );
  }

  static String _decodeEntities(String value) => decodeXmlEntities(value);
}
