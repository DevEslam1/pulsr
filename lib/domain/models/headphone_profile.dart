// lib/domain/models/headphone_profile.dart
import 'eq_preset.dart';

class HeadphoneProfile {
  final String id;
  final String name;
  final String brand;
  final String model;
  final String category; // 'Target Curve', 'In-Ear', 'TWS Earbuds', 'Over-Ear', 'On-Ear', 'Earbuds'
  final List<double> gains; // 10-band gains in dB, aligned to EqPreset.centerFrequencies
  final double bassBoost; // 0.0 to 1.0
  final double preampGain; // in dB

  const HeadphoneProfile({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    required this.category,
    required this.gains,
    this.bassBoost = 0.0,
    this.preampGain = 0.0,
  });

  factory HeadphoneProfile.fromJson(Map<String, dynamic> json) {
    return HeadphoneProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String,
      model: json['model'] as String,
      category: json['category'] as String? ?? 'Headphone',
      // Bundled profiles ship 5-band curves; up-sample to the 10 ISO centers.
      gains: EqPreset.interpolateGains(
        (json['gains'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
      ),
      bassBoost: (json['bassBoost'] as num?)?.toDouble() ?? 0.0,
      preampGain: (json['preampGain'] as num?)?.toDouble() ?? 0.0,
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
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeadphoneProfile && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
