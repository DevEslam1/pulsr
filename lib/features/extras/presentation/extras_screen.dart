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
  const ExtrasScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profiles = AudioProfileService(prefs: prefs);
      final diagnostics = DiagnosticsBundleService(
        prefs: prefs,
        outputDevice: _outputDeviceSnapshot,
      );
      // The audio handler publishes the app-scoped controller so the failure
      // streak and the manual Enter/Exit controls share one active-device map.
      final ownsSafeMode = !getIt.isRegistered<SafeModeController>();
      final safeMode = ownsSafeMode
          ? SafeModeController(prefs: prefs)
          : getIt<SafeModeController>();
      // Reuse the app-level instances started with the audio handler; only build
      // private ones when the bootstrap has not published them (tests, early
      // navigation). Ownership follows creation so nothing is disposed twice.
      final ownsBehavior = !getIt.isRegistered<SystemBehaviorSettings>();
      final behavior = ownsBehavior
          ? SystemBehaviorSettings()
          : getIt<SystemBehaviorSettings>();
      if (ownsBehavior) await behavior.load();
      final ownsUsb = !getIt.isRegistered<UsbErgonomicsService>();
      final usbErgonomics = ownsUsb
          ? UsbErgonomicsService(store: UsbQuirkStore(prefs: prefs))
          : getIt<UsbErgonomicsService>();
      if (ownsUsb) await usbErgonomics.start();
      // Same app-level pair the live announcer uses. Creating here first is
      // fine: the bootstrap picks up whatever is registered, so edits always
      // reach one shared instance instead of a screen-local copy.
      final announcements = getIt.isRegistered<AnnouncementSettings>()
          ? getIt<AnnouncementSettings>()
          : await AnnouncementSettings.load();
      final engine = getIt.isRegistered<MethodChannelTtsEngine>()
          ? getIt<MethodChannelTtsEngine>()
          : MethodChannelTtsEngine();
      if (!getIt.isRegistered<AnnouncementSettings>()) {
        getIt.registerSingleton<AnnouncementSettings>(announcements);
      }
      if (!getIt.isRegistered<MethodChannelTtsEngine>()) {
        getIt.registerSingleton<MethodChannelTtsEngine>(engine);
        await engine.init();
      }
      engine.voiceId = announcements.voiceId;
      engine.localeId = announcements.localeId;
      final assistant = getIt.isRegistered<AssistantSettings>()
          ? getIt<AssistantSettings>()
          : await AssistantSettings.load();
      if (!getIt.isRegistered<AssistantSettings>()) {
        getIt.registerSingleton<AssistantSettings>(assistant);
      }
      if (!mounted) {
        if (ownsBehavior) behavior.dispose();
        if (ownsUsb) usbErgonomics.dispose();
        if (ownsSafeMode) await safeMode.dispose();
        return;
      }
      setState(() {
        _profiles = profiles;
        _diagnostics = diagnostics;
        _safeMode = safeMode;
        _systemBehavior = behavior;
        _usbErgonomics = usbErgonomics;
        _announcements = announcements;
        _ttsEngine = engine;
        _assistantSettings = assistant;
        _ownsSystemBehavior = ownsBehavior;
        _ownsUsbErgonomics = ownsUsb;
        _ownsSafeMode = ownsSafeMode;
        _loading = false;
        _loadError = null;
      });
    } catch (e, st) {
      ErrorLogger.log(
        'Extras tools failed to initialize',
        error: e,
        stackTrace: st,
        category: 'Extras',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = ExtrasStrings.loadFailed;
      });
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

  /// Serves [path] from [source] through the loopback proxy and hands the HTTP
  /// URI to the player. The provider is owned by the stream server so its
  /// connection is reused for seeks instead of reopened per range request.
  Future<void> _playRemoteFile(RemoteSource source, String path) async {
    try {
      final runtime = _remoteRuntime ??
          (getIt.isRegistered<RemotePlaybackRuntime>()
              ? getIt<RemotePlaybackRuntime>()
              : null);
      if (runtime == null) {
        throw StateError('Network library server is not running');
      }
      final uri = await runtime.prepareUri(source, path);
      final name = path.split('/').last;
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
        source: SongSource.radio,
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
                        ExtrasStrings.announcementsSubtitle,
                        onTap: _announcements == null || _ttsEngine == null
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
                        ExtrasStrings.assistantSubtitle,
                        onTap: _assistantSettings == null
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
                        ExtrasStrings.systemBehaviorSubtitle,
                        onTap: _systemBehavior == null
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
                        ExtrasStrings.usbSubtitle,
                        onTap: _usbErgonomics == null
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
                        ExtrasStrings.profilesSubtitle,
                        onTap: _profiles == null
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
                        ExtrasStrings.diagnosticsSubtitle,
                        onTap: _diagnostics == null || _safeMode == null
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
