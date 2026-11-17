// lib/core/services/ytm_account_service_parsing.dart
//
// Split out of ytm_account_service.dart: the pure InnerTube payload helpers
// (format URL selection, unauthenticated-response detection, continuation
// token traversal). A file split, not a new abstraction boundary — none of
// these touch instance state beyond the debug log.
part of 'ytm_account_service.dart';

extension YtmAccountParsing on YtmAccountService {
  String? _extractUrlFromFormat(Map<String, dynamic> format) {
    final directUrl = format['url'] as String?;
    if (directUrl != null && directUrl.isNotEmpty) return directUrl;

    // Ciphered formats require JS deciphering (signatureCipher `s` + `n` param).
    // Dart has no Rhino engine; returning the raw `url` without `sig=` produces
    // a 403. Let the native `InnertubeClient` / NewPipe tier (which does
    // `JsDecipherCache.decipherSignature`) handle it. Returning null forces the
    // Dart tier to be skipped and the native hedged race to run.
    final cipher = (format['signatureCipher'] ?? format['cipher']) as String?;
    if (cipher != null && cipher.isNotEmpty) {
      debugPrint(
          '[YTM_ACCOUNT] Skipping ciphered format (itag ${format['itag']}) — needs native decipher');
      return null;
    }
    return null;
  }

  bool _isUnauthenticatedResponse(Map<String, dynamic> json) {
    final rc = json['responseContext'];
    if (rc is Map<String, dynamic>) {
      final mainApp = rc['mainAppWebResponseContext'];
      if (mainApp is Map<String, dynamic>) {
        if (mainApp['loggedOut'] == true) return true;
        if (mainApp['datasyncId'] != null &&
            (mainApp['datasyncId'] as String).isNotEmpty) {
          return false;
        }
      }
    }
    if (json.containsKey('contents') ||
        json.containsKey('header') ||
        json.containsKey('continuationContents') ||
        json.containsKey('onResponseReceivedActions') ||
        json.containsKey('frameworkUpdates')) {
      return false;
    }
    final alerts = json['alerts'];
    if (alerts is List) {
      for (final a in alerts) {
        final alertText = a.toString().toLowerCase();
        if (alertText.contains('sign in') || alertText.contains('login')) {
          return true;
        }
      }
    }
    return false;
  }

  String? _extractContinuationToken(dynamic node, [int depth = 0]) {
    // Iterative guard via depth cap: InnerTube payloads are shallow (<30);
    // anything deeper is malformed — bail instead of stack-overflowing.
    if (depth > 40) return null;
    if (node is Map<String, dynamic>) {
      // Canonical format: nextContinuationData.continuation
      if (node.containsKey('nextContinuationData')) {
        return node['nextContinuationData']?['continuation'] as String?;
      }
      if (node.containsKey('reloadContinuationData')) {
        return node['reloadContinuationData']?['continuation'] as String?;
      }
      // Newer InnerTube format: continuationEndpoint.continuationCommand.token
      if (node.containsKey('continuationEndpoint')) {
        final token = node['continuationEndpoint']?['continuationCommand']
            ?['token'] as String?;
        if (token != null && token.isNotEmpty) return token;
      }
      if (node.containsKey('continuationCommand')) {
        return node['continuationCommand']?['token'] as String?;
      }
      if (node.containsKey('nextRadioContinuationData')) {
        return node['nextRadioContinuationData']?['continuation'] as String?;
      }
      for (final val in node.values) {
        final token = _extractContinuationToken(val, depth + 1);
        if (token != null) return token;
      }
    } else if (node is List) {
      // Cap fan-out to avoid pathological payloads pinning the UI thread.
      final limit = node.length > 500 ? 500 : node.length;
      for (var i = 0; i < limit; i++) {
        final token = _extractContinuationToken(node[i], depth + 1);
        if (token != null) return token;
      }
    }
    return null;
  }
}
