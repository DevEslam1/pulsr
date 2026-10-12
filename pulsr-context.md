# PULSR — SLIM ARCHITECTURE & REPO CONTEXT

> Offline-first audiophile music player.
> Flutter (frontend/BLoC) + C++20 NDK (Audio DSP Engine) + Go (Listen Together Party Server).

---

## 1. Directory Tree (Depth <= 3)
```
pulsr/
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── deploy-pages.yml
├── .kilo/
│   └── .gitignore
├── android/
│   ├── .gradle/
│   │   ├── 9.1.0/
│   │   ├── buildOutputCleanup/
│   │   ├── kotlin/
│   │   ├── noVersion/
│   │   ├── vcs-1/
│   │   └── file-system.probe
│   ├── .kotlin/
│   │   ├── errors/
│   │   └── sessions/
│   ├── app/
│   │   ├── src/
│   │   ├── build.gradle.kts
│   │   ├── google-services.json
│   │   └── proguard-rules.pro
│   ├── gradle/
│   │   └── wrapper/
│   ├── .gitignore
│   ├── build.gradle.kts
│   ├── gradle.properties
│   ├── gradlew
│   ├── gradlew.bat
│   ├── hs_err_pid32500.log
│   ├── local.properties
│   ├── pulsr_android.iml
│   ├── replay_pid32500.log
│   └── settings.gradle.kts
├── assets/
│   ├── app_icon/
│   ├── eq_profiles/
│   │   └── headphone_profiles.json
│   └── fonts/
├── coverage/
│   └── lcov.info
├── docs/
│   ├── adr/
│   │   ├── 001-player-controller-decomposition.md
│   │   ├── 002-app-error-sealed-taxonomy.md
│   │   ├── 003-mutex-and-monotonic-concurrency.md
│   │   ├── 004-weak-reference-artwork-cache.md
│   │   ├── 005-dsp-audio-processing-chain.md
│   │   ├── 006-multi-slot-queue-persistence.md
│   │   ├── 007-dependency-injection.md
│   │   ├── 007-ui-sound-design.md
│   │   ├── 008-router.md
│   │   ├── 009-responsive-layout.md
│   │   ├── 010-network-and-proxy.md
│   │   ├── 011-telemetry.md
│   │   ├── 012-settings-state.md
│   │   ├── 013-playlists.md
│   │   ├── 014-domain-layering.md
│   │   └── 015-database-encryption.md
│   ├── AUDIO_BRIDGE_VERIFICATION.md
│   ├── AUDIO_DSP_HARDENING_2026-10-03.md
│   ├── AUDIO_DSP_REVIEW_2026-10-03.md
│   ├── AUDIO_OUTPUT_SHEET_AUDIT_2026-10-04.md
│   ├── player_architecture.md
│   ├── player_architecture_audit.md
│   └── QURAN_BLUETOOTH_DEVICE_CHECK_2026-10-04.md
├── ios/
│   ├── Flutter/
│   │   ├── ephemeral/
│   │   ├── AppFrameworkInfo.plist
│   │   ├── Debug.xcconfig
│   │   ├── flutter_export_environment.sh
│   │   ├── Generated.xcconfig
│   │   └── Release.xcconfig
│   ├── Runner/
│   │   ├── Assets.xcassets/
│   │   ├── Base.lproj/
│   │   ├── AppDelegate.swift
│   │   ├── GeneratedPluginRegistrant.h
│   │   ├── GeneratedPluginRegistrant.m
│   │   ├── Info.plist
│   │   ├── Runner-Bridging-Header.h
│   │   ├── Runner.entitlements
│   │   └── SceneDelegate.swift
│   ├── Runner.xcodeproj/
│   │   ├── project.xcworkspace/
│   │   ├── xcshareddata/
│   │   └── project.pbxproj
│   ├── Runner.xcworkspace/
│   │   ├── xcshareddata/
│   │   └── contents.xcworkspacedata
│   ├── RunnerTests/
│   │   └── RunnerTests.swift
│   └── .gitignore
├── lib/
│   ├── core/
│   │   ├── bloc/
│   │   ├── config/
│   │   ├── constants/
│   │   ├── di/
│   │   ├── errors/
│   │   ├── motion/
│   │   ├── network/
│   │   ├── performance/
│   │   ├── responsive/
│   │   ├── router/
│   │   ├── services/
│   │   ├── telemetry/
│   │   ├── theme/
│   │   ├── utils/
│   │   └── widgets/
│   ├── data/
│   │   ├── audio/
│   │   ├── db/
│   │   ├── lyrics/
│   │   ├── models/
│   │   ├── party/
│   │   ├── repositories/
│   │   ├── scanner/
│   │   ├── services/
│   │   ├── usecases/
│   │   └── visualizer/
│   ├── domain/
│   │   ├── interfaces/
│   │   ├── models/
│   │   ├── repositories/
│   │   ├── services/
│   │   ├── usecases/
│   │   └── boundaries.dart
│   ├── features/
│   │   ├── album_detail/
│   │   ├── artist_detail/
│   │   ├── auth/
│   │   ├── downloads/
│   │   ├── folder_detail/
│   │   ├── genre_detail/
│   │   ├── home/
│   │   ├── library/
│   │   ├── onboarding/
│   │   ├── party/
│   │   ├── player/
│   │   ├── playlist_detail/
│   │   ├── playlists/
│   │   ├── queue/
│   │   ├── quran_mode/
│   │   ├── radio/
│   │   ├── search/
│   │   ├── settings/
│   │   ├── sheets/
│   │   ├── shell/
│   │   ├── smart_playlist_builder/
│   │   ├── splash/
│   │   ├── tag_editor/
│   │   ├── widgets/
│   │   ├── year_detail/
│   │   ├── ytm_browse/
│   │   └── ytm_search/
│   ├── l10n/
│   │   ├── generated/
│   │   ├── app_ar.arb
│   │   ├── app_en.arb
│   │   └── app_es.arb
│   ├── services/
│   │   ├── canvas/
│   │   ├── discord/
│   │   └── updater/
│   ├── firebase_options.dart
│   └── main.dart
├── linux/
│   ├── flutter/
│   │   ├── ephemeral/
│   │   ├── CMakeLists.txt
│   │   ├── generated_plugin_registrant.cc
│   │   ├── generated_plugin_registrant.h
│   │   └── generated_plugins.cmake
│   ├── runner/
│   │   ├── CMakeLists.txt
│   │   ├── main.cc
│   │   ├── my_application.cc
│   │   └── my_application.h
│   ├── .gitignore
│   └── CMakeLists.txt
├── macos/
│   ├── Flutter/
│   │   ├── ephemeral/
│   │   ├── Flutter-Debug.xcconfig
│   │   ├── Flutter-Release.xcconfig
│   │   └── GeneratedPluginRegistrant.swift
│   ├── Runner/
│   │   ├── Assets.xcassets/
│   │   ├── Base.lproj/
│   │   ├── Configs/
│   │   ├── AppDelegate.swift
│   │   ├── DebugProfile.entitlements
│   │   ├── Info.plist
│   │   ├── MainFlutterWindow.swift
│   │   └── Release.entitlements
│   ├── Runner.xcodeproj/
│   │   ├── project.xcworkspace/
│   │   ├── xcshareddata/
│   │   └── project.pbxproj
│   ├── Runner.xcworkspace/
│   │   ├── xcshareddata/
│   │   └── contents.xcworkspacedata
│   ├── RunnerTests/
│   │   └── RunnerTests.swift
│   └── .gitignore
├── scratch/
├── scripts/
│   ├── audio_bridge_smoke/
│   │   ├── AaudioSinkSmoke.java
│   │   ├── AudioEffectsPlugin.java
│   │   ├── FloatSinkSmoke.java
│   │   ├── NativeDspSmoke.java
│   │   └── OutputRoutingSmoke.java
│   ├── bench_native_dsp.cpp
│   ├── check_claude_dsp_docs.py
│   ├── check_coverage.py
│   ├── check_native_test_sources.py
│   ├── check_prod_flavor.py
│   ├── generate_ai_context.py
│   ├── generate_autoeq_dataset.py
│   ├── measure_audio_gap.py
│   ├── run_audio_bridge_smoke.ps1
│   ├── run_audio_playback_smoke.ps1
│   ├── run_audio_suites.sh
│   └── run_native_dsp_tests.sh
├── server/
│   └── pulsr_party/
│       ├── clock/
│       ├── codes/
│       ├── config/
│       ├── deploy/
│       ├── hub/
│       ├── loadtest/
│       ├── party/
│       ├── presence/
│       ├── protocol/
│       ├── tools/
│       ├── .gitignore
│       ├── go.mod
│       ├── go.sum
│       ├── main.go
│       ├── main_test.go
│       ├── README.md
│       └── render.yaml
├── shaders/
│   └── milkdrop.frag
├── test/
│   ├── a11y/
│   │   └── accessibility_compliance_test.dart
│   ├── architecture/
│   │   ├── code_hygiene_test.dart
│   │   ├── empty_catch_ratchet_test.dart
│   │   ├── fat_file_ratchet_test.dart
│   │   ├── no_todo_markers_test.dart
│   │   ├── player_controller_decomposition_test.dart
│   │   ├── privacy_manifest_test.dart
│   │   ├── rtl_ratchet_test.dart
│   │   └── settings_wiring_test.dart
│   ├── audit/
│   │   ├── audit_all_phases_100_percent_test.dart
│   │   ├── audit_bug_fixes_test.dart
│   │   ├── audit_codebase_fixes_test.dart
│   │   ├── audit_codebase_remediation_test.dart
│   │   ├── audit_core_data_layer_fixes_test.dart
│   │   ├── audit_fixes_verification_test.dart
│   │   ├── audit_master_suite_test.dart
│   │   ├── audit_phase5_hardening_test.dart
│   │   ├── audit_ux_notification_controls_test.dart
│   │   ├── codebase_audit_fixes_test.dart
│   │   ├── full_audit_master_verification_test.dart
│   │   ├── full_feature_audit_fixes_test.dart
│   │   ├── max_rate_remediation_test.dart
│   │   ├── p0_bug_fixes_test.dart
│   │   ├── p1_bug_fixes_test.dart
│   │   ├── p2_bug_fixes_test.dart
│   │   ├── p3_bug_fixes_test.dart
│   │   ├── regression_fixes_test.dart
│   │   ├── remediation_audit_regression_test.dart
│   │   └── remediation_tranche_audit_test.dart
│   ├── benchmark/
│   │   └── state_performance_benchmark_test.dart
│   ├── concurrency/
│   │   └── concurrency_hardening_test.dart
│   ├── core/
│   │   ├── bloc/
│   │   ├── config/
│   │   ├── constants/
│   │   ├── di/
│   │   ├── errors/
│   │   ├── l10n/
│   │   ├── motion/
│   │   ├── network/
│   │   ├── responsive/
│   │   ├── router/
│   │   ├── services/
│   │   ├── startup/
│   │   ├── telemetry/
│   │   ├── theme/
│   │   ├── utils/
│   │   ├── widgets/
│   │   ├── phase_1_components_test.dart
│   │   └── phase_3_caching_test.dart
│   ├── data/
│   │   ├── audio/
│   │   ├── db/
│   │   ├── lyrics/
│   │   ├── party/
│   │   ├── repositories/
│   │   ├── scanner/
│   │   ├── services/
│   │   ├── usecases/
│   │   └── visualizer/
│   ├── db/
│   │   ├── legacy_schema.dart
│   │   ├── migration_resilience_test.dart
│   │   └── migration_test.dart
│   ├── di/
│   │   └── injection_graph_test.dart
│   ├── domain/
│   │   ├── models/
│   │   ├── repositories/
│   │   ├── services/
│   │   └── usecases/
│   ├── errors/
│   │   └── app_error_taxonomy_test.dart
│   ├── features/
│   │   ├── album_detail/
│   │   ├── artist_detail/
│   │   ├── auth/
│   │   ├── downloads/
│   │   ├── folder_detail/
│   │   ├── genre_detail/
│   │   ├── home/
│   │   ├── library/
│   │   ├── onboarding/
│   │   ├── perf/
│   │   ├── player/
│   │   ├── playlist_detail/
│   │   ├── playlists/
│   │   ├── polish/
│   │   ├── queue/
│   │   ├── quran_mode/
│   │   ├── radio/
│   │   ├── responsive/
│   │   ├── search/
│   │   ├── settings/
│   │   ├── sheets/
│   │   ├── shell/
│   │   ├── smart_playlist_builder/
│   │   ├── splash/
│   │   ├── tag_editor/
│   │   ├── widgets/
│   │   ├── year_detail/
│   │   ├── ytm_browse/
│   │   ├── ytm_search/
│   │   ├── adaptive_tablet_layout_test.dart
│   │   ├── audit_bug_fixes_test.dart
│   │   ├── meloplay_features_test.dart
│   │   ├── navigation_and_recents_pagination_test.dart
│   │   ├── playback_integration_test.dart
│   │   ├── sound_wiring_test.dart
│   │   └── ytm_download_cubit_test.dart
│   ├── fuzz/
│   │   └── parser_fuzz_test.dart
│   ├── golden/
│   │   ├── goldens/
│   │   ├── mini_player_golden_test.dart
│   │   ├── player_top_bar_golden_test.dart
│   │   ├── settings_section_golden_test.dart
│   │   └── song_tile_golden_test.dart
│   ├── helpers/
│   │   ├── detail_screen_harness.dart
│   │   ├── screen_harness.dart
│   │   ├── test_pulsr_audio_handler.dart
│   │   └── test_song_factory.dart
│   ├── integration/
│   │   ├── app_flow_test.dart
│   │   ├── gapless_playback_test.dart
│   │   ├── playback_integration_test.dart
│   │   ├── smoke_flow_test.dart
│   │   └── widget_test.dart
│   ├── lifecycle/
│   │   └── disposal_audit_test.dart
│   ├── mocks/
│   │   ├── audio_player_backend.dart
│   │   └── fake_audio_player_backend.dart
│   ├── perf/
│   │   ├── frame_budget_test.dart
│   │   └── rebuild_audit_test.dart
│   ├── property/
│   │   └── state_property_test.dart
│   ├── responsive/
│   │   ├── adaptive_grid_test.dart
│   │   ├── breakpoint_test.dart
│   │   ├── content_max_width_unification_test.dart
│   │   ├── layout_test.dart
│   │   ├── responsive_device_matrix_test.dart
│   │   ├── responsive_extended_test.dart
│   │   ├── responsive_layout_metrics_test.dart
│   │   └── responsive_tokens_test.dart
│   ├── security/
│   │   └── security_hardening_test.dart
│   ├── services/
│   │   ├── canvas/
│   │   ├── discord/
│   │   └── updater/
│   ├── support/
│   │   ├── fake_audio_player.dart
│   │   ├── fake_audio_session.dart
│   │   ├── fake_clock.dart
│   │   └── fake_hi_res_audio_service.dart
│   ├── ux/
│   │   ├── player_responsive_regression_test.dart
│   │   ├── recents_recovery_test.dart
│   │   ├── settings_responsive_regression_test.dart
│   │   ├── shared_ux_regression_test.dart
│   │   └── utility_responsive_regression_test.dart
│   ├── firebase_options_test.dart
│   ├── main_bootstrap_test.dart
│   └── main_test.dart
├── tool/
├── web/
│   ├── icons/
│   ├── index.html
│   └── manifest.json
├── website/
│   ├── assets/
│   ├── app.js
│   ├── index.html
│   └── styles.css
├── windows/
│   ├── flutter/
│   │   ├── ephemeral/
│   │   ├── CMakeLists.txt
│   │   ├── generated_plugin_registrant.cc
│   │   ├── generated_plugin_registrant.h
│   │   └── generated_plugins.cmake
│   ├── runner/
│   │   ├── resources/
│   │   ├── CMakeLists.txt
│   │   ├── flutter_window.cpp
│   │   ├── flutter_window.h
│   │   ├── main.cpp
│   │   ├── resource.h
│   │   ├── runner.exe.manifest
│   │   ├── Runner.rc
│   │   ├── utils.cpp
│   │   ├── utils.h
│   │   ├── win32_window.cpp
│   │   └── win32_window.h
│   ├── .gitignore
│   └── CMakeLists.txt
├── .flutter-plugins-dependencies
├── .gitignore
├── .metadata
├── analysis_options.yaml
├── audio_pipeline_reference.md
├── build.yaml
├── CLAUDE.md
├── DESIGN.md
├── DESIGN_SYSTEM.md
├── devtools_options.yaml
├── firebase.json
├── flutter_launcher_icons-dev.yaml
├── flutter_launcher_icons-ytm.yaml
├── gaps.md
├── l10n.yaml
├── LICENSE
├── pubspec.lock
├── pubspec.yaml
├── pulsr.iml
├── README.md
├── RUNBOOK.md
├── skills-lock.json
└── sounds.md
```

