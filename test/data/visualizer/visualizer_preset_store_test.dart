// test/data/visualizer/visualizer_preset_store_test.dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/visualizer/visualizer_preset_store.dart';
import 'package:pulsr/domain/models/visualizer_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_file_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('pulsr_viz_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeFile(String name, String content) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    file.writeAsStringSync(content);
    return file;
  }

  group('VisualizerPresetStore persistence', () {
    test('load returns the fallback preset when nothing is stored', () async {
      final store = VisualizerPresetStore();
      final preset = await store.load();
      expect(preset.name, VisualizerPreset.fallback.name);
      expect(preset.shape, VisualizerPreset.fallback.shape);
    });

    test('save then load round-trips the authored preset', () async {
      final store = VisualizerPresetStore();
      const authored = VisualizerPreset(
        name: 'Neon Bars',
        shape: VisualizerShape.radial,
        barCount: 64,
      );
      await store.save(authored);

      final loaded = await store.load();
      expect(loaded.name, 'Neon Bars');
      expect(loaded.shape, VisualizerShape.radial);
      expect(loaded.barCount, 64);
    });

    test('load falls back when the stored value is corrupt JSON', () async {
      SharedPreferences.setMockInitialValues({
        'setting_custom_visualizer_preset': '{not json',
      });
      final store = VisualizerPresetStore();
      expect((await store.load()).name, VisualizerPreset.fallback.name);
    });

    test('clear removes the stored preset', () async {
      final store = VisualizerPresetStore();
      await store.save(const VisualizerPreset(name: 'Temp'));
      await store.clear();
      expect((await store.load()).name, VisualizerPreset.fallback.name);
    });
  });

  group('VisualizerPresetStore.importFromFile', () {
    test('returns null when the picker is cancelled', () async {
      FilePickerPlatform.instance =
          FakeFilePickerPlatform(result: () => null);
      expect(await VisualizerPresetStore().importFromFile(), isNull);
    });

    test('returns null for a disallowed extension', () async {
      final file = writeFile('bad.txt', '{}');
      FilePickerPlatform.instance =
          FakeFilePickerPlatform(result: () => FakePlatformFile(file.path));
      expect(await VisualizerPresetStore().importFromFile(), isNull);
    });

    test('rejects a file larger than maxImportBytes', () async {
      final file = File(
          '${tempDir.path}${Platform.pathSeparator}huge.json');
      file.writeAsBytesSync(
          List<int>.filled(VisualizerPresetStore.maxImportBytes + 1, 0));
      FilePickerPlatform.instance =
          FakeFilePickerPlatform(result: () => FakePlatformFile(file.path));
      expect(await VisualizerPresetStore().importFromFile(), isNull);
    });

    test('parses and persists a valid preset file', () async {
      final file = writeFile('custom.json',
          '{"name":"Imported","shape":"wave","barCount":48}');
      FilePickerPlatform.instance =
          FakeFilePickerPlatform(result: () => FakePlatformFile(file.path));

      final store = VisualizerPresetStore();
      final imported = await store.importFromFile();
      expect(imported, isNotNull);
      expect(imported!.name, 'Imported');
      expect(imported.shape, VisualizerShape.wave);

      final reloaded = await store.load();
      expect(reloaded.name, 'Imported');
      expect(reloaded.barCount, 48);
    });

    test('swallows picker errors and returns null', () async {
      FilePickerPlatform.instance = FakeFilePickerPlatform(
          error: StateError('picker exploded'));
      expect(await VisualizerPresetStore().importFromFile(), isNull);
    });
  });
}
