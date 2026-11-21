import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../constants/channels.dart';
import '../utils/error_logger.dart';

enum AppEnvironment { dev, prod }

class AppConfig {
  static const String envName =
      String.fromEnvironment('ENV', defaultValue: 'dev');
  static const String sentryDsn =
      String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  static const String flavor =
      String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  /// Encrypt the library database at rest (ADR 015). Requires an
  /// encryption-capable SQLite build; when absent the bootstrap degrades to
  /// plaintext and reports it in the database health check.
  static const bool databaseEncryptionEnabled =
      bool.fromEnvironment('PULSR_DB_ENCRYPTION', defaultValue: true);
  static const String _buildTimeVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '');
  static String _installedVersion = '1.0.0';

  /// Installed package version. Resolved from the platform manifest at
  /// startup so release builds do not compare against a stale constant (the
  /// updater would otherwise re-offer the version already installed).
  static String get appVersion => _installedVersion;
  static const String developerName = 'Eslam Mahmoud';

  /// Reads the real versionName/CFBundleShortVersionString. A build-time
  /// [APP_VERSION] define wins so tests and CI can pin it.
  static Future<void> loadInstalledVersion() async {
    if (_buildTimeVersion.isNotEmpty) {
      _installedVersion = _buildTimeVersion;
      return;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) _installedVersion = info.version;
    } catch (e, st) {
      ErrorLogger.log('Failed to read installed app version',
          error: e, stackTrace: st, category: 'AppConfig');
    }
  }

  static const String _rawEnableYtm = String.fromEnvironment('ENABLE_YTM');
  static const String _rawYtm = String.fromEnvironment('YTM');
  static const String _rawYtmEnabled = String.fromEnvironment('YTM_ENABLED');
  static const String _rawLowerYtm = String.fromEnvironment('ytm');
  static const String _rawDashYtm = String.fromEnvironment('-ytm');
  static const String _rawDoubleDashYtm = String.fromEnvironment('--ytm');
  static const String _rawLowerFlavor = String.fromEnvironment('flavor');

  static const String _rawYtmDefine = _rawEnableYtm != ''
      ? _rawEnableYtm
      : _rawYtm != ''
          ? _rawYtm
          : _rawYtmEnabled != ''
              ? _rawYtmEnabled
              : _rawLowerYtm != ''
                  ? _rawLowerYtm
                  : _rawDashYtm != ''
                      ? _rawDashYtm
                      : _rawDoubleDashYtm;

  /// Pure alias parser mirroring the compile-time [ytmEnabled] expression.
  /// Documents all supported flag values including the legacy misspelling
  /// `'enebeld'`.
  @visibleForTesting
  static bool parseYtmEnabled(String flagValue, {String flavorValue = ''}) {
    final normalizedFlag = flagValue.trim().toLowerCase();
    if (normalizedFlag == 'true' ||
        normalizedFlag == '1' ||
        normalizedFlag == 'enabled' ||
        // Legacy misspelling alias kept for backwards compatibility.
        normalizedFlag == 'enebeld') {
      return true;
    }
    if (normalizedFlag.isNotEmpty) return false;
    return flavorValue.trim().toLowerCase() == 'ytm';
  }

  /// YouTube Music search/stream/download. Off by default so Play Store builds
  /// never expose it; enable with `--dart-define=ENABLE_YTM=true`.
  ///
  /// Being a `const false` lets Dart tree-shake the guarded branches, but the
  /// generated DI config still imports every service, so this is not a
  /// guarantee that no YouTube code reaches the binary.
  static const bool ytmEnabled = _rawYtmDefine == 'true' ||
      _rawYtmDefine == '1' ||
      _rawYtmDefine == 'enabled' ||
      // Legacy misspelling alias kept for backwards compatibility with scripts.
      _rawYtmDefine == 'enebeld' ||
      (_rawYtmDefine == '' && (flavor == 'ytm' || _rawLowerFlavor == 'ytm'));

  /// In-app voice search. There is no on-device speech recognizer wired up, so
  /// the mic affordance is hidden entirely unless this is explicitly enabled
  /// (which requires a speech-to-text dependency). The Android assistant /
  /// external `pulsr://voice-search` entry points are unaffected and always
  /// handled by [FileIntentHandler.handleVoiceSearch].
  static const bool voiceSearchEnabled =
      bool.fromEnvironment('ENABLE_VOICE_SEARCH', defaultValue: false);

  /// Flavor the installed binary was actually built with.
  ///
  /// `String.fromEnvironment('FLAVOR')` defaults to `dev` when CI forgets the
  /// define, which made a `--flavor prod` Pure build run network code with the
  /// INTERNET permission stripped. Flutter populates `appFlavor` from the
  /// Gradle product flavor, so prefer it when available.
  static String get effectiveFlavor {
    final platformFlavor = appFlavor;
    if (platformFlavor != null && platformFlavor.isNotEmpty) {
      return platformFlavor.toLowerCase();
    }
    return flavor.toLowerCase();
  }

  static AppEnvironment get environment {
    final lowerFlavor = effectiveFlavor;
    if (lowerFlavor == 'prod') {
      return AppEnvironment.prod;
    }
    switch (envName.toLowerCase()) {
      case 'prod':
      case 'production':
        return AppEnvironment.prod;
      case 'dev':
      case 'development':
      default:
        return AppEnvironment.dev;
    }
  }

  static bool get isProd => environment == AppEnvironment.prod;
  static bool get isDev => environment == AppEnvironment.dev;

  /// Pulsr Pure: Play Store offline-only build. No INTERNET permission
  /// (see android/app/src/prod/AndroidManifest.xml), no YTM, no Firebase,
  /// no Sentry, no cloud sync — competes with Musicolet on manifest privacy.
  static bool get isPure => isProd && !ytmEnabled;

  /// Runtime Pure check: asks the platform whether the INTERNET permission
  /// is present in the merged manifest, so a bad manifest merge can't
  /// silently ship network access in a Pure build. Returns null off Android,
  /// when the native hook is absent, or on error (treat as "unknown").
  static Future<bool?> verifyPureNoInternet() async {
    if (!isPure) return false;
    try {
      const channel = MethodChannel(PulsrChannels.purity);
      final bool? hasInternet =
          await channel.invokeMethod<bool>('hasInternetPermission');
      if (hasInternet == null) return null;
      return !hasInternet;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Telemetry (Sentry/Firebase) is only allowed outside Pure builds and
  /// only when a DSN is actually configured (main.dart already gates on this).
  static bool get isTelemetryAllowed => !isPure && sentryDsn.isNotEmpty;

  /// Cloud sync / remote metadata fetch must be hard-off in Pure builds even
  /// if stale prefs say otherwise.
  static bool get isCloudSyncAllowed => !isPure;

  static String get appTitle {
    final lowerFlavor = effectiveFlavor;
    if (lowerFlavor == 'ytm' || ytmEnabled) {
      return 'Pulsr Music';
    }
    if (isProd) return 'Pulsr Music';
    // B-08 single source of truth: dev flavor's native label is "Pulsr Plus" (app/build.gradle.kts)
    // Align Dart title so launcher + in-app branding match. Prod stays "Pulsr Music".
    if (lowerFlavor == 'dev') return 'Pulsr Plus';
    return isProd ? 'Pulsr Music' : 'Pulsr Plus';
  }

  /// Validates that build flavor and runtime environment configuration are aligned.
  static void validateConfiguration() {
    final lowerFlavor = effectiveFlavor;
    if (const bool.hasEnvironment('ENV') &&
        lowerFlavor == 'prod' &&
        envName.toLowerCase() == 'dev') {
      throw StateError('CRITICAL: Production flavor cannot run with ENV=dev');
    }
    if (envName.toLowerCase() == 'prod' && lowerFlavor == 'dev') {
      ErrorLogger.log(
        'Warning: Running flavor "dev" with ENV=prod. Features may behave as production in development build.',
        category: 'AppConfig',
      );
    }
    // Play Store compliance: the dedicated "prod" flavor MUST NOT have YouTube Music enabled
    if (lowerFlavor == 'prod' && ytmEnabled) {
      throw StateError(
        'CRITICAL: Production Play Store builds (flavor "prod") must not enable YouTube Music features (ENABLE_YTM=true). Use flavor "ytm" for YTM builds.',
      );
    }
    if ((lowerFlavor == 'dev' || lowerFlavor == 'ytm') && !ytmEnabled) {
      ErrorLogger.log(
        'Flavor is "$effectiveFlavor" (native NewPipe bridge compiled) but Dart gate ENABLE_YTM is false. Run with --dart-define=ENABLE_YTM=true to activate YTM features.',
        category: 'AppConfig',
      );
    }
  }
}
