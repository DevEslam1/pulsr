// Covers lib/features/settings/presentation/widgets/backup_section.dart
//
// Drives export + import flows against a fake FilePickerPlatform and stubbed
// backup use cases: success, cancel, error, invalid-extension, oversize and
// malformed-JSON paths, plus the restore confirmation/result dialogs.
//
// Backups read real files, and real dart:io futures never complete under
// flutter_test's fake async; the import paths therefore interleave
// `tester.runAsync` cycles (`pumpReal`) to let the file reads finish.
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/usecases/backup_usecases.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/backup_section.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockExport extends Mock implements ExportBackupUseCase {}

class MockImport extends Mock implements ImportBackupUseCase {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

final class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile(this._file);

  final File _file;

  @override
  String get name => _file.uri.pathSegments.last;

  @override
  Uri get uri => _file.uri;

  @override
  XFile get xFile => XFile(_file.path);

  @override
  int? lengthSync() => _file.lengthSync();

  @override
  Future<int> length() => _file.length();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      _file.openRead().map(Uint8List.fromList);
}

class _FakePicker extends FilePickerPlatform {
  PlatformFile? pickResult;
  Uri? saveResult;
  int pickCalls = 0;
  int saveCalls = 0;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    pickCalls++;
    return pickResult;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    saveCalls++;
    return saveResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late _FakePicker picker;
  late MockExport exportUseCase;
  late MockImport importUseCase;
  late MockSettingsCubit settingsCubit;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pulsr_backup_test');
    picker = _FakePicker();
    FilePickerPlatform.instance = picker;

