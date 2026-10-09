// test/data/visualizer/milkdrop_preset_store_test.dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/visualizer/milkdrop_preset_store.dart';
import 'package:pulsr/domain/models/milkdrop_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_file_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('pulsr_milk_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeFile(String name, String content) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    file.writeAsStringSync(content);
    return file;
  }

  group('MilkdropPresetStore persistence', () {
    test('load returns the default preset when nothing is stored', () async {
      final store = MilkdropPresetStore();
      final preset = await store.load();
      expect(preset.name, MilkdropPresetLibrary.defaultPreset.name);
    });

    test('save then load round-trips the raw preset text', () async {
      final store = MilkdropPresetStore();
      const preset = MilkdropPreset(name: 'Nebula Copy', zoom: 1.2);
      await store.save(preset, 'presetName=Nebula Copy\nzoom=1.2\n');

      final loaded = await store.load();
      expect(loaded.name, 'Nebula Copy');
      expect(loaded.zoom, 1.2);
    });

    test('load falls back when the stored content is blank', () async {
      SharedPreferences.setMockInitialValues({
        'setting_milkdrop_preset': '   ',
      });
      final store = MilkdropPresetStore();
      expect((await store.load()).name,
          MilkdropPresetLibrary.defaultPreset.name);
    });

    test('clear removes the stored preset', () async {
      final store = MilkdropPresetStore();
      await store.save(const MilkdropPreset(name: 'Temp'), 'zoom=1\n');
      await store.clear();
      expect((await store.load()).name,
          MilkdropPresetLibrary.defaultPreset.name);
    });
  });

  group('MilkdropPresetStore.importFromFile', () {
    test('returns null when the picker is cancelled', () async {
      FilePickerPlatform.instance =
          FakeFilePickerPlatform(result: () => null);
      expect(await MilkdropPresetStore().importFromFile(), isNull);
    });

    test('returns null for a disallowed extension', () async {
      final file = writeFile('bad.txt', 'zoom=1');
      FilePickerPlatform.instance =
          FakeFilePickerPlatform(result: () => FakePlatformFile(file.path));
      expect(await MilkdropPresetStore().importFromFile(), isNull);
    });

    test('rejects a file larger than maxImportBytes', () async {
      final file =
          File('${tempDir.path}${Platform.pathSeparator}huge.milk');
      file.writeAsBytesSync(
          List<int>.filled(MilkdropPresetStore.maxImportBytes + 1, 0));
      FilePickerPlatform.instance =
          FakeFilePickerPlatform(result: () => FakePlatformFile(file.path));
      expect(await MilkdropPresetStore().importFromFile(), isNull);
    });

    test('parses, names and persists a valid preset file', () async {
      final file = writeFile(
          'cool_preset.milk', 'presetName=Neon Dream\nzoom=1.3\ndecay=0.9\n');
      FilePickerPlatform.instance = FakeFilePickerPlatform(
          result: () => FakePlatformFile(file.path, name: 'cool_preset.milk'));

      final store = MilkdropPresetStore();
      final imported = await store.importFromFile();
      expect(imported, isNotNull);
      expect(imported!.name, 'Neon Dream');
      expect(imported.zoom, 1.3);
      expect(imported.decay, 0.9);

      final reloaded = await store.load();
      expect(reloaded.name, 'Neon Dream');
    });

    test('falls back to the cleaned file name when no presetName is present',
        () async {
      final file = writeFile('my_preset.milk', 'zoom=1.1\n');
      FilePickerPlatform.instance = FakeFilePickerPlatform(
          result: () => FakePlatformFile(file.path, name: 'my_preset.milk'));

      final imported = await MilkdropPresetStore().importFromFile();
      expect(imported, isNotNull);
      expect(imported!.name, 'my_preset');
    });

    test('swallows picker errors and returns null', () async {
      FilePickerPlatform.instance = FakeFilePickerPlatform(
          error: StateError('picker exploded'));
      expect(await MilkdropPresetStore().importFromFile(), isNull);
    });
  });
}