---

## 2. Core Build & Analysis Configurations

### `pubspec.yaml`
```yaml
name: pulsr
description: "Pulsr Music - Premium offline-first local music player"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: '>=3.41.0'
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_bloc: ^9.1.1
  go_router: ^18.0.1
  just_audio: ^0.10.6
  audio_service: ^0.18.18
  audio_session: ^0.2.4
  mutex: ^3.1.0
  on_audio_query: ^2.9.0
  drift: ^2.26.0
  drift_flutter: ^0.3.1
  path_provider: ^2.1.5
  path: ^1.9.1
  sqlite3_flutter_libs: ^0.6.0+eol
  palette_generator: ^0.3.3+6
  dynamic_color: ^2.1.0
  flutter_animate: ^4.5.2
  permission_handler: ^13.0.2
  shared_preferences: ^2.5.2
  fpdart: ^1.1.0
  get_it: ^9.2.1
  injectable: ^3.0.0
  freezed_annotation: ^3.1.0
  file_picker: ^12.2.0
  image_picker: ^1.1.2
  share_plus: ^13.3.0
  home_widget: ^0.9.4
  sentry_flutter: ^8.14.2
  firebase_core: ^4.14.0
  firebase_auth: ^6.6.1
  cloud_firestore: ^6.9.0
  google_sign_in: ^7.2.0
  flutter_inappwebview: ^6.1.5
  crypto: ^3.0.6
  http: ^1.3.0
  flutter_localizations:
    sdk: flutter
  intl: ^0.20.2
  flutter_secure_storage: ^11.0.0
  rxdart: ^0.28.0
  clock: ^1.1.2
  connectivity_plus: ^6.1.4
  flutter_lyric: ^3.0.7
  video_player: ^2.14.1
  web_socket_channel: ^3.0.3

# Vendored fork: adds NativeDspAudioProcessor to the ExoPlayer audio sink so
# libpulsr_dsp receives the decoded PCM stream. Nothing else is changed.
dependency_overrides:
  just_audio:
    path: third_party/just_audio

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  drift_dev: ^2.26.0
  build_runner: ^2.4.15
  mocktail: ^1.0.4
  just_audio_platform_interface: ^4.6.0
  bloc_test: ^10.0.0
  injectable_generator: ^3.1.3
  freezed: ^4.0.1
  flutter_launcher_icons: ^0.14.4
  fake_async: ^1.3.3
  # Platform-interface packages are referenced directly by tests that install
  # fake platform implementations (path provider, file picker, webview).
  cross_file: ^0.3.5
  plugin_platform_interface: ^2.1.8
  path_provider_platform_interface: ^2.1.3

flutter:
  uses-material-design: true
  generate: true

  assets:
    - assets/app_icon/
    - assets/eq_profiles/

  shaders:
    - shaders/milkdrop.frag

  fonts:
    - family: Manrope
      fonts:
        - asset: assets/fonts/Manrope-VariableFont_wght.ttf

flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/app_icon/app_icon_plus.png"
  min_sdk_android: 21
  adaptive_icon_background: "#0A0C12"
  adaptive_icon_foreground: "assets/app_icon/app_icon_plus.png"
  web:
    generate: true
    image_path: "assets/app_icon/app_icon_plus.png"
  windows:
    generate: true
    image_path: "assets/app_icon/app_icon_plus.png"



```

