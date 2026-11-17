// Regression test for P1-2.3: a wedged recommendation request must time out and
// clear the in-flight flag, otherwise autoplay stays dead for the session.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/features/player/cubit/controllers/player_queue_controller.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

import '../../../helpers/test_pulsr_audio_handler.dart';
import '../player_test_support.dart';

class _MockYtmService extends Mock implements YtmService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockYtmService ytm;
  late PlayerQueueController controller;
  late PlayerState state;

  setUp(() {
    ytm = _MockYtmService();
    state = const PlayerState();

    controller = PlayerQueueController(
      audioHandler: TestPulsrAudioHandler(),
      repository: MockMusicRepository(),
      getState: () => state,
      emit: (next) => state = next,
      isClosed: () => false,
      queueMutex: Mutex(),
      slotLookupCache: <int, SongsTableData>{},
      queueSlots: {},
      updateWidgetThrottled: ({bool force = false}) {},
      loadLyrics: (_) {},
      bumpQueueVersion: () {},
      isSameTrack: (a, b) => a?.id == b?.id,
      ytmService: ytm,
      autoplayFetchTimeout: const Duration(milliseconds: 20),
    );
  });

  test('a never-answering fetch times out and frees the next attempt',
      () async {
    var calls = 0;
    final wedged = Completer<List<YtmTrack>>();
    when(() => ytm.getRadioTracks('vedged', limit: any(named: 'limit')))
        .thenAnswer((_) {
      calls += 1;
      return wedged.future;
    });

    final first = controller.fetchAndEnqueueAutoplay('vedged');
    expect(controller.isAutoplayFetchInFlight, isTrue);

    await first.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.isAutoplayFetchInFlight, isFalse,
        reason: 'the timeout must clear the guard so autoplay can retry');

    // A later trigger actually reaches the service again.
    final second = controller.fetchAndEnqueueAutoplay('vedged');
    await second.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(calls, 2);
    expect(controller.isAutoplayFetchInFlight, isFalse);
  });
}
