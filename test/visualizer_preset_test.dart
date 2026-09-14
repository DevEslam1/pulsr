import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/visualizer_preset.dart';

void main() {
  group('VisualizerPreset.fromJsonString', () {
    test('parses shape, colors, counts and clamps ranges', () {
      const source = '''
      {
        "name": "Neon",
        "shape": "radial",
        "primaryColor": "#FF00AA",
        "secondaryColor": "cyan",
        "backgroundColor": "#101010",
        "barCount": 999,
        "rotationSpeed": 5.0,
        "glow": 2.0,
        "sensitivity": 0.1,
        "mirror": true
      }
      ''';
      final p = VisualizerPreset.fromJsonString(source);
      expect(p.name, 'Neon');
      expect(p.shape, VisualizerShape.radial);
      expect(p.primaryColor, 0xFFFF00AA);
      expect(p.secondaryColor, 0xFF00BCD4);
      expect(p.backgroundColor, 0xFF101010);
      expect(p.barCount, 128); // clamped
      expect(p.rotationSpeed, 2.0);
      expect(p.glow, 1.0);
      expect(p.sensitivity, 0.2);
      expect(p.mirror, true);
    });

    test('accepts ARGB integer colors and defaults unknown shape to bars', () {
      final p = VisualizerPreset.fromJsonString(
          '{"shape":"nonsense","color":255}');
      expect(p.shape, VisualizerShape.bars);
      expect(p.primaryColor, 0xFF0000FF);
      expect(p.name, 'Custom Preset');
    });

    test('throws on invalid JSON and non-object roots', () {
      expect(() => VisualizerPreset.fromJsonString('not json'),
          throwsFormatException);
      expect(
          () => VisualizerPreset.fromJsonString('[1,2,3]'), throwsFormatException);
    });

    test('round-trips through toJson', () {
      const original = VisualizerPreset(
        name: 'Round',
        shape: VisualizerShape.lissajous,
        barCount: 48,
        glow: 0.25,
        mirror: true,
      );
      final restored =
          VisualizerPreset.fromJsonString(jsonEncode(original.toJson()));
      expect(restored.name, original.name);
      expect(restored.shape, original.shape);
      expect(restored.barCount, original.barCount);
      expect(restored.glow, original.glow);
      expect(restored.mirror, original.mirror);
    });
  });
}
