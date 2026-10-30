import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/services/library_maintenance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.library_maintenance');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  LibraryMaintenanceService service({List<String>? roots}) =>
      LibraryMaintenanceService(
        database: () => null,
        channel: channel,
        allowedDeleteRoots: roots == null ? null : () async => roots,
      );

  Directory tempDir() {
    final dir = Directory.systemTemp.createTempSync('library_maint');
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir;
  }

  test('passes both the content URI and path to MediaStore', () async {
    final dir = tempDir();
    final file = File('${dir.path}${Platform.pathSeparator}song.m4a')
      ..writeAsStringSync('audio');
    final part = File('${file.path}.part')..writeAsStringSync('partial');

    await service(roots: [dir.path]).removeDownloadedArtifacts(
      filePath: file.path,
      contentUri: 'content://media/external/audio/media/42',
    );

    expect(calls.single.method, 'deleteFromMusic');
    expect(calls.single.arguments, {
      'path': file.path,
      'contentUri': 'content://media/external/audio/media/42',
    });
    expect(file.existsSync(), isFalse);
    expect(part.existsSync(), isFalse);
  });

  test('a content URI alone still reaches the platform', () async {
    await service().removeDownloadedArtifacts(
      contentUri: 'content://media/external/audio/media/7',
    );

    expect(calls.single.arguments, {
      'contentUri': 'content://media/external/audio/media/7',
    });
  });

  test('refuses to delete a persisted path outside the allowed roots',
      () async {
    final allowed = tempDir();
    final outside = tempDir();
    final file = File('${outside.path}${Platform.pathSeparator}user.flac')
      ..writeAsStringSync('audio');

    await service(roots: [allowed.path]).removeDownloadedArtifacts(
      filePath: file.path,
    );

    // The MediaStore request still ran; the direct delete did not.
    expect(calls.single.method, 'deleteFromMusic');
    expect(file.existsSync(), isTrue);
  });

  test('refuses when no root can be resolved (fails closed)', () async {
    final dir = tempDir();
    final file = File('${dir.path}${Platform.pathSeparator}song.mp3')
      ..writeAsStringSync('audio');

    // `roots: const []` models an unsupported platform / unavailable provider.
    await service(roots: const []).removeDownloadedArtifacts(
      filePath: file.path,
    );

    expect(file.existsSync(), isTrue);
  });

  test('never deletes a non-audio file even inside an allowed root', () async {
    final dir = tempDir();
    final file = File('${dir.path}${Platform.pathSeparator}notes.txt')
      ..writeAsStringSync('text');

    await service(roots: [dir.path]).removeDownloadedArtifacts(
      filePath: file.path,
    );

    expect(file.existsSync(), isTrue);
  });
}
