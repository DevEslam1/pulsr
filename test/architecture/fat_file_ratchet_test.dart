// Decomposition ratchet (gaps 01-4, 11-5, 20-3): the six oversized files
// hold the app's core and hide defects. Splitting them is L effort; this
// test ratchets their byte sizes so they can only shrink. Lower a cap when
// you extract a collaborator, never raise one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('oversized core files do not grow (01-4)', () {
    // Caps lowered after tranches 9-10 extractions:
    //   audio_handler.dart     -507B  (AudioHandlerLifecycleObserver)
    //   player_cubit.dart      -3291B (QuranRestoreSnapshot)
    //   equalizer_manager.dart -464B  (EqFrequencyValidation)
    //   library_screen.dart    -2228B (CategoryCard)
    //   settings_cubit.dart    -472B  (ProxyEndpointValidator)
    // Caps lowered after EQ/Auto tranche:
    //   equalizer_manager.dart -5121B (EqualizerPresetOps part: preset slots,
    //     JSON import/export, A/B comparison, custom frequency layouts)
    // Caps lowered after the download-cycle tranche:
    //   yt_download_service.dart -773B (foreground controller, pause registry,
    //     HTTP response/IO support)
    //   ytm_service.dart -291B (YtmMediaHelpers: artwork/playability parsing)
    // Caps lowered after the cookie/search decomposition tranche:
    //   ytm_account_service.dart -6167B (YtmCookieCodec: cookie header folding,
    //     YouTube scoping, Set-Cookie split/merge, session-cookie validation)
    //   ytm_service.dart -7003B (ytm_service_internals part: InnerTube search
    //     response traversal, track parsing, locale args, client descriptor)
    //   yt_download_service.dart -1907B (yt_download_service_types part:
    //     progress/queue value types, Range-ignored marker, part retention)
    //   playlists_screen.dart -12174B (playlists_screen_components part:
    //     hero card, playlist card and the dashed-border wrapper)
    const caps = {
      'lib/data/audio/audio_handler.dart': 223500,
      'lib/features/player/cubit/player_cubit.dart': 170000,
      'lib/features/library/presentation/library_screen.dart': 88000,
      'lib/data/audio/equalizer_manager.dart': 106950,
      'lib/features/settings/cubit/settings_cubit.dart': 82500,
      // Remaining god-files from the 2026-10 gap register. Caps are pinned to
      // the current size so they can only shrink; extract a collaborator and
      // lower the cap, never raise it. (Re-pinned after the null-safety fix in
      // ytm_account_service and the bounded-failure-map guard in ytm_service.)
      'lib/core/services/ytm_account_service.dart': 134883,
      'lib/core/services/yt_download_service.dart': 75731,
      'lib/core/services/ytm_service.dart': 78100,
      'lib/features/playlists/presentation/playlists_screen.dart': 82750,
    };
    final offenders = <String>[];
    caps.forEach((path, cap) {
      final size = File(path).statSync().size;
      if (size > cap) offenders.add('$path: $size > $cap');
    });
    expect(offenders, isEmpty,
        reason: 'core files grew — extract a collaborator and lower the cap:\n'
            '${offenders.join('\n')}');
  });
}
