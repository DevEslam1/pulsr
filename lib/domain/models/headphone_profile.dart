// lib/domain/models/headphone_profile.dart
import 'dart:math' as math;

import '../../data/audio/eq_legacy_migration.dart';
import 'eq_preset.dart';

/// Value equality for lists whose elements implement `==`. Kept local so the
/// pure domain model does not depend on Flutter's `listEquals`.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A single parametric (biquad) filter from a real AutoEQ correction profile.
///
/// AutoEQ ships its corrections as parametric filter lists with explicit
/// center frequency, Q and filter type (peaking, low/high shelf). Retaining
/// those fields — instead of flattening to a single gain per ISO band — is what
/// gives AutoEQ-parity fidelity, and lets the profile drive the native 64-band
/// parametric EQ directly with the correct Q and shelf shapes.
class EqFilter {
  final double frequency; // Hz
  final double gain; // dB
  final double q; // Q factor (or shelf slope)
  final int filterType; // 0=Peaking, 1=LowShelf, 2=HighShelf

  const EqFilter({
    required this.frequency,
    required this.gain,
    this.q = 1.414,
    this.filterType = EqFilterType.peaking,
  });

  Map<String, dynamic> toJson() => {
        'frequency': frequency,
        'gain': gain,
        'q': q,
        'type': filterType,
      };

  factory EqFilter.fromJson(Map<String, dynamic> json) => EqFilter(
        frequency: (json['frequency'] as num?)?.toDouble() ?? 1000.0,
        gain: (json['gain'] as num?)?.toDouble() ?? 0.0,
        q: (json['q'] as num?)?.toDouble() ?? 1.414,
        filterType: (json['type'] as num?)?.toInt() ?? EqFilterType.peaking,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EqFilter &&
          runtimeType == other.runtimeType &&
          frequency == other.frequency &&
          gain == other.gain &&
          q == other.q &&
          filterType == other.filterType;

  @override
  int get hashCode => Object.hash(frequency, gain, q, filterType);
}

/// Native `FilterType` ordinals (see `android/app/src/main/cpp/DspParams.h`).
class EqFilterType {
  static const int peaking = 0;
  static const int lowShelf = 1;
  static const int highShelf = 2;
  static const int lowPass = 3;
  static const int highPass = 4;
  static const int notch = 5;
  static const int bandPass = 6;
  static const int allPass = 7;
}

class HeadphoneProfile {
  final String id;
  final String name;
  final String brand;
  final String model;
  final String
      category; // 'Target Curve', 'In-Ear', 'TWS Earbuds', 'Over-Ear', 'On-Ear', 'Earbuds', 'Custom'
  final List<double>
      gains; // 10-band gains in dB, aligned to EqPreset.centerFrequencies
  final double bassBoost; // 0.0 to 1.0
  final double preampGain; // in dB
  /// True parametric AutoEQ filters (freq/Q/gain/type). When non-empty these
  /// are the authoritative correction; [gains] remains as a derived/fallback
  /// view for legacy consumers and graph rendering.
  final List<EqFilter> filters;

  /// Source dataset the profile was imported from (e.g. 'AutoEQ' or a user
  /// file name). Null for hand-authored/bundled legacy curves.
  final String? source;

  const HeadphoneProfile({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    required this.category,
    required this.gains,
    this.bassBoost = 0.0,
    this.preampGain = 0.0,
    this.filters = const [],
    this.source,
  });

  /// Whether this profile carries true parametric filters.
  bool get hasParametricFilters => filters.isNotEmpty;

