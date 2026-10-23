import 'dart:math' as math;

import 'package:flutter/foundation.dart';

class EqBand {
  final int index;
  final double centerFrequency; // in Hz
  final double gain; // in dB, typically -15.0 to 15.0
  final double q; // Q factor, default 1.414
  final int
      filterType; // 0=Peaking, 1=LowShelf, 2=HighShelf, 3=LowPass, 4=HighPass
  final bool enabled;

  const EqBand({
    required this.index,
    required this.centerFrequency,
    required this.gain,
    this.q = 1.414,
    this.filterType = 0,
    this.enabled = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EqBand &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          centerFrequency == other.centerFrequency &&
          gain == other.gain &&
          q == other.q &&
          filterType == other.filterType &&
          enabled == other.enabled;

  @override
  int get hashCode =>
      Object.hash(index, centerFrequency, gain, q, filterType, enabled);

  EqBand copyWith({
    double? gain,
    double? centerFrequency,
    double? q,
    int? filterType,
    bool? enabled,
  }) {
    return EqBand(
      index: index,
      centerFrequency: centerFrequency ?? this.centerFrequency,
      gain: gain ?? this.gain,
      q: q ?? this.q,
      filterType: filterType ?? this.filterType,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'centerFrequency': centerFrequency,
        'gain': gain,
        'q': q,
        'filterType': filterType,
        'enabled': enabled,
      };

  factory EqBand.fromJson(Map<String, dynamic> json) => EqBand(
        index: (json['index'] as num?)?.toInt() ?? 0,
        centerFrequency:
            (json['centerFrequency'] as num?)?.toDouble() ?? 1000.0,
        gain: (json['gain'] as num?)?.toDouble() ?? 0.0,
        q: (json['q'] as num?)?.toDouble() ?? 1.414,
        filterType: (json['filterType'] as num?)?.toInt() ?? 0,
        enabled: json['enabled'] as bool? ?? true,
      );
}

class EqPreset {
  final String name;
  final List<double> gains; // Gains for the bands in dB
  final double bassBoost; // 0.0 to 1.0
  final List<double>? customFrequencies;
  final List<double>? qFactors;
  final Map<int, List<double>> bandsMap;

  const EqPreset({
    required this.name,
    required this.gains,
    this.bassBoost = 0.0,
    this.customFrequencies,
    this.qFactors,
    this.bandsMap = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EqPreset &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          bassBoost == other.bassBoost &&
          listEquals(gains, other.gains) &&
          listEquals(customFrequencies, other.customFrequencies) &&
          listEquals(qFactors, other.qFactors) &&
          _bandsMapEquals(bandsMap, other.bandsMap);

  @override
  int get hashCode => Object.hash(
        name,
        bassBoost,
        Object.hashAll(gains),
        customFrequencies == null ? null : Object.hashAll(customFrequencies!),
        qFactors == null ? null : Object.hashAll(qFactors!),
        _bandsMapHash(bandsMap),
      );

  static bool _bandsMapEquals(
      Map<int, List<double>> a, Map<int, List<double>> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || !listEquals(entry.value, other)) return false;
    }
    return true;
  }

  static int _bandsMapHash(Map<int, List<double>> map) {
    final keys = map.keys.toList()..sort();
    return Object.hashAll([
      for (final key in keys) Object.hash(key, Object.hashAll(map[key]!)),
    ]);
  }

  EqPreset copyWith({
    String? name,
    List<double>? gains,
    double? bassBoost,
    List<double>? customFrequencies,
    List<double>? qFactors,
    Map<int, List<double>>? bandsMap,
  }) {
    return EqPreset(
      name: name ?? this.name,
      gains: gains ?? this.gains,
      bassBoost: bassBoost ?? this.bassBoost,
      customFrequencies: customFrequencies ?? this.customFrequencies,
      qFactors: qFactors ?? this.qFactors,
      bandsMap: bandsMap ?? this.bandsMap,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'gains': gains,
        'bassBoost': bassBoost,
        if (customFrequencies != null) 'customFrequencies': customFrequencies,
        if (qFactors != null) 'qFactors': qFactors,
        if (bandsMap.isNotEmpty)
          'bandsMap': bandsMap.map((k, v) => MapEntry(k.toString(), v)),
      };

  factory EqPreset.fromJson(Map<String, dynamic> json) {
    final rawGains = json['gains'] as List<dynamic>? ?? [];
    final gains = rawGains.map((e) => (e as num).toDouble()).toList();
    final rawFreqs = json['customFrequencies'] as List<dynamic>?;
    final customFreqs = rawFreqs?.map((e) => (e as num).toDouble()).toList();
    final rawQs = json['qFactors'] as List<dynamic>?;
    final qs = rawQs?.map((e) => (e as num).toDouble()).toList();

    final rawBandsMap = json['bandsMap'] as Map<String, dynamic>?;
    final parsedBandsMap = <int, List<double>>{};
    if (rawBandsMap != null) {
      rawBandsMap.forEach((key, value) {
        final intKey = int.tryParse(key);
        if (intKey != null && value is List) {
          parsedBandsMap[intKey] =
              value.map((e) => (e as num).toDouble()).toList();
        }
      });
    }

    return EqPreset(
      name: json['name'] as String? ?? 'Custom',
      gains: gains,
      bassBoost: (json['bassBoost'] as num?)?.toDouble() ?? 0.0,
      customFrequencies: customFreqs,
      qFactors: qs,
      bandsMap: parsedBandsMap,
    );
  }

  /// ISO 10-band graphic-EQ centers (Hz).
  static const List<double> centerFrequencies = [
    32,
    64,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];

  /// ISO 31-band 1/3-octave studio parametric EQ centers (Hz).
  static const List<double> iso31Frequencies = [
    20,
    25,
    31.5,
    40,
    50,
    63,
    80,
    100,
    125,
    160,
    200,
    250,
    315,
    400,
    500,
    630,
    800,
    1000,
    1250,
    1600,
    2000,
    2500,
    3150,
    4000,
    5000,
    6300,
    8000,
    10000,
    12500,
    16000,
    20000,
  ];

  /// Legacy alias for [iso31Frequencies]. This list has 31 entries (it is the
  /// ISO 1/3-octave series), not the app's 32-band plan
  /// ([iso32BandFrequencies]).
  static const List<double> iso32Frequencies = iso31Frequencies;

  /// Default centers for the UI's "32-band" mode. The ISO 1/3-octave series
  /// ([iso32Frequencies]) is 31 bands, which made the 10/32/64 toggle unable
  /// to ever highlight 32 and silently rejected the custom editor. This is a
  /// true 32-entry log-spaced layout spanning 20 Hz–20 kHz.
  static final List<double> iso32BandFrequencies =
      _logSpread(32, const [20.0, 20000.0]);

  /// 64-band log-spaced centers (Hz) spanning 20 Hz to 20 kHz. PowerAmp-parity
  /// high-resolution graphic EQ; log-spacing keeps the bands perceptually even.
  static final List<double> iso64Frequencies =
      _logSpread(64, const [20.0, 20000.0]);

  /// Maps [source] gains onto target frequencies (defaults to [targetFrequencies] or 10-band).
  static List<double> interpolateGains(
    List<double> source, {
    List<double> targetFrequencies = centerFrequencies,
    Map<int, List<double>>? bandsMap,
    int? currentBandCount,
    List<double>? sourceFrequencies,
  }) {
    if (bandsMap != null && currentBandCount != null) {
      bandsMap[currentBandCount] = List<double>.from(source);
    }

    final n = targetFrequencies.length;
    if (bandsMap != null && bandsMap.containsKey(n)) {
      return List<double>.from(bandsMap[n]!);
    }

    if (source.length == n) return List<double>.from(source);
    if (source.isEmpty) return List<double>.filled(n, 0.0);
    if (source.length == 1) return List<double>.filled(n, source.first);

    // Key the source centers off the exact band count: the app's 32-band plan
    // (iso32BandFrequencies, 20 Hz–20 kHz) is distinct from the 31-entry ISO
    // 1/3-octave list, so a 32-band curve converted to 10 bands stays aligned.
    final List<double> srcFreqs;
    if (sourceFrequencies != null &&
        sourceFrequencies.length == source.length) {
      srcFreqs = sourceFrequencies;
    } else if (source.length == centerFrequencies.length) {
      srcFreqs = centerFrequencies;
    } else if (source.length == iso32BandFrequencies.length) {
      srcFreqs = iso32BandFrequencies;
    } else if (source.length == iso31Frequencies.length) {
      srcFreqs = iso31Frequencies;
    } else if (source.length == iso64Frequencies.length) {
      srcFreqs = iso64Frequencies;
    } else {
      srcFreqs = _logSpread(source.length, targetFrequencies);
    }

    return [
      for (final f in targetFrequencies) _interpAtLogFreq(f, srcFreqs, source)
    ];
  }

  static double _interpAtLogFreq(
      double freq, List<double> freqs, List<double> gains) {
    final logF = math.log(freq);
    if (logF <= math.log(freqs.first)) return gains.first;
    if (logF >= math.log(freqs.last)) return gains.last;
    for (int i = 0; i < freqs.length - 1; i++) {
      final lo = math.log(freqs[i]);
      final hi = math.log(freqs[i + 1]);
      if (logF >= lo && logF <= hi) {
        final t = (logF - lo) / (hi - lo);
        return gains[i] + (gains[i + 1] - gains[i]) * t;
      }
    }
    return gains.last;
  }

  static List<double> _logSpread(int count, List<double> spanFreqs) {
    if (count <= 1) {
      return List.filled(count, spanFreqs.isNotEmpty ? spanFreqs.first : 0.0);
    }
    final logLo = math.log(spanFreqs.first);
    final logHi = math.log(spanFreqs.last);
    return [
      for (int i = 0; i < count; i++)
        math.exp(logLo + (logHi - logLo) * (i / (count - 1))),
    ];
  }

  static const List<EqPreset> defaultPresets = [
    EqPreset(
        name: 'Flat', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], bassBoost: 0.0),
    EqPreset(
        name: 'Bass Boost',
        gains: [7, 6.5, 5, 3, 1, 0, 0, 0, 0, 0],
        bassBoost: 0.5),
    EqPreset(
        name: 'Rock',
        gains: [5, 4, 2.5, 0, -1, -1, 0.5, 2.5, 4, 4.5],
        bassBoost: 0.2),
    EqPreset(
        name: 'Pop',
        gains: [-1, -0.5, 0.5, 2, 3.5, 4, 3, 1.5, 0, -1],
        bassBoost: 0.1),
    EqPreset(
        name: 'Jazz',
        gains: [3.5, 3, 2, 1, -0.5, -1, 0, 1.5, 3, 3.5],
        bassBoost: 0.1),
    EqPreset(
        name: 'Electronic',
        gains: [6, 5.5, 4, 2, 0, -0.5, 0.5, 2.5, 4.5, 5],
        bassBoost: 0.4),
    EqPreset(
        name: 'Vocal Boost',
        gains: [-3, -2.5, -1, 1, 3.5, 4.5, 4, 2, 0.5, -0.5],
        bassBoost: 0.0),
    EqPreset(
        name: 'Classical',
        gains: [4, 3.5, 2.5, 1, 0, -0.5, 0, 1.5, 3, 3.5],
        bassBoost: 0.0),
  ];
}
