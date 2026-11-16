// P0-1 remote sources: FTP reply/listing parsing and a loopback FTP session.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/interfaces/remote_fs_provider.dart';
import 'package:pulsr/domain/models/remote_source.dart';
import 'package:pulsr/features/remote_sources/ftp_fs_provider.dart';
import 'package:pulsr/features/remote_sources/ftp_protocol.dart';

const String _unixListing = 'drwxr-xr-x    2 ftp      ftp          4096 Jan 02 03:04 Albums\r\n'
    '-rw-r--r--    1 ftp      ftp             4 Jan 02 03:04 song.mp3\r\n';

/// A deliberately tiny FTP server: enough of RFC 959/2428 to exercise the
/// client's command sequencing, passive mode, REST offset and error mapping.
class _FakeFtpServer {
  _FakeFtpServer({
    this.password = 'secret',
    this.useEpsv = false,
    this.rejectRest = false,
    this.listing = _unixListing,
    this.fileContent = const [97, 98, 99, 100],
  });

  final String password;
  final bool useEpsv;
  final bool rejectRest;
  final String listing;
  final List<int> fileContent;

  final List<String> commands = <String>[];
  final List<Socket> _sockets = <Socket>[];
  final List<ServerSocket> _passiveServers = <ServerSocket>[];
  ServerSocket? _control;
  Completer<Socket>? _pendingData;
  int? _restOffset;
  String _pending = '';

  int get port => _control!.port;

  Future<void> start() async {
    _control = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _control!.listen((socket) {
      _sockets.add(socket);
      _pending = '';
      socket.write('220-Welcome to the fake FTP\r\n220-ready\r\n');
      socket.write('220 Ready\r\n');
      socket.listen((data) {
        _pending += utf8.decode(data, allowMalformed: true);
        while (true) {
          final index = _pending.indexOf('\r\n');
          if (index == -1) break;
          final line = _pending.substring(0, index);
          _pending = _pending.substring(index + 2);
          _handle(line, socket);
        }
      }, onError: (Object _) {});
    });
  }

  Future<void> stop() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _control?.close();
    for (final server in _passiveServers) {
      await server.close();
    }
  }

  Future<void> _handle(String line, Socket socket) async {
    final space = line.indexOf(' ');
    final verb = (space == -1 ? line : line.substring(0, space)).toUpperCase();
    final argument = space == -1 ? '' : line.substring(space + 1);
    commands.add(verb);
    switch (verb) {
      case 'USER':
        _reply(socket, '331 Password required');
      case 'PASS':
        _reply(socket, argument == password ? '230 Logged in' : '530 Denied');
      case 'TYPE':
        _reply(socket, '200 Type set to I');
      case 'PWD':
        _reply(socket, '257 "/music" is the current directory');
      case 'CWD':
        _reply(socket, '250 Directory changed');
      case 'EPSV':
        if (!useEpsv) {
          _reply(socket, '500 EPSV not understood');
        } else {
          final port = await _openPassiveServer();
          _reply(socket, '229 Entering Extended Passive Mode (|||$port|)');
        }
      case 'PASV':
        final port = await _openPassiveServer();
        _reply(
          socket,
          '227 Entering Passive Mode (127,0,0,1,${port ~/ 256},${port % 256})',
        );
      case 'LIST':
        _reply(socket, '150 Here comes the directory listing');
        await _writeData(utf8.encode(listing));
        _reply(socket, '226 Transfer complete');
      case 'NLST':
        _reply(socket, '150 Here comes the directory listing');
        await _writeData(utf8.encode('Albums\r\nsong.mp3\r\n'));
        _reply(socket, '226 Transfer complete');
      case 'SIZE':
        _reply(
          socket,
          argument.contains('Albums') ? '550 Not a plain file' : '213 4',
        );
      case 'MDTM':
        _reply(socket, '213 20240102030405');
      case 'REST':
        if (rejectRest) {
          _reply(socket, '502 REST not implemented');
        } else {
          _restOffset = int.tryParse(argument);
          _reply(socket, '350 Restarting at $argument');
        }
      case 'RETR':
        final offset = _restOffset ?? 0;
        _restOffset = null;
        _reply(socket, '150 Opening BINARY mode data connection');
        final body = offset >= fileContent.length
            ? const <int>[]
            : fileContent.sublist(offset);
        await _writeData(body);
        _reply(socket, '226 Transfer complete');
      case 'NOOP':
        _reply(socket, '200 NOOP ok');
      case 'QUIT':
        _reply(socket, '221 Bye');
      default:
        _reply(socket, '500 Unknown command');
    }
  }

  Future<int> _openPassiveServer() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _passiveServers.add(server);
    final completer = Completer<Socket>();
    _pendingData = completer;
    server.listen((socket) {
      _sockets.add(socket);
      if (!completer.isCompleted) completer.complete(socket);
    });
    return server.port;
  }

  Future<void> _writeData(List<int> bytes) async {
    final completer = _pendingData;
    if (completer == null) return;
    final socket = await completer.future;
    socket.add(bytes);
    await socket.flush();
    await socket.close();
    _pendingData = null;
  }

  void _reply(Socket socket, String line) {
    socket.write('$line\r\n');
  }
}