### `analysis_options.yaml`
```yaml
# This file configures the analyzer, which statically analyzes Dart code to
# check for errors, warnings, and lints.
#
# The issues identified by the analyzer are surfaced in the UI of Dart-enabled
# IDEs (https://dart.dev/tools#ides-and-editors). The analyzer can also be
# invoked from the command line by running `flutter analyze`.

# The following line activates a set of recommended lints for Flutter apps,
# packages, and plugins designed to encourage good coding practices.
analyzer:
  exclude:
    - build/**
    - android/**
    - ios/**
    - web/**
    - windows/**
    - macos/**
    - linux/**
include: package:flutter_lints/flutter.yaml

linter:
  # The lint rules applied to this project can be customized in the
  # section below to disable rules from the `package:flutter_lints/flutter.yaml`
  # included above or to enable additional rules. A list of all available lints
  # and their documentation is published at https://dart.dev/lints.
  #
  # Instead of disabling a lint rule for the entire project in the
  # section below, it can also be suppressed for a single line of code
  # or a specific dart file by using the `// ignore: name_of_lint` and
  # `// ignore_for_file: name_of_lint` syntax on the line or in the file
  # producing the lint.
  rules:
    avoid_print: true
    empty_catches: true
    prefer_final_locals: true

# Additional information about this file can be found at
# https://dart.dev/guides/language/analysis-options

```

### `android/app/src/main/cpp/CMakeLists.txt`
```cmake
cmake_minimum_required(VERSION 3.22)
project("pulsr_dsp")

# Ensure C++20 standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Ignore/unset Windows CMAKE_INSTALL_PREFIX on Android builds
if(ANDROID)
    set(CMAKE_INSTALL_PREFIX "/usr" CACHE PATH "Default install path" FORCE)
    # P0-1: Android 15+ 16 KB memory-page size compatibility
    add_link_options(-Wl,-z,max-page-size=16384)
endif()

# Global linker flags: garbage collect unused sections across all configurations
add_link_options(-Wl,--gc-sections)

# Base compile options
add_compile_options(
    -Wall
    -Wextra
    -Werror=return-type
    -fno-strict-aliasing
    -fno-math-errno
)

# ASan/UBSan need the clang runtime (libclang_rt.asan-<abi>-android.so) to be
# packaged with the APK - it is not, so enabling this in a normal build makes
# libpulsr_dsp.so fail to dlopen ("libclang_rt.asan-x86_64-android.so not
# found") and silently disables all DSP. Opt in explicitly only if you also
# bundle the sanitizer runtime:
#   ./gradlew assembleYtmDebug -Pandroid.native.buildCmakeArgs="-DPULSR_DSP_WITH_ASAN=ON"
option(PULSR_DSP_WITH_ASAN "Build libpulsr_dsp with ASan/UBSan (requires bundling the sanitizer runtime)" OFF)
if(PULSR_DSP_WITH_ASAN)
    add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
    add_link_options(-fsanitize=address,undefined)
endif()

# NEON tuning for armeabi-v7a if targeted
if(ANDROID_ABI STREQUAL "armeabi-v7a")
    add_compile_options(-mfpu=neon-vfpv4 -mfloat-abi=softfp)
endif()

set(DSP_CORE_SOURCES
    ParametricEQ.cpp
    Crossfeed.cpp
    LookaheadLimiter.cpp
    ConvolutionReverb.cpp
    SincResampler.cpp
    DsdDecoder.cpp
    SpatialPanner.cpp
    HarmonicSaturation.cpp
    StereoWidth.cpp
    LoudnessContour.cpp
    SubCrossover.cpp
    DynamicEQ.cpp
    MultibandCompressor.cpp
    DynamicBass.cpp
    ViperDdc.cpp
    ArbitraryResponseEq.cpp
    LiveProg.cpp
    AudioDspEngine.cpp
    AAudioSink.cpp
    UsbAudioSink.cpp
)

set(JNI_BRIDGE_SOURCES
    eq_jni_bridge.cpp
    aaudio_jni_bridge.cpp
)

add_library(pulsr_dsp SHARED
    ${DSP_CORE_SOURCES}
    ${JNI_BRIDGE_SOURCES}
)

# Disable RTTI and exceptions on DSP core translation units.
# JNI bridges retain exceptions to safely catch std::bad_alloc/runtime exceptions at bridge boundary.
set_source_files_properties(${DSP_CORE_SOURCES} PROPERTIES
    COMPILE_FLAGS "-fno-exceptions -fno-rtti"
)

# Configuration-specific optimization flags:
# - Debug: -O1 -g (instead of -O0) so real-time audio deadlines are testable on device without buffer underruns
# - Release / RelWithDebInfo: -O3 -flto=thin with linker LTO
target_compile_options(pulsr_dsp PRIVATE
    $<$<CONFIG:Debug>:-O1 -g>
    $<$<CONFIG:RelWithDebInfo>:-O3 -g -flto=thin>
    $<$<CONFIG:Release>:-O3 -flto=thin>
)

target_link_options(pulsr_dsp PRIVATE
    $<$<CONFIG:RelWithDebInfo>:-flto=thin -Wl,--lto-O3>
    $<$<CONFIG:Release>:-flto=thin -Wl,--lto-O3>
)

find_library(log-lib log)
find_library(android-lib android)

target_link_libraries(pulsr_dsp
    ${log-lib}
    ${android-lib}
    aaudio
    m
)

