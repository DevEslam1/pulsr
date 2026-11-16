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
    //
    // Full coverage tranche: every hand-written source file above 60 KB is
    // now ratcheted (generated sources and the pure Tanzil text asset excluded),
    // so no god-file can grow unnoticed.
    const caps = {
      'lib/data/audio/audio_handler.dart': 145000,
      'lib/features/player/cubit/player_cubit.dart': 50000,
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
      // Full coverage tranche (current sizes).
      'lib/features/player/presentation/widgets/eq_sheet_shell.dart': 164882,
      'lib/features/player/presentation/widgets/eq_advanced_controls.dart':
          163548,
      'lib/data/repositories/music_repository.dart': 159278,
      'lib/features/player/presentation/widgets/audio_quality_sheet.dart':
          129555,
      'lib/features/player/presentation/mini_player.dart': 105277,
      'lib/features/home/presentation/widgets/quran_radio_hero_carousel.dart':
          98417,
      'lib/features/player/presentation/widgets/tablet_player_bar.dart': 93323,
      'lib/data/audio/audio_handler_queue_engine.dart': 83446,
      'lib/features/search/presentation/search_screen.dart': 82962,
      'lib/features/settings/cubit/settings_audio_actions.dart': 83650,
      'lib/data/audio/audio_effects_channel.dart': 82584,
      'lib/features/player/presentation/themes/player_theme_chrome.dart': 70368,
      'lib/features/onboarding/presentation/onboarding_screen.dart': 64077,
      'lib/features/playlist_detail/presentation/online_playlist_detail_screen.dart':
          63553,
      'lib/data/repositories/download_repository_impl.dart': 63189,
      'lib/features/folder_detail/presentation/folder_detail_screen.dart':
          62296,
      'lib/features/radio/presentation/radio_screen.dart': 61759,
    };
    final offenders = <String>[];
    caps.forEach((path, cap) {
      // Count logical source size, not checkout line endings: a CRLF working
      // tree is one extra byte per line and must not trip a size ratchet that
      // was calibrated on LF.
      final bytes = File(path).readAsBytesSync();
      var size = bytes.length;
      for (var index = 0; index + 1 < bytes.length; index++) {
        if (bytes[index] == 0x0D && bytes[index + 1] == 0x0A) size--;
      }
      if (size > cap) offenders.add('$path: $size > $cap');
    });
    expect(offenders, isEmpty,
        reason: 'core files grew — extract a collaborator and lower the cap:\n'
            '${offenders.join('\n')}');
  });
}
