import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/hidden_folders_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockFolderUseCases extends Mock implements FolderUseCases {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

class MockLibraryCubit extends Mock implements LibraryCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFolderUseCases mockFolderUseCases;
  late MockSettingsCubit mockSettingsCubit;
  late MockLibraryCubit mockLibraryCubit;

  final initialFolders = [
    const FolderItem(
      path: '/music/rock',
      name: 'rock',
      songCount: 12,
      isExcluded: false,
    ),
  ];

  final toggledFolders = [
    const FolderItem(
      path: '/music/rock',
      name: 'rock',
      songCount: 12,
      isExcluded: true,
    ),
  ];

  setUp(() {
    mockFolderUseCases = MockFolderUseCases();
    mockSettingsCubit = MockSettingsCubit();
    mockLibraryCubit = MockLibraryCubit();

    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockSettingsCubit.getMinFileSizeKb()).thenAnswer((_) async => 0);
    when(() => mockSettingsCubit.rescanLibrary()).thenAnswer((_) async => 0);

    when(() => mockLibraryCubit.state).thenReturn(const LibraryState());
    when(() => mockLibraryCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => mockLibraryCubit.loadFolders()).thenAnswer((_) async {});
  });

  testWidgets(
      '[H-20] _toggleFolder updates folder exclusion without full-screen loading flicker',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    var callCount = 0;
    when(() => mockFolderUseCases.getFolderHierarchy()).thenAnswer((_) async {
      callCount++;
      return Right(callCount == 1 ? initialFolders : toggledFolders);
    });
    when(() => mockFolderUseCases.toggleExcludeFolder(any()))
        .thenAnswer((_) async => const Right(null));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
          BlocProvider<LibraryCubit>.value(value: mockLibraryCubit),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HiddenFoldersScreen(folderUseCases: mockFolderUseCases),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify folder is shown unhidden
    expect(find.text('rock'), findsOneWidget);
    final hideBtn = find.text('Hide');
    expect(hideBtn, findsOneWidget);

    // Tap hide
    await tester.tap(hideBtn);

    // Pump one frame: CircularProgressIndicator should NOT replace the list (no flicker)
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Finish async call
    await tester.pumpAndSettle();

    // Verify toggled state is rendered
    expect(find.text('Unhide'), findsOneWidget);
    verify(() => mockFolderUseCases.toggleExcludeFolder('/music/rock'))
        .called(1);
    verify(() => mockLibraryCubit.loadFolders()).called(1);
  });

  testWidgets('[M-28] _searchDebounce timer is cancelled on dispose',
      (tester) async {
    when(() => mockFolderUseCases.getFolderHierarchy())
        .thenAnswer((_) async => Right(initialFolders));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
          BlocProvider<LibraryCubit>.value(value: mockLibraryCubit),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HiddenFoldersScreen(folderUseCases: mockFolderUseCases),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Enter search text to start debounce timer
    await tester.enterText(find.byType(TextField), 'rock');
    await tester.pump();

    final state = tester
        .state<HiddenFoldersScreenState>(find.byType(HiddenFoldersScreen));
    expect(state.searchDebounce?.isActive, isTrue);

    // Unmount widget (simulate navigating away / dispose)
    await tester.pumpWidget(const SizedBox.shrink());

    // Timer should be cancelled and null
    expect(state.searchDebounce, isNull);
  });
}
