// lib/domain/models/milkdrop_preset.dart

/// A parsed Milkdrop (`.milk`) preset.
///
/// HONEST SCOPE: this parses the classic Winamp/Milkdrop preset parameter set
/// (per-frame scalars and wave/shape settings) and drives a GPU-free,
/// Canvas-based renderer from it. The preset's HSLSL `warp`/`comp` shader
/// source and per-vertex EEL equations are retained in [raw] but are not
/// executed — Pulsr renders an approximation from the preset's motion
/// parameters rather than running the original shader.
class MilkdropPreset {
  final String name;
  final double zoom;
  final double zoomExp;
  final double rot;
  final double warp;
  final double decay;
  final double gammaAdj;
  final double waveScale;
  final double waveR;
  final double waveG;
  final double waveB;
  final int waveMode;
  @Deprecated('Parsed from legacy Milkdrop .milk files but unused by renderer')
  final double fRating;
  final Map<String, String> raw;

  const MilkdropPreset({
    required this.name,
    this.zoom = 1.0,
    this.zoomExp = 1.0,
    this.rot = 0.0,
    this.warp = 1.0,
    this.decay = 0.95,
    this.gammaAdj = 1.0,
    this.waveScale = 1.0,
    this.waveR = 1.0,
    this.waveG = 1.0,
    this.waveB = 1.0,
    this.waveMode = 0,
    this.fRating = 3.0,
    this.raw = const {},
  });

  static const MilkdropPreset fallback = MilkdropPreset(
    name: 'Pulsr Default',
    zoom: 1.0,
    decay: 0.95,
    waveR: 0.4,
    waveG: 0.7,
    waveB: 1.0,
  );

  static double _d(Map<String, String> m, String key, double fallback) {
    final v = m[key];
    if (v == null) return fallback;
    return double.tryParse(v.trim()) ?? fallback;
  }

  static int _i(Map<String, String> m, String key, int fallback) {
    final v = m[key];
    if (v == null) return fallback;
    return int.tryParse(v.trim().split('.').first) ?? fallback;
  }

  /// Parses a Milkdrop `.milk` file. Malformed lines are ignored rather than
  /// throwing, so a partially corrupt preset still yields a usable result.
  factory MilkdropPreset.fromMilk(String content, {String? fallbackName}) {
    final values = <String, String>{};
    var name = fallbackName;
    for (var line in content.split(RegExp(r'\r?\n'))) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('//')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();
      if (key.isEmpty) continue;
      if (!values.containsKey(key)) {
        values[key] = value;
      }
      // Milkdrop's window title line is a bare comment; use the preset's
      // documented name keys when present.
      if (key.toLowerCase() == 'presetname' && value.isNotEmpty) {
        name = value;
      }
    }
    return MilkdropPreset(
      name: name ?? values['name'] ?? values['presetName'] ?? 'Imported Preset',
      zoom: _d(values, 'zoom', 1.0),
      zoomExp: _d(values, 'zoomexp', 1.0),
      rot: _d(values, 'rot', 0.0),
      warp: _d(values, 'warp', 1.0),
      decay: _d(values, 'decay', 0.95),
      gammaAdj: _d(values, 'gammaadj', 1.0),
      waveScale: _d(values, 'wavescale', 1.0),
      waveR: _d(values, 'waver', 1.0),
      waveG: _d(values, 'waveg', 1.0),
      waveB: _d(values, 'waveb', 1.0),
      waveMode: _i(values, 'wavemode', 0),
      fRating: _d(values, 'frating', 3.0),
      raw: values,
    );
  }
}

/// Built-in presets offered when no user preset is imported.
class MilkdropPresetLibrary {
  static const List<MilkdropPreset> presets = <MilkdropPreset>[
    MilkdropPreset(
      name: 'Pulsr Nebula',
      zoom: 1.04,
      rot: 0.01,
      warp: 1.2,
      decay: 0.96,
      waveScale: 1.1,
      waveR: 0.45,
      waveG: 0.55,
      waveB: 1.0,
    ),
    MilkdropPreset(
      name: 'Solar Bloom',
      zoom: 1.02,
      rot: -0.02,
      warp: 0.9,
      decay: 0.94,
      waveScale: 0.9,
      waveR: 1.0,
      waveG: 0.6,
      waveB: 0.25,
    ),
    MilkdropPreset(
      name: 'Emerald Tunnel',
      zoom: 1.06,
      rot: 0.03,
      warp: 1.4,
      decay: 0.97,
      waveScale: 1.3,
      waveR: 0.3,
      waveG: 1.0,
      waveB: 0.6,
    ),
  ];

  static MilkdropPreset get defaultPreset => presets.first;
}
