// test/features/player/abx_screen_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/abx_report_export.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/utils/error_logger.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/domain/models/abx_session.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/abx_screen.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:share_plus/share_plus.dart';

import 'player_test_support.dart';
import 'widgets/player_sheet_test_support.dart'
    show MockPlayerCubit, testSong, stubPlayerCubit;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late Directory tempDir;
  late Directory saveDir;
  late RecordingAudioHandler handler;
  late MockPlayerCubit playerCubit;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_abx_tmp_');
    saveDir = await Directory.systemTemp.createTemp('pulsr_abx_save_');
    handler = RecordingAudioHandler();
    if (getIt.isRegistered<PulsrAudioHandler>()) {
      await getIt.unregister<PulsrAudioHandler>();
    }
    getIt.registerSingleton<PulsrAudioHandler>(handler);

    playerCubit = stubPlayerCubit(
      state: PlayerState(
        playback: const PlaybackSlice(currentSong: testSong, isPlaying: true),
        dsp: const DspSlice(isEqEnabled: true),
      ),
    );
  });

  tearDown(() async {
    if (getIt.isRegistered<PulsrAudioHandler>()) {
      await getIt.unregister<PulsrAudioHandler>();
    }
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    if (saveDir.existsSync()) await saveDir.delete(recursive: true);
  });

  const dacOutput = AudioOutputInfo(
    deviceName: 'Chord Mojo 2',
    isUsbDac: true,
    sampleRate: 96000,
    pcmEncoding: 22,
    bitDepth: 24,
    isBitPerfectActive: false,
    isBitPerfectSupported: true,
    activeDeviceType: 'usb',
  );

  Widget buildHarness({
    required AbxSession Function(int trials) sessionFactory,
    Future<Directory> Function()? getTempDirectory,
    Future<Directory> Function()? getSaveDirectory,
    Future<ShareResult> Function(AbxReportArtifact artifact)? shareReport,
    Future<void> Function(AbxReportArtifact artifact)? onReportSaved,
  }) {
    return BlocProvider<PlayerCubit>.value(
      value: playerCubit,
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AbxScreen(
          trials: 10,
          sessionFactory: sessionFactory,
          getTempDirectory: getTempDirectory ?? () async => tempDir,
          getSaveDirectory: getSaveDirectory ?? () async => saveDir,
          shareReport: shareReport,
          onReportSaved: onReportSaved,
          outputInfoProvider: () => dacOutput,
        ),
      ),
    );
  }

  Future<void> completeSession(
    WidgetTester tester, {
    required List<AbxStimulus> capturedPlan,
  }) async {
    await tester.tap(find.text(l10n.abxStart));
    await tester.pumpAndSettle();

    for (var i = 0; i < capturedPlan.length; i++) {
      final answerText = capturedPlan[i] == AbxStimulus.a
          ? l10n.abxAnswerA
          : l10n.abxAnswerB;
      await tester.tap(find.text(answerText));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
      'completed ABX session exposes Share and Save actions that export structured JSON',
      (tester) async {
    late AbxSession createdSession;
    final sharedArtifacts = <AbxReportArtifact>[];
    final savedArtifacts = <AbxReportArtifact>[];
    final shareDone = Completer<void>();
    final saveDone = Completer<void>();

    await tester.pumpWidget(
      buildHarness(
        sessionFactory: (trials) {
          createdSession = AbxSession(trials: trials, seed: 11);
          return createdSession;
        },
        shareReport: (artifact) async {
          sharedArtifacts.add(artifact);
          if (!shareDone.isCompleted) shareDone.complete();
          return const ShareResult('ok', ShareResultStatus.success);
        },
        onReportSaved: (artifact) async {
          savedArtifacts.add(artifact);
          if (!saveDone.isCompleted) saveDone.complete();
        },
      ),
    );
    await tester.pumpAndSettle();

    // Before completion, share/save actions are not shown.
    expect(find.text(l10n.share), findsNothing);
    expect(find.text(l10n.save), findsNothing);

    final plan = createdSession.trials.map((t) => t.hiddenX).toList();
    await completeSession(tester, capturedPlan: plan);

    expect(find.text('10 / 10'), findsOneWidget);
    expect(find.text(l10n.share), findsOneWidget);
    expect(find.text(l10n.save), findsOneWidget);

    await tester.tap(find.text(l10n.share));
    final shareDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (!shareDone.isCompleted && DateTime.now().isBefore(shareDeadline)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(sharedArtifacts, hasLength(1));
    final sharedJson =
        jsonDecode(sharedArtifacts.single.jsonText) as Map<String, dynamic>;
    expect(sharedJson['kind'], 'abx_report');
    expect(sharedJson['totalTrials'], 10);
    expect(sharedJson['correctCount'], 10);
    expect(sharedJson['pValue'], closeTo(1 / 1024, 1e-12));
    expect(sharedJson['verdict'], AbxSession.strongKey);
    expect(sharedJson['sampleRate'], 96000);
    expect(sharedJson['codec'], 'FLAC');
    expect(
      (sharedJson['outputDevice'] as Map<String, dynamic>)['name'],
      'Chord Mojo 2',
    );
    expect((sharedJson['trials'] as List<dynamic>), hasLength(10));

    await tester.tap(find.text(l10n.save));
    final saveDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (!saveDone.isCompleted && DateTime.now().isBefore(saveDeadline)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(savedArtifacts, hasLength(1));
    final savedArtifact = savedArtifacts.single;
    expect(savedArtifact.file.existsSync(), isTrue);
    final savedJson =
        jsonDecode(savedArtifact.jsonText) as Map<String, dynamic>;
    expect(savedJson['verdict'], AbxSession.strongKey);
    expect(find.textContaining('pulsr-abx-report-'), findsOneWidget);
  });

  testWidgets('export failure logs error and surfaces exportFailed feedback',
      (tester) async {
    final logged = <Object>[];
    ErrorLogger.onCrashReported = (e, _, __) => logged.add(e);
    addTearDown(() => ErrorLogger.onCrashReported = null);

    late AbxSession createdSession;
    await tester.pumpWidget(
      buildHarness(
        sessionFactory: (trials) {
          createdSession = AbxSession(trials: trials, seed: 3);
          return createdSession;
        },
        getSaveDirectory: () async => throw FileSystemException('disk full'),
      ),
    );
    await tester.pumpAndSettle();

    final plan = createdSession.trials.map((t) => t.hiddenX).toList();
    await completeSession(tester, capturedPlan: plan);

    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();

    expect(find.text(l10n.exportFailed), findsOneWidget);
    expect(logged, isNotEmpty);
    expect(
      tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, l10n.save),
      ).onPressed,
      isNotNull,
    );
  });
}
