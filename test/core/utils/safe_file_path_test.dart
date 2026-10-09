// test/core/utils/safe_file_path_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/safe_file_path.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('safe_file_path_test');
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  File writeTemp(String name, [String contents = 'x']) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    file.writeAsStringSync(contents);
    return file;
  }

  group('SafeFilePath.validate', () {
    test('rejects null, empty, and whitespace-only paths', () {
      expect(SafeFilePath.validate(null), isNull);
      expect(SafeFilePath.validate(''), isNull);
      expect(SafeFilePath.validate('   '), isNull);
    });

    test('rejects null-byte injection', () {
      expect(SafeFilePath.validate('/tmp/evil\x00.mp3'), isNull);
    });

    test('rejects a path that does not exist when checkExists is true', () {
      final missing = File(
          '${tempDir.path}${Platform.pathSeparator}does_not_exist.mp3');
      expect(SafeFilePath.validate(missing.path), isNull);
    });

    test('accepts an existing regular file', () {
      final file = writeTemp('song.mp3', 'audio');
      final result = SafeFilePath.validate(file.path);
      expect(result, isNotNull);
      expect(result!.path, file.path);
    });

    test('rejects a directory', () {
      final sub = Directory(
          '${tempDir.path}${Platform.pathSeparator}a_subdir');
      sub.createSync();
      expect(SafeFilePath.validate(sub.path), isNull);
    });

    test('returns the file without checking existence when checkExists false',
        () {
      final path =
          '${tempDir.path}${Platform.pathSeparator}not_yet_written.json';
      final result = SafeFilePath.validate(path, checkExists: false);
      expect(result, isNotNull);
    });

    test('rejects disallowed extensions', () {
      final file = writeTemp('notes.exe', 'binary');
      expect(
        SafeFilePath.validate(file.path, allowedExtensions: ['.json', '.txt']),
        isNull,
      );
    });

    test('accepts allowed extensions with or without a leading dot', () {
      final file = writeTemp('backup.json', '{}');
      expect(
        SafeFilePath.validate(file.path, allowedExtensions: ['json']),
        isNotNull,
      );
      expect(
        SafeFilePath.validate(file.path, allowedExtensions: ['.json']),
        isNotNull,
      );
    });

    test('extension matching is case-insensitive', () {
      final file = writeTemp('track.MP3', 'audio');
      expect(
        SafeFilePath.validate(file.path, allowedExtensions: ['.mp3']),
        isNotNull,
      );
      expect(
        SafeFilePath.validate(file.path, allowedExtensions: ['.MP3']),
        isNotNull,
      );
    });

    test('empty allowedExtensions list disables the restriction', () {
      final file = writeTemp('anything.weird', 'data');
      expect(
        SafeFilePath.validate(file.path, allowedExtensions: const []),
        isNotNull,
      );
    });
  });

  group('SafeFilePath.validateSavePath', () {
    test('accepts a non-existent path for writing', () {
      final path = '${tempDir.path}${Platform.pathSeparator}save_me.json';
      final result = SafeFilePath.validateSavePath(path);
      expect(result, isNotNull);
    });

    test('still enforces extensions for save paths', () {
      final path = '${tempDir.path}${Platform.pathSeparator}save_me.exe';
      expect(
        SafeFilePath.validateSavePath(path, allowedExtensions: ['.json']),
        isNull,
      );
    });

    test('rejects null and null-byte save paths', () {
      expect(SafeFilePath.validateSavePath(null), isNull);
      expect(SafeFilePath.validateSavePath('/tmp/x\x00.json'), isNull);
    });
  });
}
