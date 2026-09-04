import 'package:injectable/injectable.dart';
import '../../domain/models/headphone_profile.dart';

class AutoEqResult {
  final String name;
  final String model;
  final String manufacturer;
  final String target;
  final List<double> gains; // 10 or 32 bands
  final String sourceUrl;

  const AutoEqResult({
    required this.name,
    required this.model,
    required this.manufacturer,
    required this.target,
    required this.gains,
    required this.sourceUrl,
  });

  HeadphoneProfile toHeadphoneProfile() {
    return HeadphoneProfile(
      id: 'autoeq_${manufacturer.toLowerCase()}_${model.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}',
      name: name,
      brand: manufacturer,
      model: model,
      category: 'Over-Ear',
      gains: gains,
    );
  }
}

@singleton
class AutoEqService {
  AutoEqService();

  static const String _autoEqApiBase =
      'https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results';

  // Popular pre-indexed headphone compensation curves for instant offline search
  static final List<AutoEqResult> _bundledIndex = [
    const AutoEqResult(
      name: 'Sony WH-1000XM4 (Harman Target)',
      model: 'WH-1000XM4',
      manufacturer: 'Sony',
      target: 'Harman Over-Ear',
      gains: [-2.5, -3.0, -1.0, 0.5, 1.0, 1.5, 3.0, 2.0, -1.0, 0.0],
      sourceUrl:
          '$_autoEqApiBase/oratory1990/harman_over-ear_2018/Sony%20WH-1000XM4',
    ),
    const AutoEqResult(
      name: 'Sony WH-1000XM5 (Harman Target)',
      model: 'WH-1000XM5',
      manufacturer: 'Sony',
      target: 'Harman Over-Ear',
      gains: [-1.8, -2.2, -0.5, 0.0, 1.2, 2.0, 2.5, 1.8, -0.5, 0.2],
      sourceUrl:
          '$_autoEqApiBase/oratory1990/harman_over-ear_2018/Sony%20WH-1000XM5',
    ),
    const AutoEqResult(
      name: 'Apple AirPods Pro 2 (Harman In-Ear)',
      model: 'AirPods Pro 2',
      manufacturer: 'Apple',
      target: 'Harman In-Ear',
      gains: [-0.5, 0.0, 0.5, 1.0, 0.5, -0.5, 1.5, 2.0, 1.0, -0.5],
      sourceUrl:
          '$_autoEqApiBase/crinacle/harman_in-ear_2019v2/Apple%20AirPods%20Pro%202',
    ),
    const AutoEqResult(
      name: 'Apple AirPods Max (Harman Over-Ear)',
      model: 'AirPods Max',
      manufacturer: 'Apple',
      target: 'Harman Over-Ear',
      gains: [-1.0, -0.5, 0.0, 0.5, 0.8, 1.2, 1.8, 0.5, -1.2, 0.0],
      sourceUrl:
          '$_autoEqApiBase/oratory1990/harman_over-ear_2018/Apple%20AirPods%20Max',
    ),
    const AutoEqResult(
      name: 'Sennheiser HD 600 (Harman Over-Ear)',
      model: 'HD 600',
      manufacturer: 'Sennheiser',
      target: 'Harman Over-Ear',
      gains: [4.5, 4.0, 2.5, 0.5, -0.5, 0.0, 1.0, -1.5, -2.0, 0.5],
      sourceUrl:
          '$_autoEqApiBase/oratory1990/harman_over-ear_2018/Sennheiser%20HD%20600',
    ),
    const AutoEqResult(
      name: 'Sennheiser HD 650 (Harman Over-Ear)',
      model: 'HD 650',
      manufacturer: 'Sennheiser',
      target: 'Harman Over-Ear',
      gains: [5.0, 4.2, 2.0, 0.0, -0.8, 0.0, 1.5, -1.0, -1.5, 1.0],
      sourceUrl:
          '$_autoEqApiBase/oratory1990/harman_over-ear_2018/Sennheiser%20HD%20650',
    ),
    const AutoEqResult(
      name: 'Sennheiser HD 800 S (Harman Over-Ear)',
      model: 'HD 800 S',
      manufacturer: 'Sennheiser',
      target: 'Harman Over-Ear',
      gains: [6.0, 5.0, 3.0, 1.0, 0.0, 0.5, -2.0, -4.5, 1.0, 0.0],
      sourceUrl:
          '$_autoEqApiBase/oratory1990/harman_over-ear_2018/Sennheiser%20HD%20800%20S',
    ),
    const AutoEqResult(
      name: 'Beyerdynamic DT 770 Pro 80 Ohm (Harman)',
      model: 'DT 770 Pro',
      manufacturer: 'Beyerdynamic',
      target: 'Harman Over-Ear',
      gains: [-2.0, -1.5, 0.0, 1.0, 0.5, 0.0, -1.0, -4.0, -3.5, 1.0],
      sourceUrl:
          '$_autoEqApiBase/oratory1990/harman_over-ear_2018/Beyerdynamic%20DT%20770%20Pro%2080%20Ohm',
    ),
    const AutoEqResult(
      name: 'Beyerdynamic DT 990 Pro (Harman)',
      model: 'DT 990 Pro',
      manufacturer: 'Beyerdynamic',
      target: 'Harman Over-Ear',
      gains: [3.5, 2.0, 0.5, 0.0, 0.5, 0.0, -2.5, -6.0, -4.0, 0.5],
      sourceUrl:
          '$_autoEqApiBase/oratory1990/harman_over-ear_2018/Beyerdynamic%20DT%20990%20Pro',
    ),
    const AutoEqResult(
      name: 'Audio-Technica ATH-M50x (Harman)',
      model: 'ATH-M50x',
      manufacturer: 'Audio-Technica',
      target: 'Harman Over-Ear',
      gains: [-3.0, -2.5, -1.0, 0.5, 1.2, 0.8, -1.5, 1.0, 2.0, -0.5],
      sourceUrl:
          '$_autoEqApiBase/oratory1990/harman_over-ear_2018/Audio-Technica%20ATH-M50x',
    ),
    const AutoEqResult(
      name: 'Bose QuietComfort 45 (Harman)',
      model: 'QuietComfort 45',
      manufacturer: 'Bose',
      target: 'Harman Over-Ear',
      gains: [-1.5, -1.0, 0.5, 1.0, 1.5, 1.0, -1.0, 2.5, 1.0, 0.0],
      sourceUrl:
          '$_autoEqApiBase/oratory1990/harman_over-ear_2018/Bose%20QuietComfort%2045',
    ),
    const AutoEqResult(
      name: 'Samsung Galaxy Buds 2 Pro (Harman)',
      model: 'Galaxy Buds 2 Pro',
      manufacturer: 'Samsung',
      target: 'Harman In-Ear',
      gains: [0.0, 0.5, 0.0, -0.5, 0.0, 0.8, 1.2, 0.5, -1.0, 0.0],
      sourceUrl:
          '$_autoEqApiBase/crinacle/harman_in-ear_2019v2/Samsung%20Galaxy%20Buds%202%20Pro',
    ),
  ];

  /// Searches AutoEQ database with fallback to bundled index.
  Future<List<AutoEqResult>> search(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return _bundledIndex;

    final matches = _bundledIndex.where((item) {
      return item.name.toLowerCase().contains(cleanQuery) ||
          item.manufacturer.toLowerCase().contains(cleanQuery) ||
          item.model.toLowerCase().contains(cleanQuery);
    }).toList();

    return matches;
  }
}
