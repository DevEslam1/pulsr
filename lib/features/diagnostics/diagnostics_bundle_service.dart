// lib/features/diagnostics/diagnostics_bundle_service.dart
//
// Builds the support bundle a user can send after an audio problem: app and
// device identity, USB diagnostics, DSP stage flags, per-path xrun counters, the
// recent log tail and a redacted preference snapshot. Everything that leaves
// the process goes through [DiagnosticsBundleService.redactText], so paths,
// credentials and tokens never reach the shared file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/errors/app_error.dart';
import '../../core/utils/error_logger.dart';
import '../../data/services/usb_exclusive_service.dart';
import 'diagnostics_log_buffer.dart';
import 'diagnostics_strings.dart';

/// Reads an output-device summary from the injected audio layer.
typedef DiagnosticsMapProbe = Map<String, Object?> Function();

/// Reads a map from an async native probe.
typedef DiagnosticsAsyncMapProbe = Future<Map<String, Object?>> Function();

/// One built diagnostics bundle.
class DiagnosticsBundle {
  const DiagnosticsBundle({
    required this.generatedAt,
    required this.app,
    required this.outputDevice,
    required this.usb,
    required this.dspStages,
    required this.outputPathCounters,
    required this.logLines,
    required this.preferences,
  });

  /// When the bundle was collected.
  final DateTime generatedAt;

  /// App version, platform and build mode.
  final Map<String, Object?> app;

  /// Output-device summary supplied by the caller.
  final Map<String, Object?> outputDevice;

  /// Raw USB diagnostics, empty when the native side is unavailable.
  final Map<String, Object?> usb;

  /// One entry per DSP stage: `stage`, `enabled`, `detail`.
  final List<Map<String, Object?>> dspStages;

  /// Per-output-path xrun/underrun counters with a `reported` flag.
  final Map<String, Object?> outputPathCounters;

  /// Recent log lines, already redacted.
  final List<String> logLines;

  /// Redacted preference values keyed by preference name.
  final Map<String, Object?> preferences;

  /// Number of DSP stages that are switched on.
  int get enabledDspStageCount =>
      dspStages.where((stage) => stage['enabled'] == true).length;

  /// Serializable form written to `bundle.json`.
  Map<String, Object?> toJson() => <String, Object?>{
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'app': app,
        'outputDevice': outputDevice,
        'usb': usb,
        'dspStages': dspStages,
        'outputPaths': outputPathCounters,
        'logs': logLines,
        'preferences': preferences,
      };
}

/// Raised when the bundle cannot be written to disk.
class DiagnosticsBundleError extends AppError {
  const DiagnosticsBundleError({
    required super.code,
    required super.userMessage,
    super.cause,
    super.stackTrace,
  });
}

/// Collects and exports diagnostics bundles.
class DiagnosticsBundleService {
  DiagnosticsBundleService({
    required SharedPreferences prefs,
    DiagnosticsMapProbe? outputDevice,
    DiagnosticsAsyncMapProbe? usbDiagnostics,
    DiagnosticsMapProbe? outputPathCounters,
    String Function()? appVersion,
    DateTime Function()? clock,
    Future<Directory> Function()? tempDirectory,
  })  : _prefs = prefs,
        _outputDevice = outputDevice,
        _usbDiagnostics = usbDiagnostics ?? _defaultUsbDiagnostics,
        _countersProbe = outputPathCounters,
        _appVersion = appVersion ?? (() => AppConfig.appVersion),
        _clock = clock ?? DateTime.now,
        _tempDirectory = tempDirectory ??
            (() => Directory.systemTemp.createTemp('pulsr_diagnostics_'));

  /// File name of the JSON bundle.
  static const String bundleFileName = 'bundle.json';

  /// File name of the plain-text log tail.
  static const String logFileName = 'bundle.log';

  /// How long a native USB probe may take before it is reported unavailable.
  static const Duration usbProbeTimeout = Duration(seconds: 2);

