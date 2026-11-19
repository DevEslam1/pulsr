// lib/features/extras/presentation/extras_screen.dart
//
// "Tools & extras" hub. Every feature added to close the parity gaps gets one
// row here, so Settings stays a settings screen instead of a feature dump.
//
// The hub owns the process-wide instances of the services these tools need
// (profiles, diagnostics, safe mode, USB quirks, TTS). Each screen still
// accepts an injected service, so the tools stay independently testable.

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/error_logger.dart';
import '../../announcements/announcement_screen.dart';
import '../../announcements/announcement_settings.dart';
import '../../announcements/tts_engine.dart';
import '../../assistant/assistant_settings.dart';
import '../../assistant/assistant_settings_screen.dart';
import '../../audio_profiles/audio_profile_service.dart';
import '../../audio_profiles/audio_profiles_screen.dart';
import '../../diagnostics/diagnostics_bundle_service.dart';
import '../../diagnostics/diagnostics_screen.dart';
import '../../diagnostics/safe_mode_controller.dart';
import '../../dlna/dlna_renderer_service.dart';
import '../../dlna/dlna_screen.dart';
import '../../remote_sources/remote_sources_screen.dart';
import '../../../data/db/app_database.dart' show SongSource, SongsTableData;
import '../../../domain/models/remote_source.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../../settings/presentation/widgets/settings_tiles.dart';
import '../../system_behavior/system_behavior_screen.dart';
import '../../system_behavior/system_behavior_settings.dart';
import '../../usb_tools/usb_ergonomics_screen.dart';
import '../../usb_tools/usb_ergonomics_service.dart';
import '../../usb_tools/usb_quirk_store.dart';
import '../remote_playback_runtime.dart';
import 'extras_strings.dart';

/// Hub for the parity-gap tools that do not belong inside one settings category
/// (announcements, system behaviour, USB ergonomics, network/DLNA output,
/// profiles and diagnostics).
class ExtrasScreen extends StatefulWidget {
  const ExtrasScreen({super.key, this.debugToolErrors, this.debugFailInits});

  /// Seeds per-tool initialization failures. Test-only: production always
  /// discovers failures in [_load].
  @visibleForTesting
  final Map<ExtrasTool, String>? debugToolErrors;

  /// Tools whose real initialization must throw, exercising the per-tool
  /// try/catch isolation in [_load] instead of seeding the result map.
  @visibleForTesting
  final Set<ExtrasTool>? debugFailInits;

  @override
  State<ExtrasScreen> createState() => _ExtrasScreenState();
}

class _ExtrasScreenState extends State<ExtrasScreen> {
  AudioProfileService? _profiles;
  DiagnosticsBundleService? _diagnostics;
  SafeModeController? _safeMode;
  AnnouncementSettings? _announcements;
  MethodChannelTtsEngine? _ttsEngine;
  AssistantSettings? _assistantSettings;
  SystemBehaviorSettings? _systemBehavior;
  UsbErgonomicsService? _usbErgonomics;
  RemotePlaybackRuntime? _remoteRuntime;
  bool _ownsSystemBehavior = false;
  bool _ownsUsbErgonomics = false;
  bool _ownsSafeMode = false;
  bool _ownsRemoteRuntime = false;
  bool _loading = true;
  String? _loadError;

  /// Tools whose initialization failed, with the inline message their row
  /// shows. A tool listed here has its row disabled; every other row stays
  /// usable (one broken service cannot blank the whole hub).
  late final Map<ExtrasTool, String> _toolErrors =
      Map<ExtrasTool, String>.from(widget.debugToolErrors ?? const <ExtrasTool, String>{});

  /// Subtitle for [tool]: its inline error when it failed, else [fallback].
  String _subtitleFor(ExtrasTool tool, String fallback) =>
      _toolErrors[tool] ?? fallback;

  /// Whether [tool] initialized successfully.
  bool _ready(ExtrasTool tool) => !_toolErrors.containsKey(tool);

