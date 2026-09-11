// lib/core/telemetry/audio_session_log.dart
//
// Pure-Dart per-session audio telemetry. One JSON record is persisted per
// playback session (track) so a route change, Bluetooth codec, negotiated
// output format, interruption and underrun/dropout count can be correlated
// after the fact. No native code is involved.
//
// Every public entry point is best-effort: it never throws into the playback
// path and is a complete no-op while `PrefsKeys.audioSessionLogEnabled` is off.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/audio_output_info.dart';
import '../constants/prefs_keys.dart';
import '../utils/error_logger.dart';

/// Output route class recorded per session.
enum AudioRouteType {
  speaker,
  wired,
  bluetooth;

  static AudioRouteType fromName(String? name) => AudioRouteType.values
      .firstWhere((e) => e.name == name, orElse: () => AudioRouteType.speaker);
}

/// Interruption kinds surfaced by `audio_session`, plus the becoming-noisy
/// (unplug / Bluetooth disconnect) event.
enum AudioInterruptionKind {
  duck,
  pause,
  unknown,
  becomingNoisy;

  /// Stable wire value used in the persisted JSON.
  String get wireValue =>
      this == AudioInterruptionKind.becomingNoisy ? 'becoming-noisy' : name;

  static AudioInterruptionKind fromWire(String? value) {
    if (value == 'becoming-noisy') return AudioInterruptionKind.becomingNoisy;
    return AudioInterruptionKind.values
        .firstWhere((e) => e.name == value, orElse: () => AudioInterruptionKind.unknown);
  }
}

/// One `{timestamp, from, to}` route transition during a session.
class AudioRouteChangeEvent {
  final String timestamp;
  final AudioRouteType from;
  final AudioRouteType to;

  const AudioRouteChangeEvent({
    required this.timestamp,
    required this.from,
    required this.to,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'from': from.name,
        'to': to.name,
      };

  factory AudioRouteChangeEvent.fromJson(Map<String, dynamic> json) =>
      AudioRouteChangeEvent(
        timestamp: json['timestamp'] as String? ?? '',
        from: AudioRouteType.fromName(json['from'] as String?),
        to: AudioRouteType.fromName(json['to'] as String?),
      );
}

/// One `{timestamp, type}` interruption during a session.
class AudioInterruptionEvent {
  final String timestamp;
  final AudioInterruptionKind type;

  const AudioInterruptionEvent({
    required this.timestamp,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'type': type.wireValue,
      };

  factory AudioInterruptionEvent.fromJson(Map<String, dynamic> json) =>
      AudioInterruptionEvent(
        timestamp: json['timestamp'] as String? ?? '',
        type: AudioInterruptionKind.fromWire(json['type'] as String?),
      );
}

/// The complete, retrievable telemetry for a single playback session.
class AudioSessionRecord {
  final String sessionId;
  final String trackId;
  final String trackTitle;
  final String startedAt;

  AudioRouteType routeType;
  String? bluetoothCodec;
  int? sampleRate;
  int? bitDepth;
  int? bitrateKbps;
  final List<AudioRouteChangeEvent> routeChanges;
  final List<AudioInterruptionEvent> interruptions;
  int bufferUnderruns;
  int dropouts;
  String? endedAt;

  AudioSessionRecord({
    required this.sessionId,
    required this.trackId,
    required this.trackTitle,
    required this.startedAt,
    this.routeType = AudioRouteType.speaker,
    this.bluetoothCodec,
    this.sampleRate,
    this.bitDepth,
    this.bitrateKbps,
    List<AudioRouteChangeEvent>? routeChanges,
    List<AudioInterruptionEvent>? interruptions,
    this.bufferUnderruns = 0,
    this.dropouts = 0,
    this.endedAt,
  })  : routeChanges = routeChanges ?? <AudioRouteChangeEvent>[],
        interruptions = interruptions ?? <AudioInterruptionEvent>[];

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'trackId': trackId,
        'trackTitle': trackTitle,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'routeType': routeType.name,
        'bluetoothCodec': bluetoothCodec,
        'sampleRate': sampleRate,
        'bitDepth': bitDepth,
        'bitrateKbps': bitrateKbps,
        'routeChanges': routeChanges.map((e) => e.toJson()).toList(),
        'interruptions': interruptions.map((e) => e.toJson()).toList(),
        'bufferUnderruns': bufferUnderruns,
        'dropouts': dropouts,
      };