  static const List<String> _outputPaths = <String>[
    'primary',
    'usb_exclusive',
    'aaudio',
  ];

  static final RegExp _windowsPath = RegExp(r'\b[A-Za-z]:\\[^\s"<>|]*');
  static final RegExp _devicePath =
      RegExp(r'/(?:storage|sdcard|mnt|system|vendor)/[^\s"<>|]*');
  static final RegExp _androidDataPath =
      RegExp(r'/Android/(?:data|obb)/[^\s"<>|]*');
  static final RegExp _homePath = RegExp(r'(?:/Users/|/home/)[^\s"<>|]*');
  static final RegExp _androidInternalPath = RegExp(
    r'/data/(?:user/\d+|data|app|misc)(?:/[^\s"<>|]*)?',
  );
  static final RegExp _optPath = RegExp(r'/opt/[^\s"<>|]*');
  static final RegExp _uncPath = RegExp(r'\\\\[^\s"<>|\\/]+\\[^\s"<>|]*');
  static final RegExp _fileUri = RegExp(r'\bfile://[^\s"<>|]*');
  static final RegExp _contentUri = RegExp(r'\bcontent://[^\s"<>|]*');
  static final RegExp _urlUserInfo =
      RegExp(r'([A-Za-z][A-Za-z0-9+.\-]*://)[^\s/@]+@');
  static final RegExp _credentialPair = RegExp(
    r'''(["']?)\b(password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|'''
    r'''client[_-]?secret|authorization|cookie|session[_-]?id|username)\b\1'''
    r'''(\s*[:=]\s*)'''
    r'''(?:(["'])(?:\\.|(?!\4)[^\r\n\\])*\4|[^\s,;"}]+)''',
    caseSensitive: false,
  );
  static final RegExp _privateIpv4 = RegExp(
    r'\b(?:10(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}|'
    r'172\.(?:1[6-9]|2\d|3[01])(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){2}|'
    r'192\.168(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){2}|'
    r'127(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}|'
    r'169\.254(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){2})\b',
  );
  static final RegExp _privateIpv6 = RegExp(
    r'(?:::1(?!\w)|'
    r'\bfe[89ab][0-9a-fA-F]:[0-9a-fA-F:]*\b|'
    r'\bf[cd][0-9a-fA-F]{2}:[0-9a-fA-F:]*\b)',
    caseSensitive: false,
  );
  static final RegExp _authorizationScheme =
      RegExp(r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=\-]+', caseSensitive: false);
  static final RegExp _sensitiveKey = RegExp(
    r'(password|passwd|pwd|secret|token|cookie|authorization|credential|'
    r'api[_-]?key|session|email|phone|account|user_id|auth|proxy)',
    caseSensitive: false,
  );

  final SharedPreferences _prefs;
  final DiagnosticsMapProbe? _outputDevice;
  final DiagnosticsAsyncMapProbe _usbDiagnostics;
  final DiagnosticsMapProbe? _countersProbe;
  final String Function() _appVersion;
  final DateTime Function() _clock;
  final Future<Directory> Function() _tempDirectory;
  Directory? _lastExportDirectory;

