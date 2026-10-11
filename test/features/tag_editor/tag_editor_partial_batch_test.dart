// TagEditorScreen: partial-batch failure reporting (must not be swallowed by
// the success path + pop) and the interrupted-batch retry action that re-runs
// the remaining files from the persisted checkpoint.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/metadata_search_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/tag_editor/tag_editor_cubit.dart';
import 'package:pulsr/features/tag_editor/tag_editor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _Scanner extends Mock implements MediaScannerService {}

class _Metadata extends Mock implements MetadataSearchService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Scanner scanner;
  late _Metadata metadata;
  final tagChannel = MethodChannel(PulsrChannels.tagEditor);

  void installChannel({String? failPathPart}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tagChannel, (call) async {
      if (call.method == 'readTags') return <String, dynamic>{};
      if (call.method == 'writeTags') {
        final path = (call.arguments as Map)['path'] as String;
        return failPathPart == null || !path.contains(failPathPart);
      }
      return true;
    });
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installChannel();
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tagChannel, null);
    });
    scanner = _Scanner();
    metadata = _Metadata();
    when(() => scanner.rescanSingleFile(any())).thenAnswer((_) async {});
    when(() => metadata.searchMetadata(
          title: any(named: 'title'),
          artist: any(named: 'artist'),
          album: any(named: 'album'),
        )).thenAnswer((_) async => <OnlineTrackMetadata>[]);
    getIt.registerSingleton<MediaScannerService>(scanner);
    getIt.registerSingleton<MetadataSearchService>(metadata);
    addTearDown(() async {
      await getIt.reset();
    });
  });

  Future<void> pumpEditor(WidgetTester tester,
      {required SongsTableData song, List<SongsTableData>? batch}) async {
    useScreenSize(tester, const Size(800, 1800));
    await tester.pumpWidget(
        screenHarness(child: TagEditorScreen(song: song, batchSongs: batch)));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'a partially failed batch shows the failure and does not pop the editor',
      (tester) async {
    installChannel(failPathPart: '/music/A.mp3');
    final a =
        createTestSong(id: 1, title: 'A', artist: 'X', path: '/music/A.mp3');
    final b =
        createTestSong(id: 2, title: 'B', artist: 'Y', path: '/music/B.mp3');
    await pumpEditor(tester, song: a, batch: [a, b]);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to tag 1 file'), findsOneWidget);
    expect(find.byType(TagEditorScreen), findsOneWidget,
        reason: 'the user must be able to retry the failed file');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a full batch failure still surfaces the failure and stays open',
      (tester) async {
    installChannel(failPathPart: '/music/');
    final a =
        createTestSong(id: 1, title: 'A', artist: 'X', path: '/music/A.mp3');
    final b =
        createTestSong(id: 2, title: 'B', artist: 'Y', path: '/music/B.mp3');
    await pumpEditor(tester, song: a, batch: [a, b]);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to tag 2 files'), findsOneWidget);
    expect(find.byType(TagEditorScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'the interrupted-batch dialog retries the remaining files and clears the checkpoint',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: const Value(7),
          title: 'A',
          artist: const Value('X'),
          path: '/music/A.mp3',
        ));
    getIt.registerSingleton<AppDatabase>(db);

    SharedPreferences.setMockInitialValues({
      TagEditorCubit.batchCheckpointKey: <String>['/music/A.mp3'],
    });

    await pumpEditor(tester, song: createTestSong(id: 1, title: 'Editor'));

    expect(find.text('Partial batch detected'), findsOneWidget);
    expect(find.text('Retry remaining 1 files'), findsOneWidget);

    await tester.tap(find.text('Retry remaining 1 files'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The save path waits on the artwork-cache eviction timeout, so give the
    // fake clock enough room for it to complete.
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(TagEditorCubit.batchCheckpointKey), isNull,
        reason: 'a successful retry clears the checkpoint');
    verify(() => scanner.rescanSingleFile('/music/A.mp3')).called(1);
    expect(find.text('Tags updated successfully'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
