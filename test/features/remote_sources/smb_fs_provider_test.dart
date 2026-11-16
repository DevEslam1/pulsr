// P0-1 remote sources: the SMB MethodChannel contract, without a device.
//
// The real bridge lives in SmbPlugin.kt; these tests pin the Dart side: the
// argument shape sent to it, the entry parsing, and the promise that a missing
// or failing channel raises a typed error instead of an empty folder.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/interfaces/remote_fs_provider.dart';
import 'package:pulsr/domain/models/remote_source.dart';
import 'package:pulsr/features/remote_sources/smb_fs_provider.dart';

RemoteSource _smbSource({String root = '/Music/Studio'}) {
  return RemoteSource.create(
    kind: RemoteSourceKind.smb,
    displayName: 'Share',
    host: 'fileserver',
    port: 445,
    rootPath: root,
    username: r'WORKGROUP\media',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(SmbFsProvider.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void install(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('a missing plugin raises RemoteUnavailableError, never an empty folder',
      () async {
    // No handler installed: the platform side is absent, exactly like desktop
    // or a build without the smbj dependency.
    final provider = SmbFsProvider(_smbSource());

    await expectLater(
      provider.list(''),
      throwsA(
        isA<RemoteUnavailableError>().having(
          (error) => error.userMessage,
          'userMessage',
          contains('Android'),
        ),
      ),
    );
  });

  test('list sends host, port, share and the share-relative path', () async {
    install((call) async {
      if (call.method == 'list') {
        return <Map<String, Object?>>[
          {
            'path': 'Studio/Albums',
            'name': 'Albums',
            'isDirectory': true,
          },
          {
            'path': 'Studio/song.mp3',
            'name': 'song.mp3',
            'isDirectory': false,
            'sizeBytes': 1234,
            'modifiedAt': 1700000000000,
          },
        ];
      }
      return null;
    });
    final source = _smbSource();
    final provider = SmbFsProvider(
      source,
      password: 's3cret',
      chunkSize: 4,
    );

    final entries = await provider.list('');

    final call = calls.single;
    expect(call.method, 'list');
    final args = call.arguments as Map<Object?, Object?>;
    expect(args['host'], 'fileserver');
    expect(args['port'], 445);
    expect(args['share'], 'Music');
    expect(args['basePath'], 'Studio');
    expect(args['path'], 'Studio');
    expect(args['username'], r'WORKGROUP\media');
    expect(args['password'], 's3cret');
    expect(args['domain'], 'WORKGROUP');

    expect(entries.map((e) => e.name), ['Albums', 'song.mp3']);
    expect(entries.first.path, 'Albums');
    expect(entries.last.path, 'song.mp3');
    expect(entries.last.sizeBytes, 1234);
    expect(entries.last.modifiedAt, isNotNull);
  });

  test('a logon failure becomes RemoteAuthError', () async {
    install((call) async {
      throw PlatformException(code: 'AUTH_FAILED', message: 'Logon failure');
    });
    final provider = SmbFsProvider(_smbSource(), password: 'wrong');

    await expectLater(provider.list(''), throwsA(isA<RemoteAuthError>()));
  });

  test('stat returns null when the native side reports no object', () async {
    install((call) async => null);
    final provider = SmbFsProvider(_smbSource());

    expect(await provider.stat('missing.mp3'), isNull);
  });

  test('openRead requests sequential chunks with the right offsets', () async {
    final payload = List<int>.generate(10, (index) => index);
    install((call) async {
      if (call.method != 'openReadChunk') return null;
      final args = call.arguments as Map<Object?, Object?>;
      final offset = args['offset']! as int;
      final length = args['length']! as int;
      final end = (offset + length).clamp(0, payload.length);
      return Uint8List.fromList(payload.sublist(offset, end));
    });
    final provider = SmbFsProvider(_smbSource(), chunkSize: 4);

    final bytes =
        await provider.openRead('song.mp3').expand((chunk) => chunk).toList();

    expect(bytes, payload);
    final chunkCalls = calls
        .where((call) => call.method == 'openReadChunk')
        .map((call) => call.arguments as Map<Object?, Object?>)
        .toList();
    expect(chunkCalls.map((args) => args['offset']), [0, 4, 8]);
    expect(chunkCalls.every((args) => args['path'] == 'Studio/song.mp3'), isTrue);
  });

  test('openRead stops at end and never reads past it', () async {
    install((call) async {
      final args = call.arguments as Map<Object?, Object?>;
      final offset = args['offset']! as int;
      final length = args['length']! as int;
      return Uint8List.fromList(List<int>.generate(length, (i) => offset + i));
    });
    final provider = SmbFsProvider(_smbSource(), chunkSize: 8);

    final bytes =
        await provider.openRead('song.mp3', start: 2, end: 5).expand((c) => c).toList();

    expect(bytes, [2, 3, 4, 5]);
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['offset'], 2);
    expect(args['length'], 4);
  });

  test('SMB sources without a share are rejected before any channel call',
      () async {
    install((call) async => null);
    final provider = SmbFsProvider(_smbSource(root: '/'));

    await expectLater(
      provider.list(''),
      throwsA(isA<RemoteProtocolError>()),
    );
    expect(calls, isEmpty);
  });

  test('testConnection returns false instead of throwing', () async {
    install((call) async {
      throw PlatformException(code: 'UNAVAILABLE');
    });
    final provider = SmbFsProvider(_smbSource());

    expect(await provider.testConnection(), isFalse);
  });

  test('an unavailable channel maps to RemoteUnavailableError', () async {
    install((call) async {
      throw PlatformException(code: 'UNAVAILABLE', message: 'Host down');
    });
    final provider = SmbFsProvider(_smbSource());

    await expectLater(
      provider.list(''),
      throwsA(
        isA<RemoteUnavailableError>().having(
          (error) => error.userMessage,
          'userMessage',
          'Host down',
        ),
      ),
    );
  });

  test('testConnection asks for a probe and reports success', () async {
    install((call) async => true);
    final provider = SmbFsProvider(_smbSource());

    expect(await provider.testConnection(), isTrue);
    expect(calls.single.method, 'probe');
  });
}