  @override
  void initState() {
    super.initState();
    if (widget.debugToolErrors != null) {
      // Test-only: the seeded map stands in for the initialization pass, so the
      // row-rendering contract can be asserted without booting every service.
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e, st) {
      // Without preferences no tool can start, so this stays the one fatal
      // failure; everything below is isolated per tool.
      ErrorLogger.log(
        'Extras tools could not read their preferences',
        error: e,
        stackTrace: st,
        category: 'Extras',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = ExtrasStrings.loadFailed;
      });
      return;
    }

    // Each tool initializes on its own: a tool whose service throws disables
    // only its row and shows its inline error, while every other row stays
    // usable. Skipping this isolation meant one broken service blanked the hub.
    await Future.wait<void>(<Future<void>>[
      _initProfiles(prefs),
      _initDiagnostics(prefs),
      _initSafeMode(prefs),
      _initSystemBehavior(),
      _initUsb(prefs),
      _initAnnouncements(),
      _initAssistant(),
    ]);

    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// Throws when a test asked this tool's real initialization to fail.
  void _maybeDebugFail(ExtrasTool tool) {
    if (widget.debugFailInits?.contains(tool) ?? false) {
      throw StateError('Injected $tool initialization failure');
    }
  }

  /// Records a failed tool and disables its row.
  void _failTool(    ExtrasTool tool,
    String label,
    Object error,
    StackTrace stackTrace,
  ) {
    ErrorLogger.log(
      'Extras tool failed to initialize: $label',
      error: error,
      stackTrace: stackTrace,
      category: 'Extras',
    );
    if (!mounted) return;
    setState(() => _toolErrors[tool] = ExtrasStrings.toolUnavailable);
  }

  Future<void> _initProfiles(SharedPreferences prefs) async {
    try {
      _maybeDebugFail(ExtrasTool.profiles);
      final profiles = AudioProfileService(prefs: prefs);
      if (!mounted) return;
      setState(() => _profiles = profiles);
    } catch (e, st) {
      _failTool(ExtrasTool.profiles, 'profiles', e, st);
    }
  }

  Future<void> _initDiagnostics(SharedPreferences prefs) async {
    try {
      _maybeDebugFail(ExtrasTool.diagnostics);
      final diagnostics = DiagnosticsBundleService(
        prefs: prefs,
        outputDevice: _outputDeviceSnapshot,
      );
      if (!mounted) return;
      setState(() => _diagnostics = diagnostics);
    } catch (e, st) {
      _failTool(ExtrasTool.diagnostics, 'diagnostics', e, st);
    }
  }

  Future<void> _initSafeMode(SharedPreferences prefs) async {
    SafeModeController? owned;
    try {
      _maybeDebugFail(ExtrasTool.safeMode);
      // The audio handler publishes the app-scoped controller so the failure
      // streak and the manual Enter/Exit controls share one active-device map.
      final owns = !getIt.isRegistered<SafeModeController>();
      final safeMode = owns
          ? (owned = SafeModeController(prefs: prefs))
          : getIt<SafeModeController>();
      if (!mounted) {
        if (owns) await owned?.dispose();
        return;
      }
      setState(() {
        _safeMode = safeMode;
        _ownsSafeMode = owns;
      });
    } catch (e, st) {
      _failTool(ExtrasTool.safeMode, 'safe mode', e, st);
    }
  }

  Future<void> _initSystemBehavior() async {
    SystemBehaviorSettings? owned;
    try {
      _maybeDebugFail(ExtrasTool.systemBehavior);
      // Reuse the app-level instance started with the audio handler; only build
      // a private one when the bootstrap has not published it (tests, early
      // navigation). Ownership follows creation so nothing is disposed twice.
      final owns = !getIt.isRegistered<SystemBehaviorSettings>();
      final behavior = owns
          ? (owned = SystemBehaviorSettings())
          : getIt<SystemBehaviorSettings>();
      if (owns) await behavior.load();
      if (!mounted) {
        if (owns) owned?.dispose();
        return;
      }
      setState(() {
        _systemBehavior = behavior;
        _ownsSystemBehavior = owns;
      });
    } catch (e, st) {
      _failTool(ExtrasTool.systemBehavior, 'system behavior', e, st);
    }
  }