  /// Replaces every value that could identify the user or grant access.
  ///
  /// Runs [ErrorLogger.redactPii] first (emails, cookies, auth headers, user
  /// paths) and then this module's own passes for URL user-info, credential
  /// pairs, bearer tokens, Windows/POSIX home paths, device storage paths and
  /// file/content URIs.
  static String redactText(String input) {
    var output = ErrorLogger.redactPii(input);
    output = output.replaceAllMapped(
      _urlUserInfo,
      (match) => '${match.group(1)}[REDACTED_CREDENTIALS]@',
    );
    output = output.replaceAllMapped(
      _credentialPair,
      (match) {
        final keyQuote = match.group(1) ?? '';
        final key = match.group(2) ?? '';
        final sep = match.group(3) ?? '=';
        final valQuote = match.group(4) ?? '';
        return '$keyQuote$key$keyQuote$sep$valQuote[REDACTED_SECRET]$valQuote';
      },
    );
    output = output.replaceAll(_privateIpv4, '[REDACTED_IP]');
    output = output.replaceAll(_privateIpv6, '[REDACTED_IP]');
    output = output.replaceAllMapped(
      _authorizationScheme,
      (match) => '${match.group(1)} [REDACTED_TOKEN]',
    );
    output = output.replaceAllMapped(_fileUri, (_) => 'file://[REDACTED_PATH]');
    output = output.replaceAllMapped(
      _contentUri,
      (_) => 'content://[REDACTED_URI]',
    );
    output = output.replaceAllMapped(_windowsPath, (_) => '[REDACTED_PATH]');
    output = output.replaceAllMapped(_uncPath, (_) => '[REDACTED_PATH]');
    output = output.replaceAllMapped(_homePath, (_) => '[REDACTED_PATH]');
    output = output.replaceAllMapped(
      _androidDataPath,
      (_) => '[REDACTED_PATH]',
    );
    output = output.replaceAllMapped(
      _androidInternalPath,
      (_) => '[REDACTED_PATH]',
    );
    output = output.replaceAllMapped(_optPath, (_) => '[REDACTED_PATH]');
    output = output.replaceAllMapped(_devicePath, (_) => '[REDACTED_PATH]');
    return output;
  }

  /// Collects one bundle. Native probes are guarded individually, so a missing
  /// platform channel degrades one section instead of failing the export.
  Future<DiagnosticsBundle> build() async {
    final now = _clock();
    return DiagnosticsBundle(
      generatedAt: now,
      app: _appSection(now),
      outputDevice: _probeMap(
        _outputDevice,
        'output device',
        fallback: <String, Object?>{
          'status': DiagnosticsStrings.deviceUnknown,
        },
      ),
      usb: await _usbSection(),
      dspStages: _dspStages(),
      outputPathCounters: _buildCounters(),
      logLines: DiagnosticsLogBuffer.snapshot()
          .map(redactText)
          .toList(growable: false),
      preferences: _redactedPreferences(),
    );
  }

  /// Writes `bundle.json` and `bundle.log` into a fresh temporary directory and
  /// returns both as shareable files.
  ///
  /// The directory is retained until [cleanupExport] runs, because the share
  /// target reads the files after this future completes. A new export first
  /// removes the previous directory, so a caller that forgets the cleanup can
  /// accumulate at most one bundle.
  Future<List<XFile>> export({DiagnosticsBundle? bundle}) async {
    final target = bundle ?? await build();
    Directory? directory;
    try {
      await _cleanupPreviousExport();
      directory = await _tempDirectory();
      _lastExportDirectory = directory;
      final jsonFile = File(p.join(directory.path, bundleFileName));
      await jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(target.toJson()),
        flush: true,
      );
      final logFile = File(p.join(directory.path, logFileName));
      await logFile.writeAsString(
        target.logLines.map(redactText).join('\n'),
        flush: true,
      );
      return <XFile>[
        XFile(jsonFile.path, mimeType: 'application/json'),
        XFile(logFile.path, mimeType: 'text/plain'),
      ];
    } catch (e, st) {
      await _cleanupDirectory(directory ?? _lastExportDirectory);
      ErrorLogger.log(
        'Exporting the diagnostics bundle failed',
        error: e,
        stackTrace: st,
        category: 'DiagnosticsBundle',
      );
      throw DiagnosticsBundleError(
        code: 'diagnostics-export-failed',
        userMessage: DiagnosticsStrings.exportFailed,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deletes the temporary directory created by the most recent [export].
  ///
  /// Call this after the share sheet has consumed the files (or on dispose);
  /// it is idempotent and never throws. Keeping the cleanup explicit avoids
  /// pulling files out from under an in-flight share target.
  Future<void> cleanupExport() async {
    final directory = _lastExportDirectory;
    _lastExportDirectory = null;
    await _cleanupDirectory(directory);
  }

  Future<void> _cleanupPreviousExport() async {
    final previous = _lastExportDirectory;
    _lastExportDirectory = null;
    await _cleanupDirectory(previous);
  }

  Future<void> _cleanupDirectory(Directory? directory) async {
    if (directory == null) return;
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Removing the diagnostics bundle directory failed',
        error: e,
        stackTrace: st,
        category: 'DiagnosticsBundle',
      );
    }
  }

