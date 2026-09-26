// lib/domain/models/auto_eq_profile.dart
import 'package:flutter/foundation.dart';

@immutable
class AutoEqProfile {
  final String id;
  final String name;
  final String brand;
  final String model;
  final String category;
  final List<double> gains;
  final double bassBoost;
  final double preampGain;
  final String? customGraphicEq;

  const AutoEqProfile({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    required this.category,
    required this.gains,
    this.bassBoost = 0.0,
    this.preampGain = 0.0,
    this.customGraphicEq,
  });

  factory AutoEqProfile.fromJson(Map<String, dynamic> json) {
    final rawGains = json['gains'] as List<dynamic>? ?? const [];
    final gainsList = rawGains.map((g) => (g as num).toDouble()).toList();

    return AutoEqProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      model: json['model'] as String? ?? '',
      category: json['category'] as String? ?? 'Headphones',
      gains: List.unmodifiable(gainsList),
      bassBoost: (json['bassBoost'] as num?)?.toDouble() ?? 0.0,
      preampGain: (json['preampGain'] as num?)?.toDouble() ?? 0.0,
      customGraphicEq: json['graphicEq'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'model': model,
        'category': category,
        'gains': gains,
        'bassBoost': bassBoost,
        'preampGain': preampGain,
        if (customGraphicEq != null) 'graphicEq': customGraphicEq,
      };

  /// Generates a valid EqualizerAPO `GraphicEq` string directly acceptable by
  /// `ArbitraryResponseEq::parseGraphicEq` and `loadArbitraryEq`.
  String toGraphicEqString() {
    if (customGraphicEq != null && customGraphicEq!.trim().isNotEmpty) {
      return customGraphicEq!;
    }

    if (gains.isEmpty) {
      return 'GraphicEq: 20 0.0; 20000 0.0';
    }

    final freqs = gains.length == 5
        ? const [60.0, 250.0, 1000.0, 4000.0, 12000.0]
        : gains.length == 10
            ? const [31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]
            : List<double>.generate(
                gains.length,
                (i) => 20.0 * (1000.0 / 20.0) * (i / (gains.length - 1)),
              );

    final sb = StringBuffer('GraphicEq: ');
    // Boundary sub-bass anchor
    sb.write('20 ${gains.first.toStringAsFixed(2)}; ');
    for (var i = 0; i < gains.length; i++) {
      final f = freqs[i].round();
      final g = gains[i].toStringAsFixed(2);
      sb.write('$f $g; ');
    }
    // Boundary air anchor
    sb.write('20000 ${gains.last.toStringAsFixed(2)}');
    return sb.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoEqProfile &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