  Future<void> _initUsb(SharedPreferences prefs) async {
    UsbErgonomicsService? owned;
    try {
      _maybeDebugFail(ExtrasTool.usb);
      final owns = !getIt.isRegistered<UsbErgonomicsService>();
      final usbErgonomics = owns
          ? (owned = UsbErgonomicsService(store: UsbQuirkStore(prefs: prefs)))
          : getIt<UsbErgonomicsService>();
      if (owns) await usbErgonomics.start();
      if (!mounted) {
        if (owns) owned?.dispose();
        return;
      }
      setState(() {
        _usbErgonomics = usbErgonomics;
        _ownsUsbErgonomics = owns;
      });
    } catch (e, st) {
      _failTool(ExtrasTool.usb, 'USB ergonomics', e, st);
    }
  }

  Future<void> _initAnnouncements() async {
    try {
      _maybeDebugFail(ExtrasTool.announcements);
      // Same app-level pair the live announcer uses. Creating here first is
      // fine: the bootstrap picks up whatever is registered, so edits always
      // reach one shared instance instead of a screen-local copy.
      final announcements = getIt.isRegistered<AnnouncementSettings>()
          ? getIt<AnnouncementSettings>()
          : await AnnouncementSettings.load();
      final engine = getIt.isRegistered<MethodChannelTtsEngine>()
          ? getIt<MethodChannelTtsEngine>()
          : MethodChannelTtsEngine();
      if (!mounted) return;
      if (!getIt.isRegistered<AnnouncementSettings>()) {
        getIt.registerSingleton<AnnouncementSettings>(announcements);
      }
      if (!getIt.isRegistered<MethodChannelTtsEngine>()) {
        getIt.registerSingleton<MethodChannelTtsEngine>(engine);
        await engine.init();
      }
      engine.voiceId = announcements.voiceId;
      engine.localeId = announcements.localeId;
      if (!mounted) return;
      setState(() {
        _announcements = announcements;
        _ttsEngine = engine;
      });
    } catch (e, st) {
      _failTool(ExtrasTool.announcements, 'announcements', e, st);
    }
  }

  Future<void> _initAssistant() async {
    try {
      _maybeDebugFail(ExtrasTool.assistant);
      final assistant = getIt.isRegistered<AssistantSettings>()
          ? getIt<AssistantSettings>()
          : await AssistantSettings.load();
      if (!mounted) return;
      if (!getIt.isRegistered<AssistantSettings>()) {
        getIt.registerSingleton<AssistantSettings>(assistant);
      }
      setState(() => _assistantSettings = assistant);
    } catch (e, st) {
      _failTool(ExtrasTool.assistant, 'assistant', e, st);
    }
  }

  /// Live output-device summary for the diagnostics/profile headers.
  Map<String, Object?> _outputDeviceSnapshot() {
    if (!getIt.isRegistered<SettingsCubit>()) {
      return const {'name': 'Unknown output device', 'type': 'unknown'};
    }
    final device = getIt<SettingsCubit>().state.currentOutputDevice;
    if (device == null) {
      return const {'name': 'Unknown output device', 'type': 'unknown'};
    }
    return {
      'name': device.deviceName,
      'type': device.isUsb
          ? 'usb'
          : device.isBluetooth
              ? 'bluetooth'
              : 'wired',
      'sampleRate': device.sampleRate,
      'bitDepth': device.bitDepth,
      'bitPerfect': device.isBitPerfectActive,
    };
  }

  String _deviceLabel() {
    final name = _outputDeviceSnapshot()['name'];
    return name is String ? name : ExtrasStrings.unknownDevice;
  }

  String _deviceKey() {
    final snapshot = _outputDeviceSnapshot();
    final type = snapshot['type'];
    final name = snapshot['name'];
    return '${type ?? 'output'}_${name ?? 'unknown'}';
  }

