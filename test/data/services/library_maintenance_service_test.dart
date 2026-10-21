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

  LibraryMaintenanceService service() =>
      LibraryMaintenanceService(database: () => null, channel: channel);

  test('passes both the content URI and path to MediaStore', () async {
    final dir = Directory.systemTemp.createTempSync('library_maint');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}song.m4a')
      ..writeAsStringSync('audio');
    final part = File('${file.path}.part')..writeAsStringSync('partial');

    await service().removeDownloadedArtifacts(
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
}
