// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/config/app_config.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';
import 'widgets/appearance_section.dart';
import 'widgets/audio_sound_section.dart';
import 'widgets/device_profiles_section.dart';
import 'widgets/cache_section.dart';
import 'widgets/cloud_sync_card.dart';
import 'widgets/gestures_section.dart';
import 'widgets/library_section.dart';
import 'widgets/online_section.dart';
import 'widgets/playback_section.dart';
import 'widgets/privacy_data_section.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tiles.dart';

///
/// Section order (daily-usage first):
///   1. Account / Cloud sync card
///   2. Playback            — sleep timer, gapless, crossfade, resume, waveform
///   3. Audio & Sound       — EQ, DSP engine, output device, bit-perfect, ReplayGain
///   4. Theme & Appearance  — theme mode, accent, player theme, visualizer, language
///   5. Gestures            — mini-player swipes, now-playing actions
///   6. Library & Scanning  — hidden folders, rescan, short-audio filter
///   7. YouTube Music & Online (or Network & Proxy on non-YTM builds)
///   8. Storage & Cache
///   9. Privacy & Data      — backup, scrobbling, privacy
///  10. About
///
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (prev, curr) => prev.errorMessage != curr.errorMessage && curr.errorMessage != null,
      listener: (ctx, state) {
        final msg = state.errorMessage;
        if (msg != null && msg.isNotEmpty) {
          ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Theme.of(ctx).colorScheme.error, behavior: SnackBarBehavior.floating),
          );
          // clear after showing
          ctx.read<SettingsCubit>().clearError();
        }
      },
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.settings)),
            body: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 760), // readable on tablets
                child: ListView(
                  padding: EdgeInsets.only(
                      bottom: 160,
                      top: 8,
                      left: Adaptive.pagePadding(context),
                      right: Adaptive.pagePadding(context)),
                  children: [
                    const CloudSyncCard(),
                    PlaybackSection(state: state),
                    AudioSoundSection(state: state),
                    SettingsSection(
                      icon: Icons.speaker_group_rounded,
                      title: context.l10n.deviceProfilesTitle,
                      children: const [DeviceProfilesSection()],
                    ),
                    AppearanceSection(state: state),
                    GesturesSection(state: state),
                    LibrarySection(state: state),
                    if (AppConfig.ytmEnabled) YtmOnlineSection(state: state),
                    if (!AppConfig.ytmEnabled)
                      NetworkProxySection(state: state),
                    SettingsSection(
                      icon: Icons.storage_rounded,
                      title: context.l10n.storageAndCache,
                      children: const [CacheSection()],
                    ),
                    PrivacyDataSection(state: state),
                    SettingsSection(
                      icon: Icons.info_outline_rounded,
                      title: context.l10n.about,
                      children: [
                        SettingsNavTile(
                            Icons.info_outline_rounded,
                            context.l10n.appTitle,
                            context.l10n.aboutAppSubtitle,
                            onTap: () {}),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