  factory HeadphoneProfile.fromJson(Map<String, dynamic> json) {
    // Null-guard gains like every sibling field: a stored profile missing the
    // key must not throw and abort the whole profile load.
    final rawGains = (json['gains'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const <double>[];
    final rawFilters = json['filters'] as List<dynamic>?;
    final filters = rawFilters == null
        ? const <EqFilter>[]
        : rawFilters
            .whereType<Map<String, dynamic>>()
            .map(EqFilter.fromJson)
            .where((f) =>
                f.frequency.isFinite && f.frequency > 0 && f.gain.isFinite)
            .toList();
    return HeadphoneProfile(
      // Required strings are null-guarded: a stored profile missing a key must
      // not throw and abort the whole profile load.
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      model: json['model'] as String? ?? '',
      category: json['category'] as String? ?? 'Headphone',
      // If profile is already 10 bands keep as is; a 5-band list is legacy
      // persisted/asset data, otherwise interpolate onto the 10-band plan.
      gains: rawGains.length == EqPreset.centerFrequencies.length
          ? rawGains
          : rawGains.length == 5
              ? EqLegacyMigration.to10Band(rawGains)
              : EqPreset.interpolateGains(rawGains),
      bassBoost: (json['bassBoost'] as num?)?.toDouble() ?? 0.0,
      preampGain: (json['preampGain'] as num?)?.toDouble() ?? 0.0,
      filters: filters,
      source: json['source'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'model': model,
      'category': category,
      'gains': gains,
      'bassBoost': bassBoost,
      'preampGain': preampGain,
      if (filters.isNotEmpty)
        'filters': filters.map((f) => f.toJson()).toList(),
      if (source != null) 'source': source,
    };
  }

  HeadphoneProfile copyWith({
    String? id,
    String? name,
    String? brand,
    String? model,
    String? category,
    List<double>? gains,
    double? bassBoost,
    double? preampGain,
    List<EqFilter>? filters,
    String? source,
  }) {
    return HeadphoneProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      category: category ?? this.category,
      gains: gains ?? this.gains,
      bassBoost: bassBoost ?? this.bassBoost,
      preampGain: preampGain ?? this.preampGain,
      filters: filters ?? this.filters,
      source: source ?? this.source,
    );
  }

  /// The most negative preamp that keeps a parametric-filter profile from
  /// clipping the native DSP chain. The peak boost of a sum of peaking/shelf
  /// biquads is bounded by the summed positive gains plus a shaping margin, so
  /// the returned value is always <= 0 dB and never positive.
  ///
  /// Returns 0.0 when there are no filters (legacy gain curves use their
  /// stored [preampGain] instead).
  double computeSafePreamp({double safetyMarginDb = 1.0}) {
    if (filters.isEmpty) return 0.0;
    // Sum positive filter gains: a conservative bound on the composite boost
    // because individual biquad peaks can only partially overlap in frequency.
    var positiveSum = 0.0;
    for (final f in filters) {
      if (f.gain > 0) positiveSum += f.gain;
    }
    if (positiveSum <= 0) return 0.0;
    return -(positiveSum + safetyMarginDb);
  }

  /// Expands the parametric filters onto the given ISO [centers] by evaluating
  /// the composite magnitude response of the filter sum at each center. Used to
  /// render a profile on the EQ graph and as a fallback when a consumer only
  /// understands gain curves.
  List<double> gainsFromFilters({
    List<double> centers = EqPreset.centerFrequencies,
  }) {
    if (filters.isEmpty) return List<double>.from(gains);
    return [for (final c in centers) _compositeGainAt(c)];
  }

  /// Magnitude (dB) of the summed biquad filters at [freq], using the RBJ
  /// audio-EQ-cookbook transfer functions (analog magnitude, no prewarp) so
  /// the shape is stable and cheap to evaluate for display.
  double _compositeGainAt(double freq) {
    if (freq <= 0 || !freq.isFinite) return 0.0;
    var linear = 1.0;
    for (final f in filters) {
      linear *= _biquadMagnitude(f, freq);
    }
    return 20.0 * (math.log(linear) / math.ln10);
  }

  /// Reference sample rate used when evaluating filter curves for display.
  /// AutoEQ corrections are defined against a 48 kHz working rate (the app's
  /// capture/working rate), so magnitudes match across platforms.
  static const double _curveSampleRate = 48000.0;

  static double _biquadMagnitude(EqFilter filter, double freq) {
    final f0 = filter.frequency;
    if (f0 <= 0 || !f0.isFinite) return 1.0;
    final a = filter.gain.abs() <= 1e-9
        ? 1.0
        : math.pow(10.0, filter.gain / 40.0).toDouble();
    final w0 = 2 * math.pi * f0 / _curveSampleRate;
    final w = 2 * math.pi * freq / _curveSampleRate;
    if (w0 <= 0 || w0 >= math.pi) return 1.0;
    final cosw0 = math.cos(w0);
    final sinw0 = math.sin(w0);
    if (filter.filterType == EqFilterType.lowShelf) {
      final s = math.sqrt(a) / math.sqrt(math.max(filter.q, 0.1));
      final alpha = sinw0 / 2 * math.sqrt((a + 1 / a) * (1 / s - 1) + 2);
      final b0 = a * ((a + 1) - (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha);
      final b1 = 2 * a * ((a - 1) - (a + 1) * cosw0);
      final b2 = a * ((a + 1) - (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha);
      final a0 = (a + 1) + (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha;
      final a1 = -2 * ((a - 1) + (a + 1) * cosw0);
      final a2 = (a + 1) + (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha;
      return _hMag(b0, b1, b2, a0, a1, a2, w);
    } else if (filter.filterType == EqFilterType.highShelf) {
      final s = math.sqrt(a) / math.sqrt(math.max(filter.q, 0.1));
      final alpha = sinw0 / 2 * math.sqrt((a + 1 / a) * (1 / s - 1) + 2);
      final b0 = a * ((a + 1) + (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha);
      final b1 = -2 * a * ((a - 1) + (a + 1) * cosw0);
      final b2 = a * ((a + 1) + (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha);
      final a0 = (a + 1) - (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha;
      final a1 = 2 * ((a - 1) - (a + 1) * cosw0);
      final a2 = (a + 1) - (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha;
      return _hMag(b0, b1, b2, a0, a1, a2, w);
    }
    // Peaking
    final alpha = sinw0 / (2 * math.max(filter.q, 0.1));
    final b0 = 1 + alpha * a;
    final b1 = -2 * cosw0;
    final b2 = 1 - alpha * a;
    final a0 = 1 + alpha / a;
    final a1 = -2 * cosw0;
    final a2 = 1 - alpha / a;
    return _hMag(b0, b1, b2, a0, a1, a2, w);
  }

  static double _hMag(double b0, double b1, double b2, double a0, double a1,
      double a2, double w) {
    final cosw = math.cos(w);
    final cos2w = math.cos(2 * w);
    final num2 = b0 * b0 +
        b1 * b1 +
        b2 * b2 +
        2 * (b0 * b1 + b1 * b2) * cosw +
        2 * b0 * b2 * cos2w;
    final den2 = a0 * a0 +
        a1 * a1 +
        a2 * a2 +
        2 * (a0 * a1 + a1 * a2) * cosw +
        2 * a0 * a2 * cos2w;
    if (den2 <= 0) return 1.0;
    return math.sqrt(math.max(num2, 0) / den2);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeadphoneProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          brand == other.brand &&
          model == other.model &&
          category == other.category &&
          _listEquals(gains, other.gains) &&
          bassBoost == other.bassBoost &&
          preampGain == other.preampGain &&
          _listEquals(filters, other.filters) &&
          source == other.source;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        brand,
        model,
        category,
        Object.hashAll(gains),
        bassBoost,
        preampGain,
        Object.hashAll(filters),
        source,
      );
}