  Map<String, Object?> _appSection(DateTime now) => <String, Object?>{
        'appVersion': _appVersion(),
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'buildMode': kDebugMode
            ? DiagnosticsStrings.buildModeDebug
            : kReleaseMode
                ? DiagnosticsStrings.buildModeRelease
                : DiagnosticsStrings.buildModeProfile,
        'flavor': AppConfig.flavor,
        'locale': Platform.localeName,
        'generatedAt': now.toUtc().toIso8601String(),
      };

  Future<Map<String, Object?>> _usbSection() async {
    try {
      final raw = await _usbDiagnostics().timeout(usbProbeTimeout);
      return _sanitizeMap(raw);
    } catch (e, st) {
      ErrorLogger.log(
        'USB diagnostics unavailable for the bundle',
        error: e,
        stackTrace: st,
        category: 'DiagnosticsBundle',
      );
      return <String, Object?>{'status': 'unavailable'};
    }
  }

  List<Map<String, Object?>> _dspStages() {
    bool enabled(String key) => _prefs.getBool(key) ?? false;
    String detail(String key, String fallback) => _stringValue(key) ?? fallback;
    String intDetail(String key, String fallback) =>
        _intValue(key)?.toString() ?? fallback;
    return <Map<String, Object?>>[
      <String, Object?>{
        'stage': 'equalizer',
        'enabled': enabled(PrefsKeys.eqEnabled),
        'detail': detail(PrefsKeys.eqPresetName, 'flat'),
      },
      <String, Object?>{
        'stage': 'crossfeed',
        'enabled': enabled(PrefsKeys.crossfeedEnabled),
        'detail': intDetail(PrefsKeys.crossfeedMode, 'off'),
      },
      <String, Object?>{
        'stage': 'saturation',
        'enabled': enabled(PrefsKeys.saturationEnabled),
        'detail': intDetail(PrefsKeys.saturationMode, 'off'),
      },
      <String, Object?>{
        'stage': 'stereo_width',
        'enabled': enabled(PrefsKeys.stereoWidthEnabled),
        'detail': enabled(PrefsKeys.stereoWidthMultiband)
            ? 'multiband'
            : 'single-band',
      },
      <String, Object?>{
        'stage': 'dynamic_bass',
        'enabled': enabled(PrefsKeys.dynamicBassEnabled),
        'detail': intDetail(PrefsKeys.dynamicBassPreset, 'flat'),
      },
      <String, Object?>{
        'stage': 'multiband_compressor',
        'enabled': enabled(PrefsKeys.multibandCompressorEnabled),
        'detail': '${_multibandBandCount()} bands',
      },
      <String, Object?>{
        'stage': 'convolution_reverb',
        'enabled': enabled(PrefsKeys.convolutionReverbEnabled),
        'detail': intDetail(PrefsKeys.convolutionReverbPreset, 'none'),
      },
      <String, Object?>{
        'stage': 'limiter',
        'enabled': enabled(PrefsKeys.lookaheadLimiterEnabled),
        'detail':
            '${_doubleValue(PrefsKeys.lookaheadLimiterThresholdDb) ?? 0} dB',
      },
      <String, Object?>{
        'stage': 'dither',
        'enabled': enabled(PrefsKeys.ditherEnabled),
        'detail': '${_intValue(PrefsKeys.ditherTargetBitDepth) ?? 24}-bit',
      },
      <String, Object?>{
        'stage': 'dac_voicing',
        'enabled': enabled(PrefsKeys.dacVoicingEnabled),
        'detail': intDetail(PrefsKeys.dacVoicingCharacter, 'neutral'),
      },
      <String, Object?>{
        'stage': 'loudness_contour',
        'enabled': enabled(PrefsKeys.loudnessContourEnabled),
        'detail':
            '${_doubleValue(PrefsKeys.loudnessContourIntensity) ?? 0.0}',
      },
      <String, Object?>{
        'stage': 'sub_crossover',
        'enabled': enabled(PrefsKeys.subCrossoverEnabled),
        'detail':
            '${_doubleValue(PrefsKeys.subCrossoverCornerHz) ?? 80.0} Hz',
      },
      <String, Object?>{
        'stage': 'dynamic_eq',
        'enabled': enabled(PrefsKeys.dynamicEqEnabled),
        'detail': detail(PrefsKeys.dynamicEqBands, 'flat'),
      },
      <String, Object?>{
        'stage': 'viper_ddc',
        'enabled': enabled(PrefsKeys.viperDdcEnabled),
        'detail': detail(PrefsKeys.viperDdcProfileName, 'none'),
      },
      <String, Object?>{
        'stage': 'arbitrary_eq',
        'enabled': enabled(PrefsKeys.arbitraryEqEnabled),
        'detail': enabled(PrefsKeys.arbitraryEqLinearPhase)
            ? 'linear-phase'
            : 'minimum-phase',
      },
      <String, Object?>{
        'stage': 'live_prog',
        'enabled': enabled(PrefsKeys.liveProgEnabled),
        'detail': detail(PrefsKeys.liveProgCode, 'none'),
      },
      <String, Object?>{
        'stage': 'stereo_balance',
        'enabled': (_doubleValue(PrefsKeys.stereoBalance) ?? 0.0) != 0.0,
        'detail': '${_doubleValue(PrefsKeys.stereoBalance) ?? 0.0}',
      },
      <String, Object?>{
        'stage': 'mono_mix',
        'enabled': enabled(PrefsKeys.monoMix),
        'detail': enabled(PrefsKeys.monoMix) ? 'on' : 'off',
      },
    ];
  }

