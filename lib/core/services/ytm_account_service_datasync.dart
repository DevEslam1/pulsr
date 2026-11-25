// lib/core/services/ytm_account_service_datasync.dart
//
// Split out of ytm_account_service.dart: the account-binding (dataSyncId)
// bootstrap. A file split rather than a new abstraction boundary — the
// extension lives in the same library, so it still reaches the service's
// request helpers, throttle state and diagnostics.
part of 'ytm_account_service.dart';

extension YtmAccountDatasync on YtmAccountService {
  /// Bootstraps [_dataSyncId] with one lightweight authenticated `browse` call
  /// when it is unknown (e.g. right after login before any library fetch).
  ///
  /// The music host does not return the binding in its response context
  /// (verified against the live API: `responseContext` carries no
  /// `mainAppWebResponseContext` at all), so a browse hit is followed by one
  /// visitor-bound retry and then by the WEB account menu, which is the
  /// endpoint that reports the signed-in account's dataSyncId.
  Future<void> _bootstrapDataSyncId() async {
    try {
      final headers = _buildHeaders();
      final body = jsonEncode({
        'context': _buildClientContext('WEB_REMIX'),
        'browseId': 'FEmusic_home',
      });
      final res = await _postWithRetry(
        Uri.parse('${YtmAccountService._innertubeBrowseUrl}&key=$_apiKey'),
        headers: headers,
        body: body,
        baseTimeoutSeconds: 8,
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final before = _dataSyncId;
        _harvestSessionState(json);
        if (_hasDataSyncId(before)) return;

        // The first response can only teach the session its visitorData; the
        // account binding is sometimes returned only on a request that echoes
        // it back. Retry once, immediately, with the harvested identity instead
        // of waiting out the 60 s throttle with a guest pass the whole time.
        if (_sessionVisitorData != null && _sessionVisitorData!.isNotEmpty) {
          final retryRes = await _postWithRetry(
            Uri.parse('${YtmAccountService._innertubeBrowseUrl}&key=$_apiKey'),
            headers: _buildHeaders(),
            body: body,
            baseTimeoutSeconds: 8,
          );
          if (retryRes.statusCode == 200) {
            final retryJson = jsonDecode(retryRes.body) as Map<String, dynamic>;
            _harvestSessionState(retryJson);
            if (_hasDataSyncId(before)) {
              debugPrint(
                  '[YTM_ACCOUNT] datasyncId harvested on the visitor-bound retry');
              return;
            }
          }
        }

        // Last resort: the account menu on the main site.
        if (await _tryAccountMenuDataSyncId(before)) return;

        debugPrint('[YTM_ACCOUNT] datasyncId bootstrap: HTTP 200 but no '
            'datasyncId in response (loggedIn=${!_isUnauthenticatedResponse(json)}, '
            'auth=${isOAuthSession ? 'oauth' : 'cookies'}). Account-bound '
            'playback will stay on the guest pass. $_accountMenuDiagnostic');
      } else {
        debugPrint('[YTM_ACCOUNT] datasyncId bootstrap: HTTP ${res.statusCode} '
            '(auth=${isOAuthSession ? 'oauth' : 'cookies'})');
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] datasyncId bootstrap failed: $e');
    }
  }

  /// Whether [_dataSyncId] holds a binding newer than [before].
  bool _hasDataSyncId(String? before) {
    final current = _dataSyncId;
    return current != null && current.isNotEmpty && current != before;
  }

  /// One authenticated WEB `account_menu` request, harvesting the datasyncId
  /// from its response context. Returns whether the binding was obtained.
  Future<bool> _tryAccountMenuDataSyncId(String? before) async {
    try {
      // The WEB client rejects the music `1.` major with HTTP 400
      // (INVALID_ARGUMENT); the same build stamp under `2.` is accepted.
      final webVersion = _webClientVersion;
      final headers = _buildHeaders(origin: 'https://www.youtube.com')
        ..['x-youtube-client-name'] = '1'
        ..['x-youtube-client-version'] = webVersion;
      final res = await _postWithRetry(
        Uri.parse(
            'https://www.youtube.com/youtubei/v1/account/account_menu?prettyPrint=false&key=$_apiKey'),
        headers: headers,
        body: jsonEncode({
          'context': {
            'client': {
              'clientName': 'WEB',
              'clientVersion': webVersion,
            },
          },
        }),
        baseTimeoutSeconds: 8,
      );
      if (res.statusCode != 200) {
        _accountMenuDiagnostic =
            'WEB account_menu answered HTTP ${res.statusCode}: '
            '${res.body.length > 200 ? res.body.substring(0, 200) : res.body}';
        return false;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      _harvestSessionState(json);
      if (_hasDataSyncId(before)) {
        debugPrint(
            '[YTM_ACCOUNT] datasyncId harvested from the WEB account_menu');
        return true;
      }
      _accountMenuDiagnostic = 'WEB account_menu response keys: '
          'responseContext=${_responseContextKeys(json)}.';
    } catch (e) {
      _accountMenuDiagnostic = 'WEB account_menu failed: $e';
    }
    return false;
  }

  /// Version stamp for WEB client requests.
  String get _webClientVersion => _versionResolver.webClientVersion;

  /// Key names (never values) of the response context, for diagnosing a
  /// missing datasyncId without logging anything account-bound.
  static String _responseContextKeys(Map<String, dynamic> json) {
    final rc = json['responseContext'];
    if (rc is! Map<String, dynamic>) return '<absent>';
    final mainApp = rc['mainAppWebResponseContext'];
    final mainAppKeys =
        mainApp is Map<String, dynamic> ? mainApp.keys.toList() : '<absent>';
    return '${rc.keys.toList()}/mainAppWebResponseContext=$mainAppKeys';
  }
}
