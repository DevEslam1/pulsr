// TagEditorScreen widget suite.
//
// Covers single and batch chrome, editing + undo, the auto-fetch no-match
// path and the empty-title save validation.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/metadata_search_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/tag_editor/tag_editor_screen.dart';
import 'package:pulsr/features/tag_editor/tag_field_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _Scanner extends Mock implements MediaScannerService {}

class _Metadata extends Mock implements MetadataSearchService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Scanner scanner;
  late _Metadata metadata;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final tagChannel = MethodChannel(PulsrChannels.tagEditor);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tagChannel, (call) async {
      if (call.method == 'readTags') return <String, dynamic>{};
      return true;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tagChannel, null);
    });
    scanner = _Scanner();
    metadata = _Metadata();
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
    useScreenSize(tester, const Size(800, 1600));
    await tester.pumpWidget(screenHarness(
        child: TagEditorScreen(song: song, batchSongs: batch)));
    await tester.pumpAndSettle();
  }

  testWidgets('single-track editor renders its fields and initial values',
      (tester) async {
    await pumpEditor(
      tester,
      song: createTestSong(
          id: 1, title: 'My Song', artist: 'My Artist', album: 'My Album'),
    );

    expect(find.text('Edit Audio Tags'), findsOneWidget);
    expect(find.byType(TagFieldWidget), findsWidgets);
    expect(find.widgetWithText(TextFormField, 'My Song'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'My Artist'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('editing a field enables Undo and Undo restores the value',
      (tester) async {
    await pumpEditor(tester, song: createTestSong(id: 1, title: 'Original'));

    IconButton undo() => tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.undo_rounded));
    expect(undo().onPressed, isNull);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Original'), 'Changed');
    await tester.pump();
    expect(undo().onPressed, isNotNull);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.undo_rounded));
    await tester.pump();
    expect(find.widgetWithText(TextFormField, 'Original'), findsOneWidget);
  });

  testWidgets('batch mode shows the banner and hides the title field',
      (tester) async {
    final a = createTestSong(id: 1, title: 'A', artist: 'X');
    final b = createTestSong(id: 2, title: 'B', artist: 'Y');
    await pumpEditor(tester, song: a, batch: [a, b]);

    expect(find.textContaining('Batch Edit'), findsOneWidget);
    expect(find.text('Title'), findsNothing);
    expect(find.byType(TagFieldWidget), findsWidgets);
  });

  testWidgets('auto-fetch with no online matches reports it',
      (tester) async {
    await pumpEditor(tester, song: createTestSong(id: 1, title: 'My Song'));

    await tester.tap(find.text('Auto-Fetch Tags & Cover Art'));
    await tester.pumpAndSettle();

    expect(find.text('No matching online metadata found.'), findsOneWidget);
  });

  testWidgets('saving with an empty title surfaces the validation error',
      (tester) async {
    await pumpEditor(tester, song: createTestSong(id: 1, title: 'My Song'));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'My Song'), '');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Song title cannot be empty.'), findsOneWidget);
  });
}
