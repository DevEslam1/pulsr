import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/milkdrop_preset.dart';

void main() {
  group('MilkdropPreset.fromMilk', () {
    test('parses motion parameters and name', () {
      const content = '''
// classic milkdrop file
[preset00]
presetName=Test Vision
zoom=1.05
rot=0.02
warp=1.3
decay=0.97
waver=0.4
waveg=0.5
waveb=0.9
wavemode=2
''';
      final p = MilkdropPreset.fromMilk(content);
      expect(p.name, 'Test Vision');
      expect(p.zoom, closeTo(1.05, 1e-9));
      expect(p.rot, closeTo(0.02, 1e-9));
      expect(p.warp, closeTo(1.3, 1e-9));
      expect(p.decay, closeTo(0.97, 1e-9));
      expect(p.waveR, closeTo(0.4, 1e-9));
      expect(p.waveG, closeTo(0.5, 1e-9));
      expect(p.waveB, closeTo(0.9, 1e-9));
      expect(p.waveMode, 2);
    });

    test('ignores malformed lines and applies defaults', () {
      const content = '''
this line has no equals
[preset00]
zoom=1.1
=missing key
''';
      final p = MilkdropPreset.fromMilk(content, fallbackName: 'Fallback');
      expect(p.name, 'Fallback');
      expect(p.zoom, closeTo(1.1, 1e-9));
      expect(p.decay, closeTo(0.95, 1e-9));
      expect(p.waveMode, 0);
    });

    test('built-in library is non-empty', () {
      expect(MilkdropPresetLibrary.presets, isNotEmpty);
      expect(MilkdropPresetLibrary.defaultPreset.name, isNotEmpty);
    });
  });
}
