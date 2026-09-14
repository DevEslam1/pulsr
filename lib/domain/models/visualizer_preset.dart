// lib/domain/models/visualizer_preset.dart
import 'dart:convert';

/// Shape family rendered by the Custom (JSON) visualizer.
enum VisualizerShape { bars, wave, radial, particles, lissajous }

VisualizerShape _shapeFromName(String? name) {
  switch ((name ?? '').toLowerCase()) {
    case 'wave':
      return VisualizerShape.wave;
    case 'radial':
    case 'circular':
      return VisualizerShape.radial;
    case 'particles':
      return VisualizerShape.particles;
    case 'lissajous':
      return VisualizerShape.lissajous;
    case 'bars':
    default:
      return VisualizerShape.bars;
  }
}

String _shapeName(VisualizerShape shape) => shape.name;

/// Converts a JSON color value (ARGB int, "#RRGGBB", "#AARRGGBB" or a name)
/// into an opaque ARGB int. Returns [fallback] for anything unrecognized.
int _parseColor(dynamic value, int fallback) {
  if (value is int) {
    return value <= 0xFFFFFF ? (0xFF000000 | value) : value;
  }
  if (value is String) {
    final s = value.trim();
    if (s.startsWith('#')) {
      final hex = s.substring(1);
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) {
        return hex.length <= 6 ? (0xFF000000 | parsed) : parsed;
      }
    }
    final named = _namedColors[s.toLowerCase()];
    if (named != null) return named;
  }
  return fallback;
}

const Map<String, int> _namedColors = {
  'white': 0xFFFFFFFF,
  'black': 0xFF000000,
  'red': 0xFFF44336,
  'green': 0xFF4CAF50,
  'blue': 0xFF2196F3,
  'cyan': 0xFF00BCD4,
  'magenta': 0xFFE91E63,
  'yellow': 0xFFFFEB3B,
  'orange': 0xFFFF9800,
  'purple': 0xFF9C27B0,
};

/// A user-authored Custom visualizer preset. Persisted as JSON.
class VisualizerPreset {
  final String name;
  final VisualizerShape shape;
  final int primaryColor;
  final int secondaryColor;
  final int backgroundColor;
  final int barCount;
  final double rotationSpeed;
  final double glow;
  final double sensitivity;
  final bool mirror;

  const VisualizerPreset({
    required this.name,
    this.shape = VisualizerShape.bars,
    this.primaryColor = 0xFF9B9EF5,
    this.secondaryColor = 0xFF3DDC97,
    this.backgroundColor = 0x00000000,
    this.barCount = 32,
    this.rotationSpeed = 0.0,
    this.glow = 0.5,
    this.sensitivity = 1.0,
    this.mirror = false,
  });

  static const VisualizerPreset fallback = VisualizerPreset(
    name: 'Pulsr Spectrum',
    shape: VisualizerShape.bars,
  );

  static double _clamp(double v, double lo, double hi) =>
      v.isFinite ? v.clamp(lo, hi).toDouble() : lo;

  /// Parses a JSON preset string. Throws [FormatException] on invalid JSON or
  /// a non-object root so callers can fall back explicitly.
  factory VisualizerPreset.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Visualizer preset must be a JSON object');
    }
    final map = decoded.cast<String, dynamic>();
    return VisualizerPreset(
      name: (map['name'] as String?)?.trim().isNotEmpty == true
          ? (map['name'] as String).trim()
          : 'Custom Preset',
      shape: _shapeFromName(map['shape'] as String?),
      primaryColor: _parseColor(
          map['primaryColor'] ?? map['color'], 0xFF9B9EF5),
      secondaryColor: _parseColor(map['secondaryColor'], 0xFF3DDC97),
      backgroundColor: _parseColor(map['backgroundColor'], 0x00000000),
      barCount: map['barCount'] is num
          ? (map['barCount'] as num).toInt().clamp(4, 128)
          : 32,
      rotationSpeed: _clamp(
          (map['rotationSpeed'] as num?)?.toDouble() ?? 0.0, -2.0, 2.0),
      glow: _clamp((map['glow'] as num?)?.toDouble() ?? 0.5, 0.0, 1.0),
      sensitivity: _clamp(
          (map['sensitivity'] as num?)?.toDouble() ?? 1.0, 0.2, 4.0),
      mirror: map['mirror'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'shape': _shapeName(shape),
        'primaryColor': primaryColor,
        'secondaryColor': secondaryColor,
        'backgroundColor': backgroundColor,
        'barCount': barCount,
        'rotationSpeed': rotationSpeed,
        'glow': glow,
        'sensitivity': sensitivity,
        'mirror': mirror,
      };
}