  /// Reads a preference only when it is stored as a string.
  ///
  /// SharedPreferences' typed getters cast blindly; a value written by an older
  /// build with a different type would otherwise throw and fail the bundle.
  String? _stringValue(String key) {
    final value = _prefs.get(key);
    return value is String ? _prefs.getString(key) : null;
  }

  /// Reads a preference only when it is stored as an int.
  int? _intValue(String key) {
    final value = _prefs.get(key);
    return value is int ? _prefs.getInt(key) : null;
  }

  /// Reads a preference only when it is stored as a double.
  double? _doubleValue(String key) {
    final value = _prefs.get(key);
    return value is double ? _prefs.getDouble(key) : null;
  }

  /// Number of persisted multiband-compressor bands.
  ///
  /// The equalizer stores the band list as a JSON array string, so reading it
  /// as an int would silently fall back forever. A malformed payload falls back
  /// to the four-band default.
  int _multibandBandCount() {
    final raw = _stringValue(PrefsKeys.multibandCompressorBands);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List && decoded.isNotEmpty) return decoded.length;
      } catch (_) {
        // Corrupt payload: report the default without failing the bundle.
      }
    }
    // Native MultibandCompressor::NUM_BANDS is 4 (see MultibandCompressor.h);
    // a missing pref means the engine's own four-band default is in effect.
    return 4;
  }

  Map<String, Object?> _buildCounters() {
    final provided = _probeMap(
      _countersProbe,
      'output path counters',
      fallback: const <String, Object?>{},
    );
    if (provided.isNotEmpty) {
      final paths = provided['paths'];
      final reported = provided['reported'];
      return <String, Object?>{
        'reported': reported is bool ? reported : true,
        'source': provided['source'] ?? 'native',
        'paths': paths is Map
            ? _sanitizeMap(Map<String, Object?>.from(paths))
            : _sanitizeMap(provided),
      };
    }
    return <String, Object?>{
      'reported': false,
      'source': DiagnosticsStrings.pathsNativeNotReported,
      'paths': <String, Object?>{
        for (final path in _outputPaths)
          path: <String, Object?>{
            'xruns': 0,
            'underruns': 0,
            'reported': false,
            'source': DiagnosticsStrings.pathsNativeNotReported,
          },
      },
    };
  }

  Map<String, Object?> _redactedPreferences() {
    final keys = _prefs.getKeys().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _redactValue(key, _prefs.get(key)),
    };
  }

  Object? _redactValue(String key, Object? value) {
    if (value is String) {
      return _sensitiveKey.hasMatch(key) ? '[REDACTED]' : redactText(value);
    }
    if (value is List) {
      if (_sensitiveKey.hasMatch(key)) return '[REDACTED]';
      return <Object?>[
        // Recurse instead of redacting only top-level strings: nested maps in
        // a list (USB descriptors, path counters) carry paths too.
        for (final item in value) _redactValue(key, item),
      ];
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _redactValue('${entry.key}', entry.value),
      };
    }
    if (_sensitiveKey.hasMatch(key)) return '[REDACTED]';
    return value;
  }

  Map<String, Object?> _probeMap(
    DiagnosticsMapProbe? probe,
    String label, {
    required Map<String, Object?> fallback,
  }) {
    if (probe == null) return fallback;
    try {
      return _sanitizeMap(probe());
    } catch (e, st) {
      ErrorLogger.log(
        'Reading the $label for the bundle failed',
        error: e,
        stackTrace: st,
        category: 'DiagnosticsBundle',
      );
      return fallback;
    }
  }

  Map<String, Object?> _sanitizeMap(Map<String, Object?> source) {
    return <String, Object?>{
      for (final entry in source.entries)
        entry.key: _sanitizeValue(entry.key, entry.value),
    };
  }

  Object? _sanitizeValue(String key, Object? value) {
    if (value is String) {
      return _sensitiveKey.hasMatch(key) ? '[REDACTED]' : redactText(value);
    }
    if (value is List) {
      if (_sensitiveKey.hasMatch(key)) return '[REDACTED]';
      return <Object?>[
        for (final item in value) _sanitizeValue(key, item),
      ];
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _sanitizeValue('${entry.key}', entry.value),
      };
    }
    if (_sensitiveKey.hasMatch(key)) return '[REDACTED]';
    return value;
  }

  static Future<Map<String, Object?>> _defaultUsbDiagnostics() async {
    final usb = UsbExclusiveService();
    const timeout = Duration(milliseconds: 1500);

    final diagFuture = usb
        .getDiagnostics()
        .timeout(timeout, onTimeout: () => <String, Object?>{});
    final eventsFuture = usb
        .getUsbEvents()
        .timeout(timeout, onTimeout: () => <Map<String, Object?>>[]);
    final statusFuture =
        (!usb.lastStatus.attached && usb.lastStatus.deviceId == null)
            ? usb.getStatus().timeout(timeout, onTimeout: () => usb.lastStatus)
            : Future.value(usb.lastStatus);

    final results = await Future.wait([
      diagFuture,
      eventsFuture,
      statusFuture,
    ]);

    final raw = results[0] as Map<String, Object?>;
    final events = results[1] as List<Map<String, Object?>>;
    final status = results[2] as UsbExclusiveStatus;

    final section = Map<String, Object?>.from(raw);
    if (!section.containsKey('events')) {
      section['events'] = events;
    }
    section.putIfAbsent('clockDomain', () => status.clockDomain.wireName);
    section.putIfAbsent('clockDriftPpm', () => status.clockDriftPpm);
    section.putIfAbsent('ringFillMs', () => status.ringFillMs);
    section.putIfAbsent('feedbackPresent', () => status.feedbackPresent);
    section.putIfAbsent('drainPending', () => status.drainPending);
    return section;
  }
}