  /// Opens the network-library browser. The loopback stream server starts on
  /// first use (a real socket), so the screen can play a remote file through the
  /// same HTTP path the player already uses for radio streams.
  Future<void> _openRemoteSources() async {
    try {
      final registered = getIt.isRegistered<RemotePlaybackRuntime>();
      final runtime = registered
          ? getIt<RemotePlaybackRuntime>()
          : (_remoteRuntime ??= RemotePlaybackRuntime());
      _remoteRuntime = runtime;
      _ownsRemoteRuntime = !registered;
      await runtime.ensureStarted();
      if (!mounted) return;
      // One cache index and one credential store for browsing and playback;
      // a second instance would rewrite index.json behind the first one.
      _push(RemoteSourcesScreen(
        onPlay: _playRemoteFile,
        cache: runtime.cache,
        credentials: runtime.credentials,
      ));
    } catch (e, st) {
      ErrorLogger.log(
        'Network library stream server failed to start',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ExtrasStrings.remoteUnavailableTitle),
          content: Text(ExtrasStrings.remoteUnavailableBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ],
        ),
      );
    }
  }

  /// Serves [entry] from [source] through the loopback proxy and hands the HTTP
  /// URI to the player. The provider is owned by the stream server so its
  /// connection is reused for seeks instead of reopened per range request.
  Future<void> _playRemoteFile(RemoteSource source, RemoteEntry entry) async {
    try {
      final runtime = _remoteRuntime ??
          (getIt.isRegistered<RemotePlaybackRuntime>()
              ? getIt<RemotePlaybackRuntime>()
              : null);
      if (runtime == null) {
        throw StateError('Network library server is not running');
      }
      final uri = await runtime.prepareUri(source, entry.path);
      final name = entry.name;
      final song = SongsTableData(
        id: -DateTime.now().millisecondsSinceEpoch,
        title: name.isEmpty ? source.displayName : name,
        artist: source.displayName,
        album: ExtrasStrings.remoteAlbumLabel,
        durationMs: 0,
        path: uri.toString(),
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        // A net-library file is seekable and finite, so it must not be tagged
        // as live radio: that would route pause/resume through the live-edge
        // path (position reset) and show the radio recommendation card.
        source: SongSource.remote,
        isDownloaded: false,
      );
      await getIt<PlayerCubit>().playSong(song);
    } catch (e, st) {
      ErrorLogger.log(
        'Remote playback failed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(ExtrasStrings.remotePlaybackFailed),
          ),
        );
    }
  }

  void _push(Widget screen) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  void dispose() {
    // Announcement settings and the TTS engine are app-level singletons (the
    // live announcer holds the same references), so they are not disposed here.
    if (_ownsSafeMode) _safeMode?.dispose();
    if (_ownsSystemBehavior) _systemBehavior?.dispose();
    if (_ownsUsbErgonomics) _usbErgonomics?.dispose();
    if (_ownsRemoteRuntime) {
      unawaited(_remoteRuntime?.dispose() ?? Future<void>.value());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: Text(ExtrasStrings.title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: _loading
            ? Center(
                child: Text(
                  ExtrasStrings.loading,
                  style: TextStyle(color: p.textSecondary),
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                children: [
                  if (_loadError != null) ...[
                    _InlineNotice(message: _loadError!),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  SettingsSection(
                    icon: Icons.record_voice_over_rounded,
                    title: ExtrasStrings.playbackTitle,
                    subtitle: ExtrasStrings.playbackSubtitle,
                    children: [
                      SettingsNavTile(
                        Icons.campaign_rounded,
                        ExtrasStrings.announcementsTitle,
                        _subtitleFor(ExtrasTool.announcements,
                            ExtrasStrings.announcementsSubtitle),
                        onTap: _announcements == null ||
                                _ttsEngine == null ||
                                !_ready(ExtrasTool.announcements)
                            ? null
                            : () => _push(
                                  AnnouncementScreen(
                                    settings: _announcements!,
                                    engine: _ttsEngine!,
                                  ),
                                ),
                      ),
                      settingsCardDivider(p),
                      SettingsNavTile(
                        Icons.manage_search_rounded,
                        ExtrasStrings.assistantTitle,
                        _subtitleFor(ExtrasTool.assistant,
                            ExtrasStrings.assistantSubtitle),
                        onTap: _assistantSettings == null ||
                                !_ready(ExtrasTool.assistant)
                            ? null
                            : () => _push(
                                  AssistantSettingsScreen(
                                    settings: _assistantSettings!,
                                  ),
                                ),
                      ),
                      settingsCardDivider(p),
                      SettingsNavTile(
                        Icons.tune_rounded,
                        ExtrasStrings.systemBehaviorTitle,
                        _subtitleFor(ExtrasTool.systemBehavior,
                            ExtrasStrings.systemBehaviorSubtitle),
                        onTap: _systemBehavior == null ||
                                !_ready(ExtrasTool.systemBehavior)
                            ? null
                            : () => _push(
                                  SystemBehaviorScreen(
                                    settings: _systemBehavior!,
                                  ),
                                ),
                      ),
                      settingsCardDivider(p),
                      SettingsNavTile(
                        Icons.usb_rounded,
                        ExtrasStrings.usbTitle,
                        _subtitleFor(
                            ExtrasTool.usb, ExtrasStrings.usbSubtitle),
                        onTap: _usbErgonomics == null || !_ready(ExtrasTool.usb)
                            ? null
                            : () => _push(
                                  UsbErgonomicsScreen(
                                    service: _usbErgonomics!,
                                  ),
                                ),
                      ),
                    ],
                  ),
                  SettingsSection(
                    icon: Icons.cast_connected_rounded,
                    title: ExtrasStrings.outputTitle,
                    subtitle: ExtrasStrings.outputSubtitle,
                    children: [
                      SettingsNavTile(
                        Icons.cast_rounded,
                        ExtrasStrings.dlnaTitle,
                        ExtrasStrings.dlnaSubtitle,
                        onTap: () => _push(
                          getIt.isRegistered<DlnaRendererService>()
                              ? DlnaScreen(
                                  service: getIt<DlnaRendererService>(),
                                )
                              : const DlnaScreen(),
                        ),
                      ),
                      settingsCardDivider(p),
                      SettingsNavTile(
                        Icons.dns_rounded,
                        ExtrasStrings.remoteTitle,
                        ExtrasStrings.remoteSubtitle,
                        onTap: () =>
                            _openRemoteSources(),
                      ),
                    ],
                  ),
                  SettingsSection(
                    icon: Icons.health_and_safety_rounded,
                    title: ExtrasStrings.supportTitle,
                    subtitle: ExtrasStrings.supportSubtitle,
                    children: [
                      SettingsNavTile(
                        Icons.badge_rounded,
                        ExtrasStrings.profilesTitle,
                        _subtitleFor(
                            ExtrasTool.profiles, ExtrasStrings.profilesSubtitle),
                        onTap: _profiles == null || !_ready(ExtrasTool.profiles)
                            ? null
                            : () => _push(
                                  AudioProfilesScreen(
                                    service: _profiles!,
                                    deviceLabel: _deviceLabel,
                                  ),
                                ),
                      ),
                      settingsCardDivider(p),
                      SettingsNavTile(
                        Icons.monitor_heart_rounded,
                        ExtrasStrings.diagnosticsTitle,
                        _subtitleFor(ExtrasTool.diagnostics,
                            ExtrasStrings.diagnosticsSubtitle),
                        onTap: _diagnostics == null ||
                                _safeMode == null ||
                                !_ready(ExtrasTool.diagnostics) ||
                                !_ready(ExtrasTool.safeMode)
                            ? null
                            : () => _push(
                                  DiagnosticsScreen(
                                    bundleService: _diagnostics!,
                                    safeMode: _safeMode!,
                                    deviceLabel: _deviceLabel,
                                    deviceKey: _deviceKey,
                                  ),
                                ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final String message;

  const _InlineNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: p.error, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tool row in the hub; keys its initialization failure.
enum ExtrasTool {
  profiles,
  diagnostics,
  safeMode,
  systemBehavior,
  usb,
  announcements,
  assistant,
}