RemoteSource _ftpSource(int port) {
  return RemoteSource.create(
    kind: RemoteSourceKind.ftp,
    displayName: 'Fake FTP',
    host: '127.0.0.1',
    port: port,
    rootPath: '/music',
    username: 'media',
  );
}

void main() {
  group('FtpReply', () {
    test('reads a multiline reply as one reply', () async {
      final lines = <String>['220-Welcome', '220-second line', '220 Ready'];
      var index = 0;

      final reply = await FtpReply.readReply(() async {
        if (index >= lines.length) return null;
        return lines[index++];
      });

      expect(reply.code, 220);
      expect(reply.lines, hasLength(3));
      expect(reply.message, 'Ready');
      expect(reply.isSuccess, isTrue);
    });

    test('reads a single-line reply', () async {
      var index = 0;
      final lines = ['331 Password required'];

      final reply = await FtpReply.readReply(() async {
        if (index >= lines.length) return null;
        return lines[index++];
      });

      expect(reply.code, 331);
      expect(reply.message, 'Password required');
      expect(reply.needsMoreInput, isTrue);
    });

    test('throws when the server closes mid-reply', () async {
      var index = 0;
      final lines = <String>['220-Welcome'];

      await expectLater(
        FtpReply.readReply(() async {
          if (index >= lines.length) return null;
          return lines[index++];
        }),
        throwsA(isA<FtpClosedError>()),
      );
    });

    test('rejects a line that is not a reply', () async {
      await expectLater(
        FtpReply.readReply(() async => 'hello'),
        throwsA(isA<FtpFormatError>()),
      );
    });
  });

  group('FtpListingParser', () {
    test('parses UNIX listings with and without a group column', () {
      final withGroup = FtpListingParser.parseLine(
        '-rw-r--r--    1 ftp      ftp             4 Jan 02 03:04 song.mp3',
        parentPath: 'Music',
        now: DateTime(2024, 1, 10),
      );
      final withoutGroup = FtpListingParser.parseLine(
        '-rw-r--r--   1 ftp   1024 Dec 31  2023 old.flac',
        parentPath: 'Music',
        now: DateTime(2024, 1, 10),
      );

      expect(withGroup?.name, 'song.mp3');
      expect(withGroup?.path, 'Music/song.mp3');
      expect(withGroup?.sizeBytes, 4);
      expect(withGroup?.isDirectory, isFalse);
      expect(withGroup?.modifiedAt, DateTime(2024, 1, 2, 3, 4));

      expect(withoutGroup?.name, 'old.flac');
      expect(withoutGroup?.sizeBytes, 1024);
      expect(withoutGroup?.modifiedAt, DateTime(2023, 12, 31));
    });

    test('a time later than "now" rolls back a year', () {
      final entry = FtpListingParser.parseLine(
        '-rw-r--r--    1 ftp      ftp             4 Dec 31 23:30 song.mp3',
        parentPath: '',
        now: DateTime(2024, 1, 2, 10),
      );

      expect(entry?.modifiedAt?.year, 2023);
    });

    test('marks directories and strips symlink targets', () {
      final directory = FtpListingParser.parseLine(
        'drwxr-xr-x    2 ftp      ftp          4096 Jan 02 03:04 Albums',
        parentPath: '',
        now: DateTime(2024, 1, 10),
      );
      final link = FtpListingParser.parseLine(
        'lrwxrwxrwx    1 ftp      ftp             8 Jan 02 03:04 latest -> 2024',
        parentPath: '',
        now: DateTime(2024, 1, 10),
      );

      expect(directory?.isDirectory, isTrue);
      expect(directory?.sizeBytes, isNull);
      expect(link?.name, 'latest');
      expect(link?.isDirectory, isFalse);
    });

    test('parses DOS listings with <DIR> and 12-hour times', () {
      final directory = FtpListingParser.parseLine(
        '01-02-24  03:04PM       <DIR>          Albums',
        parentPath: 'music',
        now: DateTime(2024, 1, 10),
      );
      final file = FtpListingParser.parseLine(
        '12-31-2023  11:30AM                 1024 song.mp3',
        parentPath: 'music',
        now: DateTime(2024, 1, 10),
      );

      expect(directory?.isDirectory, isTrue);
      expect(directory?.path, 'music/Albums');
      expect(directory?.modifiedAt, DateTime(2024, 1, 2, 15, 4));

      expect(file?.isDirectory, isFalse);
      expect(file?.sizeBytes, 1024);
      expect(file?.modifiedAt, DateTime(2023, 12, 31, 11, 30));
    });

    test('ignores headers, blank lines and dot entries', () {
      expect(
        FtpListingParser.parseLine('total 12', parentPath: ''),
        isNull,
      );
      expect(FtpListingParser.parseLine('   ', parentPath: ''), isNull);
      expect(
        FtpListingParser.parseLine(
          'drwxr-xr-x    2 ftp      ftp          4096 Jan 02 03:04 ..',
          parentPath: '',
        ),
        isNull,
      );
    });

    test('sorts a whole payload with folders first', () {
      final entries = FtpListingParser.parseListing(
        _unixListing,
        parentPath: '',
        now: DateTime(2024, 1, 10),
      );

      expect(entries.map((e) => e.name), ['Albums', 'song.mp3']);
    });

    test('turns NLST names into entries, dropping duplicates', () {
      final entries = FtpListingParser.parseNameList(
        '/music/Albums\r\nsong.mp3\r\nsong.mp3\r\n..\r\n',
        parentPath: '',
      );

      expect(entries.map((e) => e.name), ['Albums', 'song.mp3']);
      expect(entries.every((e) => e.isDirectory == false), isTrue);
    });

    test('parses PASV and EPSV answers', () {
      final passive =
          FtpListingParser.parsePassiveReply('Entering Passive Mode (10,0,0,5,4,1)');
      expect(passive?.host, '10.0.0.5');
      expect(passive?.port, 4 * 256 + 1);
      expect(FtpListingParser.parsePassiveReply('nonsense'), isNull);

      expect(
        FtpListingParser.parseExtendedPassiveReply(
          'Entering Extended Passive Mode (|||6446|)',
        ),
        6446,
      );
      expect(
        FtpListingParser.parseExtendedPassiveReply('Entering Extended Mode'),
        isNull,
      );
    });

    test('parses MDTM timestamps and rejects impossible ones', () {
      expect(
        FtpListingParser.parseModifiedTime('20240102030405'),
        DateTime.utc(2024, 1, 2, 3, 4, 5),
      );
      expect(FtpListingParser.parseModifiedTime('not-a-date'), isNull);
      expect(FtpListingParser.parseModifiedTime('20241302030405'), isNull);
    });
  });

  group('FtpFsProvider against a loopback server', () {
    late _FakeFtpServer server;
    late FtpFsProvider provider;

    Future<void> start(_FakeFtpServer candidate, {String? password}) async {
      server = candidate;
      await server.start();
      provider = FtpFsProvider(
        _ftpSource(server.port),
        password: password ?? candidate.password,
      );
    }

    tearDown(() async {
      await provider.close();
      await server.stop();
    });

    test('logs in, sets binary mode and lists the root', () async {
      await start(_FakeFtpServer());

      final entries = await provider.list('');

      expect(server.commands, containsAll(<String>['USER', 'PASS', 'TYPE', 'PASV', 'LIST']));
      expect(entries.map((e) => e.name), ['Albums', 'song.mp3']);
      expect(entries.first.isDirectory, isTrue);
      expect(entries.last.sizeBytes, 4);
    });

    test('uses EPSV when the server advertises it', () async {
      await start(_FakeFtpServer(useEpsv: true));

      final entries = await provider.list('');

      expect(server.commands, contains('EPSV'));
      expect(server.commands, isNot(contains('PASV')));
      expect(entries, hasLength(2));
    });

    test('stat reports size for a file and CWD-probes a directory', () async {
      await start(_FakeFtpServer());

      final file = await provider.stat('song.mp3');
      final directory = await provider.stat('Albums');

      expect(file?.isDirectory, isFalse);
      expect(file?.sizeBytes, 4);
      expect(file?.modifiedAt, DateTime.utc(2024, 1, 2, 3, 4, 5));
      expect(directory?.isDirectory, isTrue);
      expect(server.commands, contains('CWD'));
    });

    test('openRead resumes with REST and stops at the requested end', () async {
      await start(_FakeFtpServer());

      final bytes = await provider
          .openRead('song.mp3', start: 2, end: 3)
          .expand((chunk) => chunk)
          .toList();

      expect(server.commands, contains('REST'));
      expect(bytes, [99, 100]);
    });

    test('falls back to skipping bytes when REST is rejected', () async {
      await start(_FakeFtpServer(rejectRest: true));

      final bytes = await provider
          .openRead('song.mp3', start: 2)
          .expand((chunk) => chunk)
          .toList();

      expect(server.commands, contains('REST'));
      expect(bytes, [99, 100]);
    });

    test('a rejected password becomes RemoteAuthError', () async {
      await start(_FakeFtpServer(), password: 'wrong');

      await expectLater(provider.list(''), throwsA(isA<RemoteAuthError>()));
    });

    test('testConnection reports true for a working session', () async {
      await start(_FakeFtpServer());

      expect(await provider.testConnection(), isTrue);
    });

    test('close sends QUIT', () async {
      await start(_FakeFtpServer());
      await provider.list('');

      await provider.close();

      expect(server.commands, contains('QUIT'));
    });
  });
}
