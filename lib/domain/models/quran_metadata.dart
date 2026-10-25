// lib/domain/models/quran_metadata.dart
import 'package:flutter/foundation.dart';

/// Accurate timestamp boundaries for a specific Ayah within an audio track.
@immutable
class QuranAyahTiming {
  final int ayahNumber;
  final Duration start;
  final Duration end;

  const QuranAyahTiming({
    required this.ayahNumber,
    required this.start,
    required this.end,
  }) : assert(ayahNumber >= 1, 'Ayah number must be >= 1');

  bool get isValid => ayahNumber >= 1 && end >= start;

  Map<String, dynamic> toMap() => {
        'ayahNumber': ayahNumber,
        'startMs': start.inMilliseconds,
        'endMs': end.inMilliseconds,
      };

  factory QuranAyahTiming.fromMap(Map<String, dynamic> map) {
    return QuranAyahTiming(
      ayahNumber: (map['ayahNumber'] as num?)?.toInt() ?? 1,
      start: Duration(milliseconds: (map['startMs'] as num?)?.toInt() ?? 0),
      end: Duration(milliseconds: (map['endMs'] as num?)?.toInt() ?? 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuranAyahTiming &&
          runtimeType == other.runtimeType &&
          ayahNumber == other.ayahNumber &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(ayahNumber, start, end);
}

/// Normalized Quran metadata model.
///
/// Disallows guessing or inferring Surah / Ayah numbers from loose filenames.
@immutable
class QuranMetadata {
  /// Surah number in the range 1..114.
  final int surahNumber;

  /// Canonical Surah name (e.g. "Al-Fatihah" or "الفاتحة").
  final String surahName;

  /// Starting Ayah number (1-indexed).
  final int ayahStart;

  /// Ending Ayah number (>= ayahStart).
  final int ayahEnd;

  /// Name of the reciter (e.g. "Mishary Rashid Alafasy").
  final String reciter;

  /// Optional source or catalog provenance (e.g. "quran.com", "tanzil").
  final String? source;

  /// Optional millisecond-accurate verse boundary timestamps.
  final List<QuranAyahTiming> ayahTimings;

  const QuranMetadata({
    required this.surahNumber,
    required this.surahName,
    required this.ayahStart,
    required this.ayahEnd,
    required this.reciter,
    this.source,
    this.ayahTimings = const <QuranAyahTiming>[],
  });

  /// Strict validation ensuring no corrupted or out-of-bounds Quran records exist.
  bool get isValid =>
      surahNumber >= 1 &&
      surahNumber <= 114 &&
      ayahStart >= 1 &&
      ayahEnd >= ayahStart &&
      surahName.trim().isNotEmpty &&
      reciter.trim().isNotEmpty;

  /// Total number of Ayahs in this recitation segment.
  int get totalAyahs => (ayahEnd - ayahStart) + 1;

  /// Finds the accurate timing slice for a given Ayah, or null if boundaries are unmapped.
  QuranAyahTiming? timingForAyah(int ayah) {
    if (ayah < ayahStart || ayah > ayahEnd) return null;
    for (final timing in ayahTimings) {
      if (timing.ayahNumber == ayah) return timing;
    }
    return null;
  }

  /// Ayah that contains [position], falling back to the closest preceding
  /// timing when the track position sits in a gap between timings.
  int ayahAt(Duration position) {
    QuranAyahTiming? nearest;
    for (final timing in ayahTimings) {
      if (timing.start <= position && position < timing.end) {
        return timing.ayahNumber;
      }
      if (timing.start <= position &&
          (nearest == null || timing.start > nearest.start)) {
        nearest = timing;
      }
    }
    return nearest?.ayahNumber ?? ayahStart;
  }

  Map<String, dynamic> toMap() => {
        'surahNumber': surahNumber,
        'surahName': surahName,
        'ayahStart': ayahStart,
        'ayahEnd': ayahEnd,
        'reciter': reciter,
        'source': source,
        'ayahTimings': ayahTimings.map((t) => t.toMap()).toList(),
      };

  factory QuranMetadata.fromMap(Map<String, dynamic> map) {
    final rawTimings = map['ayahTimings'];
    final timings = <QuranAyahTiming>[];
    if (rawTimings is List) {
      for (final item in rawTimings) {
        if (item is Map) {
          timings.add(QuranAyahTiming.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }

    return QuranMetadata(
      surahNumber: (map['surahNumber'] as num?)?.toInt() ?? 1,
      surahName: (map['surahName'] as String?)?.trim() ?? '',
      ayahStart: (map['ayahStart'] as num?)?.toInt() ?? 1,
      ayahEnd: (map['ayahEnd'] as num?)?.toInt() ?? 1,
      reciter: (map['reciter'] as String?)?.trim() ?? '',
      source: map['source'] as String?,
      ayahTimings: timings,
    );
  }

  QuranMetadata copyWith({
    int? surahNumber,
    String? surahName,
    int? ayahStart,
    int? ayahEnd,
    String? reciter,
    String? source,
    List<QuranAyahTiming>? ayahTimings,
  }) {
    return QuranMetadata(
      surahNumber: surahNumber ?? this.surahNumber,
      surahName: surahName ?? this.surahName,
      ayahStart: ayahStart ?? this.ayahStart,
      ayahEnd: ayahEnd ?? this.ayahEnd,
      reciter: reciter ?? this.reciter,
      source: source ?? this.source,
      ayahTimings: ayahTimings ?? this.ayahTimings,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuranMetadata &&
          runtimeType == other.runtimeType &&
          surahNumber == other.surahNumber &&
          surahName == other.surahName &&
          ayahStart == other.ayahStart &&
          ayahEnd == other.ayahEnd &&
          reciter == other.reciter &&
          source == other.source &&
          listEquals(ayahTimings, other.ayahTimings);

  @override
  int get hashCode => Object.hash(
        surahNumber,
        surahName,
        ayahStart,
        ayahEnd,
        reciter,
        source,
        Object.hashAll(ayahTimings),
      );
}

/// Quran-specific bookmark representation. Completely isolated from standard
/// music bookmarks to avoid mixing devotional verse bookmarks with music playback state.
@immutable
class QuranBookmark {
  final String trackUri;
  final QuranMetadata metadata;
  final int currentAyah;
  final Duration position;
  final DateTime timestamp;

  const QuranBookmark({
    required this.trackUri,
    required this.metadata,
    required this.currentAyah,
    required this.position,
    required this.timestamp,
  });

  bool get isValid =>
      trackUri.isNotEmpty &&
      metadata.isValid &&
      currentAyah >= metadata.ayahStart &&
      currentAyah <= metadata.ayahEnd &&
      position >= Duration.zero;

  Map<String, dynamic> toMap() => {
        'trackUri': trackUri,
        'metadata': metadata.toMap(),
        'currentAyah': currentAyah,
        'positionMs': position.inMilliseconds,
        'timestamp': timestamp.toIso8601String(),
      };

  factory QuranBookmark.fromMap(Map<String, dynamic> map) {
    return QuranBookmark(
      trackUri: map['trackUri'] as String? ?? '',
      metadata: QuranMetadata.fromMap(
          Map<String, dynamic>.from(map['metadata'] as Map? ?? {})),
      currentAyah: (map['currentAyah'] as num?)?.toInt() ?? 1,
      position:
          Duration(milliseconds: (map['positionMs'] as num?)?.toInt() ?? 0),
      timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuranBookmark &&
          runtimeType == other.runtimeType &&
          trackUri == other.trackUri &&
          metadata == other.metadata &&
          currentAyah == other.currentAyah &&
          position == other.position &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      Object.hash(trackUri, metadata, currentAyah, position, timestamp);
}

/// Precise Quran loop mode.
enum QuranRepeatMode {
  off,
  singleAyah,
  range,
}
