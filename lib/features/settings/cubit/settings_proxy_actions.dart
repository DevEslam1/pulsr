part of 'settings_cubit.dart';

mixin SettingsProxyActions on PulsrCubit<SettingsState> {
  Future<void> _syncProxySettings(ProxyConfig config) async {
    // 1. Synchronize Dart HttpOverrides
    AppHttpOverrides.instance.update(config);

    // 2. Synchronize Android Native / NewPipe / JVM Proxy
    // FIX-E03: Add platform check to prevent MissingPluginException on desktop
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await SettingsCubit._proxyChannel.invokeMethod('setProxy', config.toMap());
    } catch (e) {
      debugPrint('[SettingsCubit] Failed to sync proxy to native channel: $e');
    }
  }

  /// Reads the entry-ID-keyed proxy pool credentials out of secure storage.
  Future<Map<String, String>> _readProxyPoolSecrets() async {
    final secrets = <String, String>{};
    final raw = await _safeSecureRead(SettingsCubit._keyProxyListPasswordsSecure);
    if (raw == null || raw.isEmpty) return secrets;
    try {
      (jsonDecode(raw) as Map<String, dynamic>).forEach((id, value) {
        if (value is String && value.isNotEmpty) secrets[id] = value;
      });
    } catch (_) {}
    return secrets;
  }

  Future<String?> _safeSecureRead(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to read secure storage key: $key',
        error: e,
        stackTrace: st,
        category: 'SettingsCubit',
      );
      return null;
    }
  }

  Future<void> setProxyEnabled(bool enabled) async {
    _proxyDirty = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsCubit._keyProxyEnabled, enabled);
    final updated = state.copyWith(proxyEnabled: enabled);
    safeEmit(updated);
    if (!enabled) {
      await _syncProxySettings(const ProxyConfig(enabled: false));
    } else {
      await _syncProxySettings(activeProxyConfig.copyWith(enabled: true));
    }
  }

  Future<void> setProxySettings({
    required bool enabled,
    required AppProxyType type,
    required String host,
    required int port,
    String? username,
    String? password,
    String? bypassHosts,
  }) async {
    _proxyDirty = true;
    final trimmedHost = host.trim();
    if (enabled) {
      final validationError =
          validateProxyHostAndPort(host: trimmedHost, port: port);
      if (validationError != null) {
        safeEmit(state.copyWith(errorMessage: validationError));
        return;
      }
    }

    final pass = password ?? '';
    _proxyPassword = pass;
    final newConfig = ProxyConfig(
      enabled: enabled,
      type: type,
      host: trimmedHost,
      port: port,
      username: username?.trim() ?? '',
      password: pass,
      bypassHosts: bypassHosts ?? 'localhost, 127.0.0.1',
    );

    final updated = state.copyWith(
      proxyEnabled: newConfig.enabled,
      proxyType: newConfig.type,
      proxyHost: newConfig.host,
      proxyPort: newConfig.port,
      proxyUsername: newConfig.username,
      hasProxyPassword: newConfig.password.isNotEmpty,
      proxyBypassHosts: newConfig.bypassHosts,
    );

    safeEmit(updated);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsCubit._keyProxyEnabled, newConfig.enabled);
    await prefs.setString(SettingsCubit._keyProxyType, newConfig.type.name);
    await prefs.setString(SettingsCubit._keyProxyHost, newConfig.host);
    await prefs.setInt(SettingsCubit._keyProxyPort, newConfig.port);
    await prefs.setString(SettingsCubit._keyProxyUsername, newConfig.username);
    try {
      if (newConfig.password.isNotEmpty) {
        await _secureStorage.write(
          key: SettingsCubit._keyProxyPasswordSecure,
          value: newConfig.password,
        );
      } else {
        await _secureStorage.delete(key: SettingsCubit._keyProxyPasswordSecure);
      }
    } catch (_) {}
    await prefs.remove(SettingsCubit._keyProxyPassword);
    await prefs.setString(SettingsCubit._keyProxyBypassHosts, newConfig.bypassHosts);

    await _syncProxySettings(newConfig);
  }

  /// Persists the pool with credentials split out: the prefs JSON is
  /// password-free and the secrets live in secure storage, keyed by entry ID.
  Future<void> _saveProxyList(List<ProxyEntry> list) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = list.map((e) => e.toMap()..remove('password')).toList();
    await prefs.setString(SettingsCubit._keyProxyList, jsonEncode(jsonList));

    final secrets = <String, String>{
      for (final e in list)
        if (e.password.isNotEmpty) e.id: e.password,
    };
    try {
      if (secrets.isEmpty) {
        await _secureStorage.delete(key: SettingsCubit._keyProxyListPasswordsSecure);
      } else {
        await _secureStorage.write(
          key: SettingsCubit._keyProxyListPasswordsSecure,
          value: jsonEncode(secrets),
        );
      }
    } catch (e, st) {
      // The pool itself is saved either way; only the credentials are lost, and
      // failing loudly here beats silently writing them back out in plaintext.
      ErrorLogger.log(
        'Failed to persist proxy pool credentials to secure storage',
        error: e,
        stackTrace: st,
        category: 'SettingsCubit',
      );
    }
  }

  /// Imports multiple proxies parsed from raw multi-line text or file content.
  /// Returns the count of newly added proxies.
  Future<int> importProxiesFromText(
    String rawText, {
    bool autoSelectFirst = false,
  }) async {
    final parsed = ProxyEntry.parseList(rawText);
    if (parsed.isEmpty) return 0;

    final existing = List<ProxyEntry>.from(state.proxyList);
    final existingKeys =
        existing.map((e) => '${e.host}:${e.port}:${e.username}').toSet();

    int addedCount = 0;
    for (final p in parsed) {
      final key = '${p.host}:${p.port}:${p.username}';
      if (!existingKeys.contains(key)) {
        existing.add(p);
        existingKeys.add(key);
        addedCount++;
      }
    }

    if (addedCount > 0) {
      safeEmit(state.copyWith(proxyList: existing));
      await _saveProxyList(existing);
      if (autoSelectFirst && existing.isNotEmpty) {
        await selectProxyEntry(parsed.first);
      }
    }
    return addedCount;
  }

  /// Adds or updates a single proxy entry in the pool.
  Future<void> addProxyEntry(
    ProxyEntry entry, {
    bool autoSelect = false,
  }) async {
    final existing = List<ProxyEntry>.from(state.proxyList);
    final index = existing.indexWhere(
      (e) => e.id == entry.id || (e.host == entry.host && e.port == entry.port),
    );
    if (index >= 0) {
      existing[index] = entry;
    } else {
      existing.add(entry);
    }
    safeEmit(state.copyWith(proxyList: existing));
    await _saveProxyList(existing);
    if (autoSelect) {
      await selectProxyEntry(entry);
    }
  }

  /// Removes a proxy from the pool by ID.
  Future<void> removeProxyEntry(String id) async {
    final updated = state.proxyList.where((e) => e.id != id).toList();
    safeEmit(state.copyWith(proxyList: updated));
    await _saveProxyList(updated);
  }

  /// Clears the entire proxy pool.
  Future<void> clearProxyList() async {
    safeEmit(state.copyWith(proxyList: []));
    await _saveProxyList([]);
  }

  /// Selects a proxy from the pool and activates it as the current active proxy.
  Future<void> selectProxyEntry(ProxyEntry entry) async {
    await setProxySettings(
      enabled: true,
      type: entry.type,
      host: entry.host,
      port: entry.port,
      username: entry.username,
      password: entry.password,
      bypassHosts: state.proxyBypassHosts,
    );
  }

  /// Concurrently tests all proxies in the pool in parallel batches of 5
  /// against the probe endpoint, updating live latency and working status for each proxy.
  Future<void> testAllProxies() async {
    if (state.proxyList.isEmpty || state.isTestingAllProxies) return;

    safeEmit(state.copyWith(isTestingAllProxies: true));
    try {
      final ids = state.proxyList.map((e) => e.id).toList();

      for (int i = 0; i < ids.length; i += 5) {
        // Re-read the live pool for every batch: the user can add or remove
        // proxies while the probes run, and writing back a start-of-run
        // snapshot would resurrect removed entries and drop new ones.
        final batchIds = ids.sublist(i, math.min(i + 5, ids.length)).toSet();
        final batch =
            state.proxyList.where((e) => batchIds.contains(e.id)).toList();
        if (batch.isEmpty) continue;

        _mergeProxyEntries({
          for (final e in batch) e.id: e.copyWith(isTesting: true),
        });

        final probed = await Future.wait(batch.map(_probeProxyEntry));
        if (isClosed) return;
        _mergeProxyEntries({for (final e in probed) e.id: e});
      }
      await _saveProxyList(state.proxyList);
    } finally {
      safeEmit(state.copyWith(isTestingAllProxies: false));
    }
  }

  /// Writes probe results back onto the current pool by ID, leaving entries the
  /// user touched mid-run alone.
  void _mergeProxyEntries(Map<String, ProxyEntry> updates) {
    safeEmit(
      state.copyWith(
        proxyList: [
          for (final entry in state.proxyList) updates[entry.id] ?? entry,
        ],
      ),
    );
  }

  Future<ProxyEntry> _probeProxyEntry(ProxyEntry entry) async {
    try {
      final result = await AppHttpOverrides.instance.testConnection(
        configToTest: entry.toProxyConfig(enabled: true),
        timeout: const Duration(seconds: 10),
      );
      return entry.copyWith(
        isTesting: false,
        isWorking: result.success,
        latencyMs: result.latencyMs,
        lastError: result.error,
        clearLastError: result.error == null,
      );
    } catch (e) {
      return entry.copyWith(
        isTesting: false,
        isWorking: false,
        lastError: e.toString(),
      );
    }
  }

  /// Tests a single proxy entry in the pool by its ID.
  Future<void> testSingleProxyEntry(String id) async {
    final index = state.proxyList.indexWhere((e) => e.id == id);
    if (index < 0) return;

    final entry = state.proxyList[index];
    _mergeProxyEntries({id: entry.copyWith(isTesting: true)});

    final probed = await _probeProxyEntry(entry);
    if (isClosed) return;
    _mergeProxyEntries({id: probed});
    await _saveProxyList(state.proxyList);
  }

  /// Sorts proxy entries by lowest latency first, followed by unverified/failed ones.
  Future<void> sortProxiesByLatency() async {
    final list = List<ProxyEntry>.from(state.proxyList);
    list.sort((a, b) {
      if (a.isWorking == true && b.isWorking == true) {
        return (a.latencyMs ?? 99999).compareTo(b.latencyMs ?? 99999);
      }
      if (a.isWorking == true && b.isWorking != true) return -1;
      if (a.isWorking != true && b.isWorking == true) return 1;
      return 0;
    });
    safeEmit(state.copyWith(proxyList: list));
    await _saveProxyList(list);
  }




























  // Requires: provided by the composing class (same library).
  FlutterSecureStorage get _secureStorage;

  // Requires: provided by the composing class (same library).
  // ignore: unused_element
  bool get _proxyDirty;
  set _proxyDirty(bool value);

  // Requires: provided by the composing class (same library).
  // ignore: unused_element
  String get _proxyPassword;
  set _proxyPassword(String value);

  // Requires: provided by the composing class (same library).
  ProxyConfig get activeProxyConfig;
}