```

### `android/app/build.gradle.kts`
```kotlin
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.pulsr.music"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.pulsr.music"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 28 (Android 9) is the floor for the true 10-band graphic EQ, which is
        // built on DynamicsProcessing postEq — added in API 28.
        minSdk = 28
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appName"] = "Pulsr Music"
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    flavorDimensions += "default"
    productFlavors {
        create("dev") {
            dimension = "default"
            applicationIdSuffix = ".plus"
            manifestPlaceholders["appName"] = "Pulsr Plus"
            proguardFile(file("src/dev/proguard-rules.pro"))
        }
        create("prod") {
            dimension = "default"
            manifestPlaceholders["appName"] = "Pulsr Music"
        }
        // Off-Play distribution build. Identical to prod but compiles the
        // NewPipeExtractor bridge, so YouTube Music search/stream/download works.
        create("ytm") {
            dimension = "default"
            applicationIdSuffix = ".ytm"
            manifestPlaceholders["appName"] = "Pulsr Music"
            proguardFile(file("src/ytm/proguard-rules.pro"))
        }
    }

    // Flavor-specific ProGuard keep rules for NewPipeExtractor + Rhino.
    // AGP does NOT auto-discover src/<flavor>/proguard-rules.pro, so we wire them
    // explicitly. B-02 fix: these rules were previously dead code; without them
    // R8 strips the extractor in dev/ytm release builds -> runtime crash.
    // Using androidComponents to inject per-flavor proguard files correctly.
    // Fallback wiring via buildTypes ensures the rules are present even if
    // productFlavors ProGuard DSL is not supported in this AGP version.

    // The extractor bridge lives outside src/main so that `prod` -- the Play
    // Store variant -- cannot compile it and does not link NewPipeExtractor at
    // all. This is a hard exclusion, unlike the Dart-side ENABLE_YTM gate which
    // only relies on tree-shaking. Both source sets must declare the same
    // YtmExtractorPlugin class, because MainActivity in src/main references it.
    // The assets dir carries the BotGuard page the poToken WebView runs, which is
    // likewise GPL and so likewise kept out of prod.
    sourceSets {
        getByName("dev") {
            kotlin.srcDir("src/ytmEnabled/kotlin")
            assets.srcDir("src/ytmEnabled/assets")
        }
        getByName("ytm") {
            kotlin.srcDir("src/ytmEnabled/kotlin")
            assets.srcDir("src/ytmEnabled/assets")
        }
        getByName("prod") { kotlin.srcDir("src/ytmDisabled/kotlin") }
    }

    val keystoreProperties = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) {
            load(FileInputStream(f))
        }
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("keyAlias")) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            val releaseConfig = signingConfigs.getByName("release")
            val hasKeystore = releaseConfig.storeFile != null && releaseConfig.storeFile!!.exists()
            signingConfig = if (hasKeystore) releaseConfig else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            // Flavor-specific ProGuard rules are scoped per-flavor via androidComponents (B-11b)
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    testOptions {
        // B-10 fix: false prevents silent stubbing of un-mocked MethodChannels (which caused false-greens)
        unitTests.isReturnDefaultValues = false
        unitTests.isIncludeAndroidResources = true
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    packaging {
        resources {
            excludes += "google/protobuf/**"
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "META-INF/INDEX.LIST"
            excludes += "META-INF/io.netty.versions.properties"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Scoped to this module rather than the root allprojects block: JitPack serves
// unreviewed builds straight from git tags, so only the app needs to trust it.
repositories {
    maven { url = uri("https://jitpack.io") }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
    implementation("net.jthink:jaudiotagger:3.0.1")
    implementation("androidx.media:media:1.7.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation(project(":media3-decoder-flac"))

    // GPL-3.0. Its presence is why Pulsr as a whole is GPL-3.0, and why it is
    // kept out of the prod (Play Store) variant. Pulls in Mozilla Rhino, which
    // solves YouTube's JS signature challenges on-device.
    val newPipeExtractor = "com.github.TeamNewPipe:NewPipeExtractor:v0.26.5"
    "devImplementation"(newPipeExtractor)
    "ytmImplementation"(newPipeExtractor)

    // Google Cast SDK. Scoped to the dev/ytm flavors only: the prod (Play Store)
    // "Pure" variant strips INTERNET and must not ship Cast or Play Services
    // routing. The matching code lives in sourceSets dev/ytm (src/ytmEnabled).
    val castFramework = "com.google.android.gms:play-services-cast-framework:21.5.0"
    "devImplementation"(castFramework)
    "ytmImplementation"(castFramework)

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20231013")
}

configurations.all {
    resolutionStrategy {
        force("com.google.protobuf:protobuf-javalite:3.25.5")
    }
}

tasks.matching { it.name.startsWith("package") && it.name.endsWith("UnitTestForUnitTest") }.configureEach {
    mustRunAfter(tasks.matching { it.name.startsWith("copyFlutterAssets") })
}

tasks.register("testNative") {
    group = "verification"
    description = "Compiles and executes the full native C++ DSP test suite on the host via CMake/CTest (parity -O3 + sanitizer/debug builds)."
    doLast {
        val testDir = file("src/test/cpp")
        val isWindows = org.apache.tools.ant.taskdefs.condition.Os.isFamily(org.apache.tools.ant.taskdefs.condition.Os.FAMILY_WINDOWS)

        // Host C++ compiler discovery (mirrors the CMake toolchain expectation).
        val compiler = if (project.hasProperty("hostClangPath")) {
            project.property("hostClangPath").toString()
        } else if (System.getenv("HOST_CLANG") != null) {
            System.getenv("HOST_CLANG")!!
        } else if (isWindows) {
            val windhawk = file("C:/Program Files/Windhawk/Compiler/bin/clang++.exe")
            if (windhawk.exists()) windhawk.absolutePath else "clang++"
        } else {
            "clang++"
        }

        // Locate the CMake executable: prefer an explicit override, then PATH,
        // then the Android SDK's bundled cmake (which ships a host cmake binary).
        fun findCmake(): String {
            if (project.hasProperty("cmakePath")) return project.property("cmakePath").toString()
            val envCmake = System.getenv("CMAKE")
            if (!envCmake.isNullOrBlank()) return envCmake
            val onPath = try {
                val proc = ProcessBuilder(if (isWindows) listOf("where", "cmake") else listOf("which", "cmake"))
                    .redirectErrorStream(true).start()
                val out = proc.inputStream.bufferedReader().readText().trim().lines().firstOrNull()
                val code = proc.waitFor()
                if (code == 0 && !out.isNullOrBlank()) out else null
            } catch (_: Throwable) { null }
            if (onPath != null) return onPath

            val localProps = file("../local.properties")
            val sdkFromProps = if (localProps.exists()) {
                localProps.readLines().firstOrNull { it.startsWith("sdk.dir=") }
                    ?.substringAfter("=")?.trim()?.replace("\\\\", "/")?.replace("\\", "/")
            } else null
            val sdkRoot = sdkFromProps
                ?: System.getenv("ANDROID_HOME")
                ?: System.getenv("ANDROID_SDK_ROOT")
                ?: (if (isWindows) System.getenv("LOCALAPPDATA")?.let { "$it/Android/Sdk" } else null)
            if (sdkRoot != null) {
                val cmakeDir = file("$sdkRoot/cmake")
                if (cmakeDir.exists()) {
                    val candidates = cmakeDir.listFiles()?.sortedByDescending { it.name } ?: emptyList()
                    for (dir in candidates) {
                        val exe = file("${dir.absolutePath}/bin/cmake" + if (isWindows) ".exe" else "")
                        if (exe.exists()) return exe.absolutePath
                    }
                }
            }
            return "cmake"
        }

        fun executeCmd(cmd: List<String>, desc: String, workingDir: File? = null) {
            val pb = ProcessBuilder(cmd).redirectErrorStream(true)
            if (isWindows) {
                val env = pb.environment()
                val currentPath = env["PATH"] ?: ""
                val windhawkBin = "<REL_PATH> Files\\Windhawk\\Compiler\\bin"
                env["PATH"] = "$windhawkBin;$currentPath"
            }
            if (workingDir != null) pb.directory(workingDir)
            val proc = pb.start()
            proc.inputStream.bufferedReader().useLines { lines ->
                lines.forEach { println("[$desc] $it") }
            }
            val res = proc.waitFor()
            if (res != 0) {
                throw GradleException("$desc failed with exit code $res")
            }
        }

        fun runBuild(configName: String, sanitizers: Boolean) {
            val buildDir = file("build/testNative/$configName").apply { mkdirs() }
            val cmake = findCmake()
            val ctest = File(File(cmake).parentFile, if (isWindows) "ctest.exe" else "ctest").takeIf { it.exists() }?.absolutePath ?: "ctest"
            val configureArgs = mutableListOf(
                cmake,
                "-S", testDir.absolutePath,
                "-B", buildDir.absolutePath,
                "-DCMAKE_BUILD_TYPE=$configName",
                "-DCMAKE_CXX_COMPILER=$compiler",
            )
            val ninja = File(File(cmake).parentFile, if (isWindows) "ninja.exe" else "ninja")
            if (ninja.exists()) {
                configureArgs += listOf("-G", "Ninja", "-DCMAKE_MAKE_PROGRAM=${ninja.absolutePath.replace('\\', '/')}")
            }
            if (sanitizers && !isWindows) {
                configureArgs += "-DPULSR_TEST_SANITIZERS=ON"
            }
            println("[testNative] Configuring $configName build ...")
            executeCmd(configureArgs, "testNative-configure-$configName")

            println("[testNative] Building $configName ...")
            executeCmd(
                listOf(cmake, "--build", buildDir.absolutePath, "--parallel"),
                "testNative-build-$configName"
            )

            if (isWindows) {
                val windhawkBin = file("C:/Program Files/Windhawk/Compiler/bin")
                for (dll in listOf("libc++.dll", "libunwind.dll")) {
                    val src = File(windhawkBin, dll)
                    if (src.exists()) {
                        src.copyTo(File(buildDir, dll), overwrite = true)
                        val whl = File(buildDir, dll.replace(".dll", ".whl"))
                        src.copyTo(whl, overwrite = true)
                    }
                }
            }

            println("[testNative] Running $configName test suite via CTest ...")
            executeCmd(
                listOf(ctest, "--test-dir", buildDir.absolutePath, "--output-on-failure"),
                "testNative-run-$configName"
            )
        }

        // (a) Parity build: exact production flags (-O3 -std=c++20).
        runBuild("Release", sanitizers = false)
        // (b) Sanitizer / debug build: ASan+UBSan where the host supports it.
        runBuild("Debug", sanitizers = true)

        println("[testNative] PASSED: parity (-O3) and sanitizer/debug native DSP suites passed 100%.")
    }
}

tasks.register("validateProdIsolation") {
    group = "verification"
    description = "Ensures GPL / YouTube Extractor code never compiles into the prod variant."
    doLast {
        val prodKotlinDir = file("src/ytmDisabled/kotlin")
        if (!prodKotlinDir.exists()) {
            throw GradleException("Prod stub directory src/ytmDisabled/kotlin is missing!")
        }
        val forbiddenTerms = listOf("music.youtube.com", "NewPipeExtractor", "org.schabi.newpipe", "po_token")

        // B2/B3 fix: byte-level ASCII scanning helper for binary files (.png, .so)
        fun fileContainsAsciiBytes(targetFile: File, term: String): Boolean {
            val termBytes = term.toByteArray(Charsets.US_ASCII)
            val bytes = targetFile.readBytes()
            if (bytes.size < termBytes.size) return false
            outer@ for (i in 0..(bytes.size - termBytes.size)) {
                for (j in termBytes.indices) {
                    if (bytes[i + j] != termBytes[j]) continue@outer
                }
                return true
            }
            return false
        }

        // 1. Check main Manifest
        val mainManifest = file("src/main/AndroidManifest.xml")
        if (mainManifest.exists()) {
            val content = mainManifest.readText()
            for (term in forbiddenTerms) {
                if (content.contains(term)) {
                    throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/AndroidManifest.xml!")
                }
            }
        }

        // 2. Check main Kotlin sources
        val mainKotlinDir = file("src/main/kotlin")
        if (mainKotlinDir.exists()) {
            mainKotlinDir.walkTopDown().filter { it.isFile && it.extension == "kt" }.forEach { file ->
                val text = file.readText()
                for (term in forbiddenTerms) {
                    if (text.contains(term)) {
                        throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/kotlin file: ${file.path}")
                    }
                }
            }
        }

        // 3. Check main res (B2/B3 fix: byte-level scan on images, text scan on xml)
        val mainResDir = file("src/main/res")
        if (mainResDir.exists()) {
            mainResDir.walkTopDown().filter { it.isFile && (it.extension == "xml" || it.extension == "png") }.forEach { file ->
                for (term in forbiddenTerms) {
                    if (file.extension == "png") {
                        if (fileContainsAsciiBytes(file, term)) {
                            throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/res file: ${file.path}")
                        }
                    } else {
                        if (file.readText().contains(term)) {
                            throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/res file: ${file.path}")
                        }
                    }
                }
            }
        }

        // 4. Check main assets
        val mainAssetsDir = file("src/main/assets")
        if (mainAssetsDir.exists()) {
            mainAssetsDir.walkTopDown().filter { it.isFile }.forEach { file ->
                val text = file.readText()
                for (term in forbiddenTerms) {
                    if (text.contains(term)) {
                        throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/assets file: ${file.path}")
                    }
                }
            }
        }

        // 5. Check Proguard rules
        val proguardRules = file("proguard-rules.pro")
        if (proguardRules.exists()) {
            val text = proguardRules.readText()
            for (term in forbiddenTerms) {
                if (text.contains(term)) {
                    throw GradleException("Forbidden GPL/YouTube term '$term' found in proguard-rules.pro!")
                }
            }
        }

        // 6. Check native C++ sources (B-12 completeness gap)
        val mainCppDir = file("src/main/cpp")
        if (mainCppDir.exists()) {
            mainCppDir.walkTopDown().filter { it.isFile && (it.extension == "cpp" || it.extension == "h" || it.extension == "c" || it.extension == "cc") }.forEach { file ->
                val text = file.readText()
                for (term in forbiddenTerms) {
                    if (text.contains(term)) {
                        throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/cpp file: ${file.path}")
                    }
                }
            }
        }

        // 7. Check jniLibs (prebuilt .so that could hide extractor) - B2/B3 fix
        val jniLibsDir = file("src/main/jniLibs")
        if (jniLibsDir.exists()) {
            jniLibsDir.walkTopDown().filter { it.isFile }.forEach { file ->
                val name = file.name
                for (term in forbiddenTerms) {
                    if (name.contains(term)) {
                        throw GradleException("Forbidden GPL/YouTube term '$term' found in jniLibs file name: ${file.path}")
                    }
                    if (fileContainsAsciiBytes(file, term)) {
                        throw GradleException("Forbidden GPL/YouTube term '$term' found in jniLibs binary: ${file.path}")
                    }
                }
            }
        }

        println("[validateProdIsolation] PASSED: Prod isolation verified successfully across manifests, kotlin, res, assets, proguard, cpp, and jniLibs.")
        // 8. Pulsr Pure: prod overlay must strip INTERNET + YTM download worker.
        val prodManifest = file("src/prod/AndroidManifest.xml")
        if (!prodManifest.exists()) {
            throw GradleException("Pulsr Pure prod overlay src/prod/AndroidManifest.xml is missing!")
        } else {
            val prodText = prodManifest.readText()
            if (!prodText.contains("android.permission.INTERNET") || !prodText.contains("tools:node=\"remove\"")) {
                throw GradleException("Pulsr Pure prod overlay must remove INTERNET permission!")
            }
            if (!prodText.contains(".DownloadService") || !prodText.contains("tools:node=\"remove\"")) {
                throw GradleException("Pulsr Pure prod overlay must remove DownloadService!")
            }
        }
    }
}

afterEvaluate {
    tasks.matching { it.name.startsWith("assemble") || it.name == "check" || it.name == "test" }.configureEach {
        dependsOn("validateProdIsolation")
    }
}

```

---

## 3. Flutter Entry & Dependency Injection Graph

### `lib/main.dart`
```dart
// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'core/errors/error_message_resolver.dart';
import 'core/utils/l10n_extensions.dart';
import 'core/utils/l10n_holder.dart';
import 'core/utils/startup_gates.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/generated/app_localizations.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/performance/gpu_budget.dart';
import 'core/utils/platform_capabilities.dart';
import 'core/config/app_config.dart';
import 'core/di/injection.dart';
import 'core/network/app_http_overrides.dart';
import 'core/services/artwork_cache_manager.dart';
import 'core/services/settings_cache.dart';
import 'core/services/sound_feedback_service.dart';
import 'core/services/automation_trigger_service.dart';
import 'core/theme/aura_theme.dart';
import 'core/theme/dynamic_theme_cubit.dart';
import 'core/widgets/cached_artwork.dart';
import 'core/widgets/pulsr_toast.dart';
import 'core/router/app_router.dart';
import 'core/network/network_change_monitor.dart';
import 'core/services/auth_service.dart';
import 'core/services/scrobbler_service.dart';
import 'core/services/file_intent_handler.dart';
import 'core/services/restore_detection_service.dart';
import 'core/services/ytm_account_service.dart';
import 'core/services/ytm_client_version_resolver.dart';
import 'core/services/ytm_service.dart';
import 'core/services/ytm_url_cache.dart';
import 'core/utils/error_logger.dart';
import 'core/utils/ytm_rate_limiter.dart';
import 'data/audio/audio_handler.dart';
import 'data/audio/eq_legacy_migration.dart';
import 'data/db/app_database.dart';
import 'data/scanner/media_scanner_service.dart';
import 'domain/repositories/music_repository_interface.dart';
import 'domain/usecases/get_songs_usecase.dart';
import 'domain/usecases/get_albums_usecase.dart';
import 'domain/usecases/get_artists_usecase.dart';
import 'domain/usecases/get_favorites_usecase.dart';
import 'domain/usecases/toggle_favorite_usecase.dart';
import 'domain/usecases/search_music_usecase.dart';
import 'domain/usecases/playlist_usecases.dart';
import 'domain/usecases/folder_usecases.dart';
import 'features/auth/cubit/auth_cubit.dart';
import 'features/auth/presentation/ytm_web_login_sheet.dart';
import 'features/library/cubit/library_cubit.dart';
import 'features/player/cubit/player_cubit.dart';
import 'features/player/cubit/player_state.dart';
import 'features/playlists/cubit/playlist_cubit.dart';
import 'features/search/cubit/search_cubit.dart';
import 'features/settings/cubit/settings_cubit.dart';
import 'features/settings/cubit/settings_state.dart';
import 'features/widgets/widget_service.dart';
import 'features/ytm_search/cubit/ytm_download_cubit.dart';
import 'domain/repositories/download_repository_interface.dart';
import 'features/downloads/cubit/downloads_cubit.dart';
import 'services/discord/discord_rpc_service.dart';
import 'services/updater/app_update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Cap the framework's decoded-image cache so artwork bitmaps cannot balloon
  // RAM under heavy scrolling (80 MB ceiling).
  PaintingBinding.instance.imageCache.maximumSizeBytes = 80 << 20;
  HttpOverrides.global = AppHttpOverrides.instance;
  // A production build with dev flags cannot be patched at runtime: surface a
  // blocking configuration screen instead of logging and continuing with
  // illegal flags (Play Store compliance).
  Object? fatalConfigError;
  try {
    AppConfig.validateConfiguration();
  } catch (e, st) {
    fatalConfigError = e;
    ErrorLogger.log('AppConfig.validateConfiguration error',
        error: e, stackTrace: st, category: 'Startup');
  }

  ErrorLogger.onCrashReported = (error, stackTrace, category) {
    // Single-sink rule: the Sentry capture (with scope tags) is owned by
    // ErrorLogger.log. This hook only mirrors the report to logcat so the
    // crash is not reported twice.
    debugPrint('[Pulsr.CrashReport][$category] $error\n$stackTrace');
  };
  ErrorLogger.initialize();

  // FIX-A3: Global error boundary for widget build errors
  ErrorWidget.builder = (FlutterErrorDetails details) {
    ErrorLogger.log(
      'Widget build error',
      error: details.exception,
      stackTrace: details.stack,
      category: 'UI',
    );
    return Builder(
      builder: (context) => Material(
        child: Center(
          child: Text(
            AppLocalizations.of(context)?.somethingWentWrong ?? 'Error',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  };

  if (fatalConfigError != null) {
    runApp(PulsrConfigurationErrorApp(
      title: AppConfig.appTitle,
      message: fatalConfigError.toString(),
    ));
    return;
  }

  // Initialize in-memory SettingsCache and ArtworkCacheManager
  try {
    await SettingsCache().init();
    await ArtworkCacheManager().init();
    await SoundFeedbackService.init();
  } catch (_) {}

  // Rehydrate the GPU budget before first frame (persisted by SettingsCubit).
  try {
    final prefs = await SharedPreferences.getInstance();
    try {
      await EqLegacyMigration.run(prefs);
    } catch (e, st) {
      ErrorLogger.log('EQ legacy migration failed',
          error: e, stackTrace: st, category: 'Startup');
    }
    GpuBudget.setEnabled(prefs.getBool('setting_reduce_motion') ?? false);
  } catch (_) {}
  // Warm native audio capability cache (best-effort, never blocks).
  unawaited(PlatformCapabilities.ensureLoaded()
      .timeout(const Duration(seconds: 5))
      .catchError((_) {}));

  // Firebase powers Auth + (optionally) cloud sync. Pure builds must perform
  // zero network work, so skip init there; elsewhere init best-effort so a
  // missing google-services file never blocks startup.
  if (!AppConfig.isPure) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Firebase.initializeApp failed — Auth runs offline-only',
          error: e, stackTrace: st, category: 'Startup');
    }
  }

  // System Chrome configuration for true edge-to-edge UI
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    ),
  );

  try {
    await configureDependencies().timeout(const Duration(seconds: 15));
  } catch (e, st) {
    ErrorLogger.log('DI configureDependencies failed or timed out',
        error: e, stackTrace: st, category: 'Startup');
  }

  SoundFeedbackService.isMusicPlaying = () {
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        return getIt<PulsrAudioHandler>().playbackState.value.playing;
      }
    } catch (_) {}
    return false;
  };

  // Defer heavy post-DI tasks to AFTER runApp to eliminate Davey! 1223ms jank on OnePlus
  // Previously awaited 3x8s before first frame -> Skipped 121 frames. Now fire-and-forget.
  void firePostStartupTasks() {
    // Run after first frame renders on screen so startup paints without jank
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Respect the user's offline-only setting at cold start: it must disable
      // every online initializer, not just the UI surfaces (mirrors
      // CloudSyncService's runtime gate). SharedPreferences MUST be awaited
      // before computing the gates; resolving it in a later microtask let the
      // synchronous onlineAllowed computation ignore offline-only mode.
      SharedPreferences? prefs;
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (e, st) {
        ErrorLogger.log('Failed to read startup preferences',
            error: e, stackTrace: st, category: 'Startup');
      }
      final onlineAllowed = StartupGates.onlineAllowed(prefs);
      final cloudSyncAllowed = StartupGates.cloudSyncAllowed(prefs);
      try {
        Future.wait([
          // Pure builds have no INTERNET permission: skip every online
          // initializer so Pulsr Pure performs zero network work at startup.
          if (onlineAllowed)
            YtmRateLimiter.shared
                .restore()
                .timeout(const Duration(seconds: 4))
                .catchError((e, st) {
              ErrorLogger.log('YtmRateLimiter restore failed or timed out',
                  error: e, stackTrace: st, category: 'Startup');
            }),
          if (cloudSyncAllowed)
            getIt<AuthService>()
                .initialize()
                .timeout(const Duration(seconds: 4))
                .catchError((e, st) {
              ErrorLogger.log('AuthService initialize failed or timed out',
                  error: e, stackTrace: st, category: 'Startup');
            }),
          if (onlineAllowed)
            getIt<YtmAccountService>()
                .init()
                .timeout(const Duration(seconds: 8))
                .catchError((e, st) {
              ErrorLogger.log('YtmAccountService init failed or timed out',
                  error: e, stackTrace: st, category: 'Startup');
            }),
          if (onlineAllowed && getIt.isRegistered<YtmClientVersionResolver>())
            getIt<YtmClientVersionResolver>()
                .init()
                .timeout(const Duration(seconds: 8))
                .catchError((e, st) {
              ErrorLogger.log(
                  'YtmClientVersionResolver init failed or timed out',
                  error: e,
                  stackTrace: st,
                  category: 'Startup');
            }),
          // Rehydrate guest stream URLs saved by the previous run so a replay
          // or skip-back after launch resolves instantly.
          if (onlineAllowed && getIt.isRegistered<YtmUrlCache>())
            getIt<YtmUrlCache>()
                .restore()
                .timeout(const Duration(seconds: 8))
                .catchError((e, st) {
              ErrorLogger.log('YtmUrlCache restore failed or timed out',
                  error: e, stackTrace: st, category: 'Startup');
            }),
        ]);
        // Warm the native extractor (BotGuard WebView + client matrix) while
        // the user is still looking at the home screen, so the first YTM
        // search/tap doesn't pay cold-start attestation (~seconds).
        // Fire-and-forget, guarded: never blocks or throws into startup.
        try {
          if (onlineAllowed && getIt.isRegistered<YtmService>()) {
            unawaited(getIt<YtmService>()
                .preWarm()
                .timeout(const Duration(seconds: 15))
                .catchError((_) {}));
          }
        } catch (_) {}
        // Scrobbler session recovery + credential migration (previously only
        // reachable from tests): recover a scrobble interrupted by process
        // death, and proactively move leftover plaintext credentials into
        // secure storage. Local-first; safe to run whenever cloud sync is on.
        try {
          if (cloudSyncAllowed && getIt.isRegistered<ScrobblerService>()) {
            final scrobbler = getIt<ScrobblerService>();
            unawaited(scrobbler
                .migrateAllCredentialsToSecureStorage()
                .then((_) => scrobbler.checkPendingScrobble())
                .timeout(const Duration(seconds: 10))
                .catchError((e, st) {
              ErrorLogger.log('Scrobbler startup recovery failed',
                  error: e, stackTrace: st, category: 'Startup');
            }));
          }
        } catch (e, st) {
          ErrorLogger.log('Scrobbler startup hook failed',
              error: e, stackTrace: st, category: 'Startup');
        }

        // Initialize Discord RPC if configured and online allowed
        try {
          if (onlineAllowed && prefs != null) {
            unawaited(DiscordRpcService.instance.init(prefs).then((_) {
              if (getIt.isRegistered<PlayerCubit>()) {
                DiscordRpcService.instance.bindToPlayerCubit(getIt<PlayerCubit>());
              }
            }).catchError((e, st) {
              ErrorLogger.log('DiscordRpcService init failed',
                  error: e, stackTrace: st, category: 'Startup');
            }));
          }
        } catch (_) {}

        // Best-effort check for app updates off GitHub releases
        try {
          if (onlineAllowed) {
            unawaited(AppUpdateService.instance.check().catchError((e, st) {
              ErrorLogger.log('AppUpdateService startup check failed',
                  error: e, stackTrace: st, category: 'Startup');
              return null;
            }));
          }
        } catch (_) {}
      } catch (e, st) {
        ErrorLogger.log('Parallel startup init failed',
            error: e, stackTrace: st, category: 'Startup');
      }
    });
  }

  var appStarted = false;
  if (AppConfig.isTelemetryAllowed) {
    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = AppConfig.sentryDsn;
          options.environment = AppConfig.envName;
          options.tracesSampleRate = AppConfig.isProd ? 0.2 : 1.0;
          options.sendDefaultPii = false;
          options.enableAutoPerformanceTracing = true;
        },
        appRunner: () {
          appStarted = true;
          runApp(const PulsrApp());
          firePostStartupTasks();
        },
      );
    } catch (e, st) {
      // A telemetry init failure must never black-screen the app: fall through
      // to the un-instrumented startup path below.
      ErrorLogger.log('SentryFlutter.init failed — starting without telemetry',
          error: e, stackTrace: st, category: 'Startup');
    }
  }
  if (!appStarted) {
    runApp(const PulsrApp());
    firePostStartupTasks();
  }
}