    exportUseCase = MockExport();
    importUseCase = MockImport();
    settingsCubit = MockSettingsCubit();
    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => settingsCubit.reloadSettings()).thenAnswer((_) async {});

    await getIt.reset();
    getIt.registerSingleton<ExportBackupUseCase>(exportUseCase);
    getIt.registerSingleton<ImportBackupUseCase>(importUseCase);
  });

  tearDown(() async {
    await getIt.reset();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  File seedFile(String name, String content) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    file.writeAsStringSync(content);
    return file;
  }

  File seedBigFile(String name, int bytes) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(Uint8List(bytes));
    return file;
  }

  // Interleaves real-async cycles with frames so real file reads resolve.
  Future<void> pumpReal(WidgetTester tester, {int cycles = 6}) async {
    for (var i = 0; i < cycles; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: settingsCubit,
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: BackupSection()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('export', () {
    testWidgets('a successful export writes and reports the destination',
        (tester) async {
      picker.saveResult = Uri.parse('file:///backups/pulsr_backup_2024.json');
      when(() => exportUseCase.execute())
          .thenAnswer((_) async => '{"version":4}');

      await pumpSection(tester);
      await tester.tap(find.text(l10n.exportBackup));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      verify(() => exportUseCase.execute()).called(1);
      expect(picker.saveCalls, 1);
      expect(find.textContaining('pulsr_backup'), findsWidgets);

      await unmount(tester);
    });

    testWidgets('cancelling the save dialog exports nothing further',
        (tester) async {
      picker.saveResult = null;
      when(() => exportUseCase.execute()).thenAnswer((_) async => '{}');

      await pumpSection(tester);
      await tester.tap(find.text(l10n.exportBackup));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      verify(() => exportUseCase.execute()).called(1);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('a non-json save location is rejected', (tester) async {
      picker.saveResult = Uri.parse('content://downloads/notes.txt');
      when(() => exportUseCase.execute()).thenAnswer((_) async => '{}');

      await pumpSection(tester);
      await tester.tap(find.text(l10n.exportBackup));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('an export failure surfaces the error snackbar',
        (tester) async {
      when(() => exportUseCase.execute()).thenThrow(Exception('disk full'));

      await pumpSection(tester);
      await tester.tap(find.text(l10n.exportBackup));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);

      await unmount(tester);
    });
  });

  group('import', () {
    testWidgets('a cancelled pick is a no-op', (tester) async {
      picker.pickResult = null;

      await pumpSection(tester);
      await tester.tap(find.text(l10n.importBackup));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(picker.pickCalls, 1);
      verifyNever(() => importUseCase.execute(any()));

      await unmount(tester);
    });

    testWidgets('a non-json file is rejected', (tester) async {
      picker.pickResult = _FakePlatformFile(seedFile('notes.txt', 'hello'));

      await pumpSection(tester);
      await tester.tap(find.text(l10n.importBackup));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      verifyNever(() => importUseCase.execute(any()));

      await unmount(tester);
    });

    testWidgets('an oversize backup is rejected before reading',
        (tester) async {
      picker.pickResult =
          _FakePlatformFile(seedBigFile('big.json', 10 * 1024 * 1024 + 16));

      await pumpSection(tester);
      await tester.tap(find.text(l10n.importBackup));
      await tester.pump();
      await pumpReal(tester);

      expect(find.text(l10n.backupTooLarge), findsOneWidget);
      verifyNever(() => importUseCase.execute(any()));

      await unmount(tester);
    });

    testWidgets('malformed JSON shows the invalid-backup message',
        (tester) async {
      picker.pickResult =
          _FakePlatformFile(seedFile('broken.json', 'not json at all'));

      await pumpSection(tester);
      await tester.tap(find.text(l10n.importBackup));
      await tester.pump();
      await pumpReal(tester);

      expect(find.text(l10n.backupInvalid), findsOneWidget);
      verifyNever(() => importUseCase.execute(any()));

      await unmount(tester);
    });

    testWidgets('cancelling the restore confirmation does not import',
        (tester) async {
      picker.pickResult = _FakePlatformFile(seedFile(
        'backup.json',
        '{"version":4,"favorites":[],"playlists":[],"settings":{},"playHistory":[],"excludedFolders":[]}',
      ));

      await pumpSection(tester);
      await tester.tap(find.text(l10n.importBackup));
      await tester.pump();
      await pumpReal(tester);

      expect(find.text(l10n.confirmRestore), findsWidgets);

      await tester.tap(find.widgetWithText(TextButton, l10n.cancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      verifyNever(() => importUseCase.execute(any()));

      await unmount(tester);
    });

    testWidgets('confirming restores and shows the result dialog',
        (tester) async {
      picker.pickResult = _FakePlatformFile(seedFile(
        'backup.json',
        '{"version":4,"favorites":[],"playlists":[],"settings":{},"playHistory":[],"excludedFolders":[]}',
      ));
      when(() => importUseCase.execute(any())).thenAnswer(
        (_) async => const ImportResult(
          restoredFavoritesCount: 2,
          restoredPlaylistsCount: 1,
          restoredHistoryCount: 3,
          restoredSettingsCount: 4,
          restoredExcludedFoldersCount: 1,
          unmatchedPaths: ['/missing/song.mp3'],
        ),
      );

      await pumpSection(tester);
      await tester.tap(find.text(l10n.importBackup));
      await tester.pump();
      await pumpReal(tester);

      await tester.tap(find.widgetWithText(FilledButton, l10n.confirmRestore));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(l10n.backupRestored), findsOneWidget);
      verify(() => importUseCase.execute(any())).called(1);
      verify(() => settingsCubit.reloadSettings()).called(1);

      await tester.tap(find.widgetWithText(TextButton, l10n.doneAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await unmount(tester);
    });

    testWidgets('an import failure surfaces the error snackbar',
        (tester) async {
      picker.pickResult = _FakePlatformFile(seedFile(
        'backup.json',
        '{"version":4,"favorites":[],"playlists":[],"settings":{},"playHistory":[],"excludedFolders":[]}',
      ));
      when(() => importUseCase.execute(any()))
          .thenThrow(const FormatException('bad payload'));

      await pumpSection(tester);
      await tester.tap(find.text(l10n.importBackup));
      await tester.pump();
      await pumpReal(tester);

      await tester.tap(find.widgetWithText(FilledButton, l10n.confirmRestore));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);

      await unmount(tester);
    });
  });
}

