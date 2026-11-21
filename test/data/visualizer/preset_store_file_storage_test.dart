import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/visualizer/milkdrop_preset_store.dart';
import 'package:pulsr/data/visualizer/visualizer_preset_store.dart';
import 'package:pulsr/domain/models/milkdrop_preset.dart';
import 'package:pulsr/domain/models/visualizer_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_file_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('pulsr_preset_test_');
    VisualizerPresetStore.directoryProvider = () async => tempDir;
    MilkdropPresetStore.directoryProvider = () async => tempDir;
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('VisualizerPresetStore file storage', () {
    test('stores preset file in visualizer_presets/ directory and only filename in SharedPreferences', () async {
      final store = VisualizerPresetStore();
      const preset = VisualizerPreset(
        name: 'FilePreset',
        shape: VisualizerShape.radial,
        barCount: 32,
      );

      await store.save(preset);

      final prefs = await SharedPreferences.getInstance();
      final storedKey = prefs.getString('setting_custom_visualizer_preset');
      expect(storedKey, 'custom_preset.json');

      final expectedFile = File('${tempDir.path}/visualizer_presets/custom_preset.json');
      expect(expectedFile.existsSync(), isTrue);
      expect(expectedFile.readAsStringSync(), contains('FilePreset'));

      final loaded = await store.load();
      expect(loaded.name, 'FilePreset');
      expect(loaded.shape, VisualizerShape.radial);
      expect(loaded.barCount, 32);
    });

    test('rethrows from save so importFromFile does not report false success on failure', () async {
      // Create a directory at the file path so writeAsString fails with FileSystemException
      Directory('${tempDir.path}/visualizer_presets/custom_preset.json').createSync(recursive: true);

      final store = VisualizerPresetStore();
      // Directly saving rethrows
      expect(
        () => store.save(const VisualizerPreset(name: 'Fail')),
        throwsA(isA<FileSystemException>()),
      );

      // importFromFile catches and returns null
      final validPresetFile = File('${tempDir.path}/test.json');
      validPresetFile.writeAsStringSync('{"name":"Test","shape":"bars","barCount":16}');

      FilePickerPlatform.instance = FakeFilePickerPlatform(
        result: () => FakePlatformFile(validPresetFile.path),
      );

      final imported = await store.importFromFile();
      expect(imported, isNull);
    });
  });

  group('MilkdropPresetStore file storage', () {
    test('stores preset file in visualizer_presets/ directory and only filename/name in SharedPreferences', () async {
      final store = MilkdropPresetStore();
      const preset = MilkdropPreset(name: 'MilkFilePreset', zoom: 1.5);
      const rawMilk = 'presetName=MilkFilePreset\nzoom=1.5\n';

      await store.save(preset, rawMilk);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('setting_milkdrop_preset_file'), 'custom_preset.milk');
      expect(prefs.getString('setting_milkdrop_preset_name'), 'MilkFilePreset');
      expect(prefs.getString('setting_milkdrop_preset'), isNull);

      final expectedFile = File('${tempDir.path}/visualizer_presets/custom_preset.milk');
      expect(expectedFile.existsSync(), isTrue);
      expect(expectedFile.readAsStringSync(), rawMilk);

      final loaded = await store.load();
      expect(loaded.name, 'MilkFilePreset');
      expect(loaded.zoom, 1.5);
    });

    test('rethrows from save so importFromFile does not report false success on failure', () async {
      // Create a directory at the file path so writeAsString fails with FileSystemException
      Directory('${tempDir.path}/visualizer_presets/custom_preset.milk').createSync(recursive: true);

      final store = MilkdropPresetStore();
      expect(
        () => store.save(const MilkdropPreset(name: 'Fail'), 'zoom=1\n'),
        throwsA(isA<FileSystemException>()),
      );

      final validPresetFile = File('${tempDir.path}/test.milk');
      validPresetFile.writeAsStringSync('presetName=Test\nzoom=1.0\n');

      FilePickerPlatform.instance = FakeFilePickerPlatform(
        result: () => FakePlatformFile(validPresetFile.path, name: 'test.milk'),
      );

      final imported = await store.importFromFile();
      expect(imported, isNull);
    });
  });
}