class PulsrApp extends StatefulWidget {
  const PulsrApp({super.key});

  @override
  State<PulsrApp> createState() => _PulsrAppState();
}

class _PulsrAppState extends State<PulsrApp> with WidgetsBindingObserver {
  GoRouter? _router;
  StreamSubscription<void>? _authExpiredSub;
  StreamSubscription<void>? _networkChangeSub;
  NetworkChangeMonitor? _networkMonitor;
  AutomationTriggerService? _automationTriggerService;
  VoidCallback? _platformBridgeDegradedListener;
  DateTime? _lastAuthExpiredPrompt;
  bool _dependenciesReady = false;
  bool _bootstrapFailed = false;
  bool _bootstrapInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = _createRouterSafely();
    _dependenciesReady = appDependenciesReady;
    if (!_dependenciesReady) {
      unawaited(_resolveDependencies());
    }
    _autoScanOnStartup();
    _checkInitialAudioIntent();
    if (AppConfig.ytmEnabled) _listenForYtmSessionExpiry();
    if (AppConfig.isCloudSyncAllowed) _startNetworkChangeMonitor();
    _startAutomationTriggers();
    _watchPlatformBridgeHealth();
    _verifyPureMode();
  }

  GoRouter? _createRouterSafely() {
    try {
      return createRouter(getIt<MediaScannerService>());
    } catch (e, st) {
      ErrorLogger.log('Router creation failed — bootstrap will retry',
          error: e, stackTrace: st, category: 'Startup');
      return null;
    }
  }

  /// Awaits the async singletons the UI resolves synchronously. A slow or
  /// partially failed warm-up paints a retry screen instead of crashing in
  /// build with an un-ready StateError.
  Future<void> _resolveDependencies() async {
    if (_bootstrapInFlight) return;
    _bootstrapInFlight = true;
    final ready = await ensureAppDependenciesReady();
    _bootstrapInFlight = false;
    if (!mounted) return;
    setState(() {
      _dependenciesReady = ready;
      _bootstrapFailed = !ready;
    });
  }

  void _retryBootstrap() {
    if (!mounted) return;
    setState(() {
      _bootstrapFailed = false;
      _router ??= _createRouterSafely();
    });
    if (!_dependenciesReady || _router == null) {
      unawaited(_resolveDependencies());
    }
  }

  /// Runtime "Pulsr Pure" guarantee: a Pure build must not carry the INTERNET
  /// permission. Ask the platform whether the merged manifest really omits it,
  /// and surface a loud error if a bad merge silently added network access.
  void _verifyPureMode() {
    if (!AppConfig.isPure) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final pure = await AppConfig.verifyPureNoInternet();
        if (pure == false) {
          ErrorLogger.log(
            'CRITICAL: Pulsr Pure build has INTERNET permission — purity check failed',
            category: 'Startup',
          );
          if (!mounted) return;
          final ctx = rootNavigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            PulsrToast.show(
              ctx,
              message:
                  'Pulsr Pure integrity check failed: this build can access the network.',
              icon: Icons.warning_amber_rounded,
              isError: true,
              duration: const Duration(seconds: 6),
            );
          }
        }
      } catch (e, st) {
        ErrorLogger.log('Pulsr Pure verification failed',
            error: e, stackTrace: st, category: 'Startup');
      }
    });
  }

  /// B-6: if the platform audio bridge failed to initialise, playback still
  /// works but the lock-screen / shade controls silently do not exist. Surface
  /// it once so the user is not left wondering where the media notification is.
  void _watchPlatformBridgeHealth() {
    try {
      if (!getIt.isRegistered<PulsrAudioHandler>()) return;
      final handler = getIt<PulsrAudioHandler>();
      void surface() {
        if (!handler.platformBridgeDegraded.value) return;
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        PulsrToast.show(
          ctx,
          message: 'Background media controls are unavailable on this launch. '
              'Playback works, but the lock-screen controls could not start.',
          icon: Icons.warning_amber_rounded,
          isError: true,
          duration: const Duration(seconds: 5),
        );
      }

      if (handler.platformBridgeDegraded.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) => surface());
      } else {
        handler.platformBridgeDegraded.addListener(surface);
        _platformBridgeDegradedListener = surface;
      }
    } catch (e, st) {
      // Best-effort diagnostic only; never let it block startup (e.g. a test
      // double of the handler that does not expose the notifier).
      ErrorLogger.log('Failed to watch platform bridge health',
          error: e, stackTrace: st, category: 'Startup');
    }
  }

  /// Watches output-device changes (Bluetooth/headphones) and fires the
  /// matching user automation rules. Charging is intentionally not wired: it
  /// is not reliably observable from Dart without a native change.
  void _startAutomationTriggers() {
    try {
      final service = AutomationTriggerService();
      _automationTriggerService = service;
      service.start();
    } catch (e, st) {
      ErrorLogger.log('Failed to start automation trigger service',
          error: e, stackTrace: st, category: 'Startup');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // No-op: locale is stable; avoid AssetManager thrash (LOG-16)
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Flush the debounced queue-slot write before the process can be killed.
      try {
        if (getIt.isRegistered<PlayerCubit>()) {
          unawaited(getIt<PlayerCubit>().persistQueueSlotsNow());
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to persist queue slots on detach',
            error: e, stackTrace: st, category: 'PulsrApp');
      }
    }
  }

  @override
  void didHaveMemoryPressure() {
    // Trim artwork and stream caches on GC pressure (LOG-14 14MB/59MB).
    // Clear only the in-memory bytes; the persistent disk cache is kept so a
    // transient memory warning does not force a full re-fetch + re-decode.
    try {
      getIt<ArtworkCacheManager>().trimMemoryForPressure();
    } catch (e, st) {
      ErrorLogger.log('Failed to trim artwork memory cache on memory pressure',
          error: e, stackTrace: st, category: 'PulsrApp');
    }
    try {
      // ignore: avoid_dynamic_calls
      (getIt.get<ArtworkLruCache>() as dynamic)?.trimForMemoryPressure();
    } catch (_) {
      // Fallback direct trim
      try {
        ArtworkLruCache().trimForMemoryPressure();
      } catch (e, st) {
        ErrorLogger.log('Failed direct trim for memory pressure',
            error: e, stackTrace: st, category: 'PulsrApp');
      }
    }
  }

  /// Surfaces a re-login prompt when the YouTube Music session dies mid-use
  /// (detected during stream resolution), instead of failing silently.
  void _listenForYtmSessionExpiry() {
    getIt.allReady().then((_) {
      if (!mounted) return;
      try {
        _authExpiredSub = getIt<YtmService>().onAuthExpired.listen((_) {
          if (!mounted) return;
          final now = DateTime.now();
          final last = _lastAuthExpiredPrompt;
          if (last != null && now.difference(last).inSeconds < 15) return;
          _lastAuthExpiredPrompt = now;

          final ctx = rootNavigatorKey.currentContext;
          if (ctx == null || !ctx.mounted) return;
          ScaffoldMessenger.of(ctx)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(context.l10n.ytmSessionExpired),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: ctx.l10n.signIn,
                  onPressed: () => YtmWebLoginSheet.show(ctx),
                ),
              ),
            );
        });
      } catch (e, st) {
        ErrorLogger.log('Failed to listen for Ytm session expiry',
            error: e, stackTrace: st, category: 'PulsrApp');
      }
    });
  }

  void _startNetworkChangeMonitor() {
    getIt.allReady().then((_) {
      if (!mounted) return;
      try {
        final monitor = NetworkChangeMonitor();
        _networkMonitor = monitor;
        monitor.start();
        _networkChangeSub = monitor.onNetworkChanged.listen((_) async {
          ErrorLogger.log('Network path changed — invalidating YTM caches',
              category: 'PulsrApp');
          try {
            if (getIt.isRegistered<YtmService>()) {
              await getIt<YtmService>().handleNetworkChange();
            }
          } catch (e, st) {
            ErrorLogger.log('Failed handling network change in YtmService',
                error: e, stackTrace: st, category: 'PulsrApp');
          }
          try {
            if (getIt.isRegistered<PulsrAudioHandler>()) {
              getIt<PulsrAudioHandler>().clearNetworkCaches();
            }
          } catch (e, st) {
            ErrorLogger.log('Failed clearing audio handler network caches',
                error: e, stackTrace: st, category: 'PulsrApp');
          }
        });
      } catch (e, st) {
        ErrorLogger.log('Failed to start network change monitor',
            error: e, stackTrace: st, category: 'PulsrApp');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authExpiredSub?.cancel();
    _networkChangeSub?.cancel();
    _networkMonitor?.dispose();
    _automationTriggerService?.dispose();
    if (_platformBridgeDegradedListener != null &&
        getIt.isRegistered<PulsrAudioHandler>()) {
      getIt<PulsrAudioHandler>()
          .platformBridgeDegraded
          .removeListener(_platformBridgeDegradedListener!);
    }
    super.dispose();
  }

  void _checkInitialAudioIntent() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await getIt<FileIntentHandler>().checkInitialUri();
      } catch (e, st) {
        if (!mounted) return;
        ErrorLogger.log('Failed to process initial audio intent on startup',
            error: e, stackTrace: st, category: 'Startup');
      }
    });
  }

  void _autoScanOnStartup() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final scanner = getIt<MediaScannerService>();
        await RestoreDetectionService.checkAndHandleRestore(scanner);
        if (!mounted) return;
        final hasPermission = await scanner.checkPermission();
        if (hasPermission && mounted) {
          final repo = getIt<IMusicRepository>();
          final songsRes = await repo.getAllSongs(limit: 1);
          final hasSongs = songsRes.fold((l) => false, (r) => r.isNotEmpty);
          if (!hasSongs && mounted) {
            final settingsCubit = getIt<SettingsCubit>();
            await settingsCubit.rescanLibrary();
          }
        }
      } catch (e, st) {
        if (!mounted) return;
        ErrorLogger.log('Failed to execute automatic startup media scan',
            error: e, stackTrace: st, category: 'Startup');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = _router;
    if (!_dependenciesReady || router == null) {
      return _DependencyBootstrapScreen(
        failed: _bootstrapFailed || (router == null && _dependenciesReady),
        onRetry: _retryBootstrap,
      );
    }
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: getIt<AppDatabase>()),
        RepositoryProvider<IMusicRepository>.value(
            value: getIt<IMusicRepository>()),
        RepositoryProvider<PulsrAudioHandler>.value(
            value: getIt<PulsrAudioHandler>()),
        RepositoryProvider<MediaScannerService>.value(
            value: getIt<MediaScannerService>()),
        RepositoryProvider<GetSongsUseCase>.value(
            value: getIt<GetSongsUseCase>()),
        RepositoryProvider<GetAlbumsUseCase>.value(
            value: getIt<GetAlbumsUseCase>()),
        RepositoryProvider<GetArtistsUseCase>.value(
            value: getIt<GetArtistsUseCase>()),
        RepositoryProvider<GetFavoritesUseCase>.value(
            value: getIt<GetFavoritesUseCase>()),
        RepositoryProvider<ToggleFavoriteUseCase>.value(
            value: getIt<ToggleFavoriteUseCase>()),
        RepositoryProvider<SearchMusicUseCase>.value(
            value: getIt<SearchMusicUseCase>()),
        RepositoryProvider<PlaylistUseCases>.value(
            value: getIt<PlaylistUseCases>()),
        RepositoryProvider<FolderUseCases>.value(
            value: getIt<FolderUseCases>()),
        RepositoryProvider<WidgetService>.value(value: getIt<WidgetService>()),
        RepositoryProvider<IDownloadRepository>.value(
            value: getIt<IDownloadRepository>()),
      ],
      child: MultiBlocProvider(
        providers: [
          // getIt singletons are provided by value: `create:` would make the
          // provider close the shared instance on teardown, leaving getIt
          // handing out a dead cubit for the rest of the process.
          BlocProvider<DynamicThemeCubit>.value(
            value: getIt<DynamicThemeCubit>(),
          ),
          BlocProvider<PlayerCubit>.value(
            value: getIt<PlayerCubit>(),
          ),
          BlocProvider<LibraryCubit>(
            create: (_) => getIt<LibraryCubit>(),
          ),
          BlocProvider<SearchCubit>(
            create: (_) => getIt<SearchCubit>(),
          ),
          BlocProvider<PlaylistCubit>(
            create: (_) => getIt<PlaylistCubit>(),
          ),
          BlocProvider<SettingsCubit>.value(
            value: getIt<SettingsCubit>(),
          ),
          BlocProvider<AuthCubit>(
            create: (_) => getIt<AuthCubit>(),
          ),
          BlocProvider<DownloadsCubit>.value(
            value: getIt<DownloadsCubit>(),
          ),
          if (AppConfig.ytmEnabled)
            BlocProvider<YtmDownloadCubit>.value(
              value: getIt<YtmDownloadCubit>(),
            ),
        ],
        child: MultiBlocListener(
          listeners: [
            BlocListener<PlayerCubit, PlayerState>(
              listenWhen: (prev, curr) =>
                  prev.currentSong?.id != curr.currentSong?.id,
              listener: (context, state) {
                final song = state.currentSong;
                final source =
                    context.read<SettingsCubit>().state.themeColorSource;
                // Keep the album-art palette fresh for the artwork source and
                // for system (used as the pre-Android-12 fallback seed).
                if (source == ThemeColorSource.artwork ||
                    source == ThemeColorSource.system) {
                  if (song != null) {
                    context.read<DynamicThemeCubit>().updateFromSong(song);
                  } else {
                    context.read<DynamicThemeCubit>().resetToDefault();
                  }
                }
              },
            ),
            BlocListener<SettingsCubit, SettingsState>(
              listenWhen: (prev, curr) =>
                  prev.themeColorSource != curr.themeColorSource,
              listener: (context, state) {
                final usesArt =
                    state.themeColorSource == ThemeColorSource.artwork ||
                        state.themeColorSource == ThemeColorSource.system;
                if (usesArt) {
                  final song = context.read<PlayerCubit>().state.currentSong;
                  if (song != null) {
                    context.read<DynamicThemeCubit>().updateFromSong(song);
                  }
                } else {
                  context.read<DynamicThemeCubit>().resetToDefault();
                }
              },
            ),
            // App-level surface for transport failures: PlayerCubit writes the
            // message to PlayerState.errorMessage, so without this every
            // seek/skip/shuffle/repeat failure would be silent (A-10).
            BlocListener<PlayerCubit, PlayerState>(
              listenWhen: (prev, curr) =>
                  curr.errorMessage != null &&
                  curr.errorMessage != prev.errorMessage,
              listener: (context, state) {
                final message = state.errorMessage;
                if (message != null) {
                  // rootNavigatorKey.currentContext is the Navigator itself,
                  // whose Overlay is a *child* — Overlay.of(navigatorContext)
                  // throws. Use the overlay's own context instead.
                  final overlayCtx =
                      rootNavigatorKey.currentState?.overlay?.context;
                  if (overlayCtx != null && overlayCtx.mounted) {
                    PulsrToast.show(
                      overlayCtx,
                      message: resolveUiErrorMessage(context, message),
                      icon: Icons.error_outline_rounded,
                      isError: true,
                    );
                  }
                }
                context.read<PlayerCubit>().clearError();
              },
            ),
          ],
          child: BlocSelector<
              SettingsCubit,
              SettingsState,
              ({
                ThemeColorSource colorSource,
                AppThemeMode themeMode,
                Color customAccent,
                String languageCode,
                bool highContrast,
                bool reduceMotion,
                bool dimWhitePoint
              })>(
            selector: (state) => (
              colorSource: state.themeColorSource,
              themeMode: state.themeMode,
              customAccent: state.customAccentColor,
              languageCode: state.languageCode,
              highContrast: state.highContrast,
              reduceMotion: state.reduceMotion,
              dimWhitePoint: state.dimWhitePoint,
            ),
            builder: (context, settingsConfig) {
              return BlocSelector<DynamicThemeCubit, DynamicThemeState,
                  ({Color primaryColor, bool hasCustomArtwork})>(
                selector: (state) => (
                  primaryColor: state.primaryColor,
                  hasCustomArtwork: state.hasCustomArtworkColor,
                ),
                builder: (context, dynamicThemeConfig) {
                  return DynamicColorBuilder(
                    builder: (lightDynamic, darkDynamic) {
                      // Resolve the accent seed per brightness.
                      Color resolveAccent(Color? dynamicPrimary) {
                        switch (settingsConfig.colorSource) {
                          case ThemeColorSource.system:
                            if (dynamicPrimary != null) {
                              return dynamicPrimary;
                            }
                            return dynamicThemeConfig.hasCustomArtwork
                                ? dynamicThemeConfig.primaryColor
                                : settingsConfig.customAccent;
                          case ThemeColorSource.artwork:
                            return dynamicThemeConfig.primaryColor;
                          case ThemeColorSource.custom:
                            return settingsConfig.customAccent;
                        }
                      }

                      final isHighContrast = settingsConfig.highContrast ||
                          MediaQuery.highContrastOf(context);
                      final isBoldText = MediaQuery.boldTextOf(context);

                      final lightTheme = isHighContrast
                          ? AuraTheme.highContrastThemeFor(Brightness.light,
                              seed: resolveAccent(lightDynamic?.primary))
                          : AuraTheme.customTheme(
                              resolveAccent(lightDynamic?.primary),
                              brightness: Brightness.light,
                              isBoldText: isBoldText,
                            );

                      final darkTheme = isHighContrast
                          ? AuraTheme.highContrastThemeFor(Brightness.dark,
                              seed: resolveAccent(darkDynamic?.primary))
                          : AuraTheme.customTheme(
                              resolveAccent(darkDynamic?.primary),
                              brightness: Brightness.dark,
                              isAmoled: settingsConfig.themeMode ==
                                  AppThemeMode.amoled,
                              isBoldText: isBoldText,
                              dimWhitePoint: settingsConfig.dimWhitePoint,
                            );

                      final ThemeMode flutterThemeMode;
                      switch (settingsConfig.themeMode) {
                        case AppThemeMode.light:
                          flutterThemeMode = ThemeMode.light;
                          break;
                        case AppThemeMode.dark:
                        case AppThemeMode.amoled:
                          flutterThemeMode = ThemeMode.dark;
                          break;
                        case AppThemeMode.system:
                          flutterThemeMode = ThemeMode.system;
                          break;
                      }

                      final isDarkTheme = isHighContrast ||
                          flutterThemeMode == ThemeMode.dark ||
                          (flutterThemeMode == ThemeMode.system &&
                              MediaQuery.platformBrightnessOf(context) ==
                                  Brightness.dark);

                      return AnnotatedRegion<SystemUiOverlayStyle>(
                        value: SystemUiOverlayStyle(
                          statusBarColor: Colors.transparent,
                          statusBarIconBrightness:
                              isDarkTheme ? Brightness.light : Brightness.dark,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarIconBrightness:
                              isDarkTheme ? Brightness.light : Brightness.dark,
                        ),
                        child: MaterialApp.router(
                          title: AppConfig.appTitle,
                          debugShowCheckedModeBanner: false,
                          restorationScopeId: 'pulsr',
                          themeMode: flutterThemeMode,
                          theme: lightTheme,
                          darkTheme: darkTheme,
                          builder: (context, child) {
                            // Expose the active localizations to non-widget code
                            // (cubits/services) via L10nHolder.
                            L10nHolder.current = AppLocalizations.of(context);
                            // Honour both the in-app toggle and the OS
                            // "Reduce motion" / "Remove animations" setting.
                            // Overriding `disableAnimations` here makes every
                            // `PulsrMotion` call site collapse app-wide without
                            // each widget reading settings directly.
                            final media = MediaQuery.of(context);
                            final reduceMotion = settingsConfig.reduceMotion ||
                                media.disableAnimations;
                            return MediaQuery(
                              data: media.copyWith(
                                disableAnimations: reduceMotion,
                              ),
                              child: MediaQuery.withClampedTextScaling(
                                // Accessibility: allow the full OS text-size
                                // range (up to 200%). Fixed-height text boxes
                                // on key surfaces scale via
                                // MediaQuery.textScalerOf so nothing clips.
                                minScaleFactor: 0.8,
                                maxScaleFactor: 2.0,
                                child: _AppOrientationSystemUiObserver(
                                  child: child ?? const SizedBox.shrink(),
                                ),
                              ),
                            );
                          },
                          locale: settingsConfig.languageCode == 'system'
                              ? null
                              : Locale(settingsConfig.languageCode),
                          localizationsDelegates: const [
                            AppLocalizations.delegate,
                            GlobalMaterialLocalizations.delegate,
                            GlobalWidgetsLocalizations.delegate,
                            GlobalCupertinoLocalizations.delegate,
                          ],
                          supportedLocales: AppLocalizations.supportedLocales,
                          routerConfig: router,
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Global system UI observer mounted in [MaterialApp.builder] to ensure all
/// screens across the entire application remain in immersive full-screen mode
/// in landscape orientation (hiding status and navigation letterbox bars),
/// and gracefully return to edge-to-edge with transparent system bars in portrait.
class _AppOrientationSystemUiObserver extends StatefulWidget {
  final Widget child;
  const _AppOrientationSystemUiObserver({required this.child});

  @override
  State<_AppOrientationSystemUiObserver> createState() =>
      _AppOrientationSystemUiObserverState();
}

class _AppOrientationSystemUiObserverState
    extends State<_AppOrientationSystemUiObserver> with WidgetsBindingObserver {
  Orientation? _lastOrientation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (orientation != _lastOrientation) {
      _lastOrientation = orientation;
      _applySystemUi(orientation);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _lastOrientation != null) {
      _applySystemUi(_lastOrientation!);
    }
  }

  void _applySystemUi(Orientation orientation) {
    if (orientation == Orientation.landscape) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
          systemStatusBarContrastEnforced: false,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Blocking screen shown when the build's flavor/environment configuration is
/// invalid (e.g. a Play Store build shipping YTM flags). The app must not
/// start with an illegal configuration, so this is terminal — not recoverable.
class PulsrConfigurationErrorApp extends StatelessWidget {
  final String title;
  final String message;

  const PulsrConfigurationErrorApp({
    super.key,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 52, color: Colors.redAccent),
                const SizedBox(height: 18),
                Text(
                  context.l10n.bootConfigurationError,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Recoverable boot/retry screen rendered while the async DI singletons the
/// shell needs are still warming up (or after a warm-up failure). Prevents the
/// un-ready-StateError crash that previously black-screened slow cold starts.
class _DependencyBootstrapScreen extends StatelessWidget {
  final bool failed;
  final VoidCallback onRetry;

  const _DependencyBootstrapScreen({
    required this.failed,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!failed)
                  const CircularProgressIndicator()
                else ...[
                  const Icon(Icons.refresh_rounded,
                      size: 48, color: Colors.white70),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.bootStartupFailed,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.bootStartupFailedMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13.5, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onRetry,
                    child: Text(context.l10n.retry),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

```

### Dependency Injection Graph (`lib/core/di/injection.dart`)
**Registered Singletons & Services:**
- `LyricsRepository`
- `AppUpdateService`
- `DownloadService`
- `DiscordRpcService`
- `SpotifyImporterService`

**Pre-warmed Singletons (Async Initialization):**
- `T`
- `PlayerCubit`

---

## 4. Domain Interfaces & Repositories
### `lib/domain/interfaces/artwork_resolver_interface.dart`
```dart
  abstract class IArtworkResolver {
  void putCachedArtwork(String key, Uint8List bytes);
  void clearCache();
```

### `lib/domain/interfaces/lyrics_provider_interface.dart`
```dart
  abstract class ILyricsProvider {
```

### `lib/domain/interfaces/proxy_applier_interface.dart`
```dart
  abstract class IProxyApplier {
```

### `lib/domain/interfaces/scrobble_sink_interface.dart`
```dart
  abstract class IScrobbleSink {
  void notifyPlaybackState({
```

### `lib/domain/interfaces/widget_pusher_interface.dart`
```dart
  abstract class IWidgetPusher {
```

### `lib/domain/repositories/download_repository_interface.dart`
```dart
  abstract class IDownloadRepository {
```

### `lib/domain/repositories/music_repository_interface.dart`
```dart
  abstract class IMusicRepository {
  return watchAllSongs().map((result) => result.map((songs) => songs
  String _normalizeDir(String path) =>
  String _parentDir(String path) {
  class FolderSongEntry {
  const FolderSongEntry({
```

### `lib/domain/repositories/smart_playlist_engine_interface.dart`
```dart
  abstract class ISmartPlaylistEngine {
```

---

## 5. Go Listen-Together Party Server

### `server/pulsr_party/go.mod`
```go
module github.com/pulsr-audio/pulsr/server/party

go 1.26

require github.com/gorilla/websocket v1.5.3 // indirect

```

### `server/pulsr_party/protocol/protocol.go`
```go
package protocol

import (
	"errors"
	"strings"
)

// ProtocolVersion indicates the active wire protocol version.
// Clients send version in frames; servers accept older versions compatibly.
const ProtocolVersion = 1

// Server -> Client frame types
const (
	FrameWelcome = "welcome"
	FrameState   = "state"
	FrameQueue   = "queue"
	FrameMembers = "members"
	FramePong    = "pong"
	FrameError   = "error"
	FrameBye     = "bye"
	FrameActivity = "activity"
)

// Client -> Server frame types
const (
	FramePing      = "ping"
	FrameControl   = "control"
	FrameSync      = "sync"
	FrameSyncQueue = "syncQueue"
	FrameReport    = "report"
)

// Control actions
const (
	ActionPlay        = "play"
	ActionPause       = "pause"
	ActionSeek        = "seek"
	ActionSetTrack    = "setTrack"
	ActionSetQueue    = "setQueue"
	ActionQueueAdd    = "queueAdd"
	ActionQueueRemove = "queueRemove"
	ActionQueueClear  = "queueClear"
	ActionQueueMove   = "queueMove"
	ActionNext        = "next"
	ActionPrevious    = "previous"
	ActionKick        = "kick"
	ActionSetMaxMembers = "setMaxMembers"
	ActionSetAutoplay = "setAutoplay"
	ActionSetHostOnlyControl = "setHostOnlyControl"
)

// ControlActions are the actions a party's HostOnlyControl setting restricts to
// the host. Membership actions are not here: kick and setMaxMembers are already
// host-only unconditionally, and setHostOnlyControl has to stay reachable by
// the host to be turned back off.
var ControlActions = map[string]bool{
	ActionPlay:        true,
	ActionPause:       true,
	ActionSeek:        true,
	ActionSetTrack:    true,
	ActionSetQueue:    true,
	ActionQueueAdd:    true,
	ActionQueueRemove: true,
	ActionQueueClear:  true,
	ActionQueueMove:   true,
	ActionNext:        true,
	ActionPrevious:    true,
	ActionSetAutoplay: true,
}

// JoinRequest is the identity submitted when creating or joining a party.
type JoinRequest struct {
	UserId      string  `json:"userId"`
	DeviceId    string  `json:"deviceId"`
	DisplayName string  `json:"displayName"`
	AvatarUrl   *string `json:"avatarUrl,omitempty"`
	MaxMembers  *int    `json:"maxMembers,omitempty"`
	AutoplayEnabled *bool `json:"autoplayEnabled,omitempty"`
}

// Validate ensures all required identity fields are present and safe.
func (r *JoinRequest) Validate() error {
	r.UserId = strings.TrimSpace(r.UserId)
	if r.UserId == "" || len(r.UserId) > 128 {
		return errors.New("userId must be between 1 and 128 characters")
	}

	r.DeviceId = strings.TrimSpace(r.DeviceId)
	if r.DeviceId == "" || len(r.DeviceId) > 128 {
		return errors.New("deviceId must be between 1 and 128 characters")
	}

	r.DisplayName = strings.TrimSpace(r.DisplayName)
	if r.DisplayName == "" || len(r.DisplayName) > 80 {
		return errors.New("displayName must be between 1 and 80 characters")
	}

	if r.AvatarUrl != nil {
		trimmed := strings.TrimSpace(*r.AvatarUrl)
		if trimmed == "" {
			r.AvatarUrl = nil
		} else if len(trimmed) > 1000 {
			return errors.New("avatarUrl must not exceed 1000 characters")
		} else if !strings.HasPrefix(trimmed, "http://") && !strings.HasPrefix(trimmed, "https://") {
			return errors.New("avatarUrl must be an http(s) URL")
		} else {
			r.AvatarUrl = &trimmed
		}
	}
	if r.MaxMembers != nil && (*r.MaxMembers < 2 || *r.MaxMembers > 10) {
		return errors.New("maxMembers must be between 2 and 10")
	}
	return nil
}

```