  factory AudioSessionRecord.fromJson(Map<String, dynamic> json) =>
      AudioSessionRecord(
        sessionId: json['sessionId'] as String? ?? '',
        trackId: json['trackId'] as String? ?? '',
        trackTitle: json['trackTitle'] as String? ?? '',
        startedAt: json['startedAt'] as String? ?? '',
        endedAt: json['endedAt'] as String?,
        routeType: AudioRouteType.fromName(json['routeType'] as String?),
        bluetoothCodec: json['bluetoothCodec'] as String?,
        sampleRate: (json['sampleRate'] as num?)?.toInt(),
        bitDepth: (json['bitDepth'] as num?)?.toInt(),
        bitrateKbps: (json['bitrateKbps'] as num?)?.toInt(),
        routeChanges: (json['routeChanges'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((e) => AudioRouteChangeEvent.fromJson(
                    Map<String, dynamic>.from(e)))
                .toList() ??
            const <AudioRouteChangeEvent>[],
        interruptions: (json['interruptions'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((e) => AudioInterruptionEvent.fromJson(
                    Map<String, dynamic>.from(e)))
                .toList() ??
            const <AudioInterruptionEvent>[],
        bufferUnderruns: (json['bufferUnderruns'] as num?)?.toInt() ?? 0,
        dropouts: (json['dropouts'] as num?)?.toInt() ?? 0,
      );
}

/// Records one JSONL record per playback session under the app documents
/// directory, keeping only the last [maxSessions] records.
class AudioSessionLog {
  AudioSessionLog({
    Future<Directory?> Function()? directoryProvider,
    Future<bool> Function()? enabledProvider,
    this.maxSessions = defaultMaxSessions,
    this.fileName = defaultFileName,
    DateTime Function()? clock,
  })  : _directoryProvider = directoryProvider ?? _defaultDirectory,
        _enabledProvider = enabledProvider ?? _defaultEnabled,
        _clock = clock ?? DateTime.now;

  static const int defaultMaxSessions = 25;
  static const String defaultFileName = 'audio_session_logs.jsonl';

  /// Process-wide instance. Wired by the audio handler and settings UI;
  /// replaceable in tests.
  static AudioSessionLog instance = AudioSessionLog();

  final Future<Directory?> Function() _directoryProvider;
  final Future<bool> Function() _enabledProvider;
  final DateTime Function() _clock;
  final int maxSessions;
  final String fileName;

  AudioSessionRecord? _active;
  int _sessionCounter = 0;
  Future<void> _tail = Future<void>.value();

  /// Id of the session currently being recorded, or null.
  String? get activeSessionId => _active?.sessionId;
  String? get activeTrackId => _active?.trackId;
  bool get hasActiveSession => _active != null;

  static Future<Directory?> _defaultDirectory() async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _defaultEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(PrefsKeys.audioSessionLogEnabled) ?? true;
    } catch (_) {
      return true;
    }
  }

  String _nowIso() => _clock().toUtc().toIso8601String();

  /// Serializes an operation onto the write tail and swallows every failure, so
  /// telemetry can never throw into playback. Skips entirely when disabled.
  Future<void> _run(Future<void> Function() body) {
    final next = _tail.then((_) async {
      try {
        if (!await _enabledProvider()) return;
        await body();
      } catch (e, st) {
        ErrorLogger.log('Audio session telemetry failed',
            error: e, stackTrace: st, category: 'AudioSessionLog');
      }
    });
    _tail = next;
    return next;
  }

  /// Starts a new session, finalizing the previous one (if any) first so there
  /// is exactly one persisted record per session.
  Future<void> startSession({
    required String trackId,
    required String trackTitle,
    AudioRouteType routeType = AudioRouteType.speaker,
    String? bluetoothCodec,
    int? sampleRate,
    int? bitDepth,
    int? bitrateKbps,
  }) {
    return _run(() async {
      await _finalizeActive();
      _active = AudioSessionRecord(
        sessionId: 'sess_${_clock().toUtc().microsecondsSinceEpoch}_${_sessionCounter++}',
        trackId: trackId,
        trackTitle: trackTitle,
        startedAt: _nowIso(),
        routeType: routeType,
        bluetoothCodec: bluetoothCodec,
        sampleRate: sampleRate,
        bitDepth: bitDepth,
        bitrateKbps: bitrateKbps,
      );
    });
  }

  /// Updates the negotiated output/route fields of the active session and, when
  /// the route class actually changed, appends a route-change event.
  Future<void> updateOutputInfo({
    required AudioRouteType routeType,
    String? bluetoothCodec,
    int? sampleRate,
    int? bitDepth,
  }) {
    return _run(() async {
      final active = _active;
      if (active == null) return;
      final previous = active.routeType;
      active.routeType = routeType;
      if (bluetoothCodec != null) active.bluetoothCodec = bluetoothCodec;
      if (sampleRate != null) active.sampleRate = sampleRate;
      if (bitDepth != null) active.bitDepth = bitDepth;
      if (previous != routeType) {
        active.routeChanges.add(AudioRouteChangeEvent(
          timestamp: _nowIso(),
          from: previous,
          to: routeType,
        ));
      }
    });
  }

  Future<void> recordInterruption(AudioInterruptionKind type) {
    return _run(() async {
      _active?.interruptions
          .add(AudioInterruptionEvent(timestamp: _nowIso(), type: type));
    });
  }

  Future<void> recordUnderrun() {
    return _run(() async {
      final active = _active;
      if (active != null) active.bufferUnderruns++;
    });
  }

  Future<void> recordDropout() {
    return _run(() async {
      final active = _active;
      if (active != null) active.dropouts++;
    });
  }

  /// Finalizes and persists the active session. Safe to call with none active.
  Future<void> endSession() {
    return _run(_finalizeActive);
  }

  Future<void> _finalizeActive() async {
    final active = _active;
    if (active == null) return;
    _active = null;
    active.endedAt = _nowIso();
    final dir = await _directoryProvider();
    if (dir == null) return;
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString('${jsonEncode(active.toJson())}\n',
        mode: FileMode.append, flush: true);
    await _enforceRing(file);
  }

  /// Rewrites the JSONL file keeping only the newest [maxSessions] records.
  Future<void> _enforceRing(File file) async {
    final lines = await _readLines(file);
    if (lines.length <= maxSessions) return;
    final kept = lines.sublist(lines.length - maxSessions);
    await file.writeAsString('${kept.join('\n')}\n', flush: true);
  }

  Future<List<String>> _readLines(File file) async {
    if (!await file.exists()) return <String>[];
    final content = await file.readAsString();
    return const LineSplitter()
        .convert(content)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// Reads every persisted session, newest last. Malformed lines are skipped.
  Future<List<AudioSessionRecord>> readAll() async {
    try {
      final dir = await _directoryProvider();
      if (dir == null) return const <AudioSessionRecord>[];
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      final records = <AudioSessionRecord>[];
      for (final line in await _readLines(file)) {
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map) {
            records.add(
                AudioSessionRecord.fromJson(Map<String, dynamic>.from(decoded)));
          }
        } catch (_) {
          // Skip a corrupt line rather than failing the whole export.
        }
      }
      return records;
    } catch (e, st) {
      ErrorLogger.log('Audio session log read failed',
          error: e, stackTrace: st, category: 'AudioSessionLog');
      return const <AudioSessionRecord>[];
    }
  }

  /// Writes all persisted records to a fresh JSONL file and returns it, or null
  /// when the documents directory is unavailable. Read-only with respect to the
  /// recording flag: existing logs can always be exported.
  Future<File?> exportToFile() async {
    try {
      final dir = await _directoryProvider();
      if (dir == null) return null;
      final records = await readAll();
      final stamp = _clock()
          .toUtc()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-');
      final file = File(
          '${dir.path}${Platform.pathSeparator}pulsr_audio_session_logs_$stamp.jsonl');
      final buffer = StringBuffer();
      for (final record in records) {
        buffer.writeln(jsonEncode(record.toJson()));
      }
      await file.writeAsString(buffer.toString(), flush: true);
      return file;
    } catch (e, st) {
      ErrorLogger.log('Audio session log export failed',
          error: e, stackTrace: st, category: 'AudioSessionLog');
      return null;
    }
  }

  /// Deletes the persisted log file. Never throws.
  Future<void> clear() async {
    try {
      final dir = await _directoryProvider();
      if (dir == null) return;
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      if (await file.exists()) await file.delete();
    } catch (e, st) {
      ErrorLogger.log('Audio session log clear failed',
          error: e, stackTrace: st, category: 'AudioSessionLog');
    }
  }

  /// Classifies an [AudioOutputInfo] into a session route type.
  static AudioRouteType routeTypeForInfo(AudioOutputInfo? info) {
    if (info == null) return AudioRouteType.speaker;
    final type = info.activeDeviceType.toLowerCase();
    if (info.isBluetooth ||
        info.isLeAudio ||
        type.contains('blue') ||
        type.contains('ble') ||
        type.contains('hearing')) {
      return AudioRouteType.bluetooth;
    }
    if (info.isUsbDac ||
        type.contains('usb') ||
        type.contains('wired') ||
        type.contains('headphone') ||
        type.contains('headset')) {
      return AudioRouteType.wired;
    }
    return AudioRouteType.speaker;
  }
}
