// test/features/player/widgets/custody_certificate_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/chain_of_custody_service.dart';
import 'package:pulsr/core/utils/error_logger.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/custody_certificate_card.dart';

import 'player_sheet_test_support.dart';

class _MockChainOfCustodyService extends Mock
    implements ChainOfCustodyService {}

void main() {
  testWidgets(
      'P0-7: verifyChain failure resets _busy, re-enables verify button, and shows error',
      (tester) async {
    final recordedErrors = <Object>[];
    ErrorLogger.onCrashReported = (e, _, __) => recordedErrors.add(e);
    addTearDown(() => ErrorLogger.onCrashReported = null);

    final service = _MockChainOfCustodyService();
    when(
      () => service.verifyChain(
        trackId: any(named: 'trackId'),
        trackTitle: any(named: 'trackTitle'),
        filePath: any(named: 'filePath'),
        decoderCodec: any(named: 'decoderCodec'),
        sourceSampleRate: any(named: 'sourceSampleRate'),
        sourceBitDepth: any(named: 'sourceBitDepth'),
      ),
    ).thenThrow(StateError('native platform boom'));

    final cubit = stubPlayerCubit(
      state: PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
        ),
      ),
    );

    await tester.pumpWidget(
      sheetHost(
        playerCubit: cubit,
        child: CustodyCertificateCard(service: service),
      ),
    );

    final verifyButtonFinder = find.byType(IconButton);
    expect(tester.widget<IconButton>(verifyButtonFinder).onPressed, isNotNull);

    await tester.tap(verifyButtonFinder);
    await tester.pumpAndSettle();

    // Button must be re-enabled (_busy == false) and error displayed.
    final buttonAfter = tester.widget<IconButton>(verifyButtonFinder);
    expect(buttonAfter.onPressed, isNotNull);
    expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(recordedErrors, isNotEmpty);
  });

  testWidgets(
      'P0-7: shareCertificate failure resets _busy and surfaces error instead of escaping',
      (tester) async {
    final recordedErrors = <Object>[];
    ErrorLogger.onCrashReported = (e, _, __) => recordedErrors.add(e);
    addTearDown(() => ErrorLogger.onCrashReported = null);

    final service = _MockChainOfCustodyService();
    when(
      () => service.verifyChain(
        trackId: any(named: 'trackId'),
        trackTitle: any(named: 'trackTitle'),
        filePath: any(named: 'filePath'),
        decoderCodec: any(named: 'decoderCodec'),
        sourceSampleRate: any(named: 'sourceSampleRate'),
        sourceBitDepth: any(named: 'sourceBitDepth'),
      ),
    ).thenAnswer(
      (_) async => ChainOfCustodyReport(
        trackId: '42',
        trackTitle: 'Test Song — Test Artist',
        contentSha256: 'abc',
        sourceIdentitySha256: 'def',
        fileSizeBytes: 123,
        fileModifiedMs: 0,
        decoderCodec: 'FLAC',
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        bufferSize: 2048,
        activeDspStages: const [],
        isBitPerfectActive: false,
        isBypassCompareActive: false,
        rollingRtf: 0.1,
        estimatedLatencyMs: 20,
        thermalStatus: 0,
        measurement: null,
        limitations: const [],
        verifiedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    final cubit = stubPlayerCubit(
      state: PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
        ),
      ),
    );

    await tester.pumpWidget(
      sheetHost(
        playerCubit: cubit,
        child: CustodyCertificateCard(
          service: service,
          getTempDirectory: () async =>
              throw StateError('temp directory unavailable'),
        ),
      ),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    // Tapping Share when export directory lookup throws must reset _busy and surface error.
    final shareFinder = find.byType(TextButton);
    expect(shareFinder, findsOneWidget);
    await tester.tap(shareFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNotNull);
    expect(tester.widget<TextButton>(shareFinder).onPressed, isNotNull);
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(recordedErrors, isNotEmpty);
  });
}
