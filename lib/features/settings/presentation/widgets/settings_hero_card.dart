// lib/features/settings/presentation/widgets/settings_hero_card.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/performance/gpu_budget.dart';
import '../../../../core/services/ytm_account_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/pulsr_pressable.dart';
import '../../../../core/widgets/pulsr_progress.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../auth/cubit/auth_cubit.dart';
import '../../../auth/cubit/auth_state.dart';
import '../../../auth/presentation/auth_sheet.dart';
import '../../../auth/presentation/ytm_web_login_sheet.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/presentation/widgets/equalizer_sheet.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import 'audio_setup_wizard.dart';
import 'ytm_account_disconnect_dialog.dart';

/// Top "Quick Controls" strip for the 4 most toggled preferences in Settings:
/// 1. Experience Mode (Normal vs Professional)
/// 2. Theme / AMOLED
/// 3. Offline-Only Mode
/// 4. Active Audio Engine / EQ
class SettingsQuickControlsStrip extends StatelessWidget {
  final SettingsState? state;
  final SettingsCubit? cubit;
  final VoidCallback? onOpenAudioEngine;

  const SettingsQuickControlsStrip({
    super.key,
    this.state,
    this.cubit,
    this.onOpenAudioEngine,
  });

  static String quickControlsHeading(BuildContext context) =>
      context.l10n.settingsQuickControls;

  @override
  Widget build(BuildContext context) {
    final activeCubit = cubit ?? context.read<SettingsCubit>();
    final activeState = state ?? context.watch<SettingsCubit>().state;
    final p = context.palette;
    final l10n = context.l10n;
    final isPro = activeState.isProfessional;
    final isAmoled = activeState.themeMode == AppThemeMode.amoled;
    final isOffline = activeState.offlineOnlyMode;
    final isBitPerfect = activeState.bitPerfectOutput;

    final themeStatus = switch (activeState.themeMode) {
      AppThemeMode.amoled => l10n.amoledLabel,
      AppThemeMode.dark => l10n.themeDark,
      AppThemeMode.light => l10n.themeLight,
      AppThemeMode.system => l10n.systemDefault,
    };

    final tiles = <Widget>[
      _QuickControlTile(
        tileKey: const ValueKey('quick_control_experience_mode'),
        icon: isPro ? Icons.tune_rounded : Icons.auto_awesome_rounded,
        label: l10n.experienceModeTitle,
        status: isPro
            ? l10n.experienceModeProfessional
            : l10n.experienceModeNormal,
        isActive: isPro,
        onTap: () {
          PulsrHaptics.selectionClick();
          activeCubit.setExperienceMode(
            isPro ? ExperienceMode.normal : ExperienceMode.professional,
          );
        },
      ),
      _QuickControlTile(
        tileKey: const ValueKey('quick_control_theme_amoled'),
        icon: isAmoled ? Icons.nightlight_round : Icons.dark_mode_outlined,
        label: l10n.amoledLabel,
        status: themeStatus,
        isActive: isAmoled,
        onTap: () {
          PulsrHaptics.selectionClick();
          activeCubit.setThemeMode(
            isAmoled ? AppThemeMode.dark : AppThemeMode.amoled,
          );
        },
      ),
      _QuickControlTile(
        tileKey: const ValueKey('quick_control_offline_only'),
        icon: isOffline ? Icons.cloud_off_rounded : Icons.cloud_queue_rounded,
        label: l10n.offlineOnlyMode,
        status: isOffline ? l10n.activeLabel : l10n.rgOff,
        isActive: isOffline,
        onTap: () {
          PulsrHaptics.selectionClick();
          activeCubit.setOfflineOnlyMode(!isOffline);
        },
      ),
      _QuickControlTile(
        tileKey: const ValueKey('quick_control_audio_engine_eq'),
        icon: isBitPerfect ? Icons.usb_rounded : Icons.equalizer_rounded,
        label: l10n.equalizer,
        status:
            isBitPerfect ? l10n.badgeExclusive : l10n.onboardingAudioEngine,
        isActive: isBitPerfect,
        onTap: () {
          PulsrHaptics.selectionClick();
          if (onOpenAudioEngine != null) {
            onOpenAudioEngine!();
            return;
          }
          bool hasPlayerCubit = false;
          try {
            context.read<PlayerCubit>();
            hasPlayerCubit = true;
          } catch (_) {
            hasPlayerCubit = false;
          }
          if (hasPlayerCubit) {
            EqualizerSheet.show(context);
          } else {
            AudioSetupWizardSheet.show(context, cubit: activeCubit);
          }
        },
      ),
    ];

    final heading = quickControlsHeading(context);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.xxs,
              0,
              AppSpacing.xxs,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 16, color: p.accent),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w800,
                        letterSpacing: AppTracking.wide,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(child: tiles[0]),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: tiles[1]),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(child: tiles[2]),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: tiles[3]),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickControlTile extends StatelessWidget {
  final Key tileKey;
  final IconData icon;
  final String label;
  final String status;
  final bool isActive;
  final VoidCallback onTap;

  const _QuickControlTile({
    required this.tileKey,
    required this.icon,
    required this.label,
    required this.status,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shouldAnimate = PulsrMotion.shouldAnimate(context);

    return Semantics(
      button: true,
      toggled: isActive,
      label: '$label, $status',
      child: PulsrPressable(
        pressedScale: 0.98,
        onTap: onTap,
        child: AnimatedContainer(
          key: tileKey,
          duration: shouldAnimate ? context.motionMs(200) : Duration.zero,
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? p.accent.withValues(alpha: 0.14)
                : p.surfaceContainerHigh.withValues(alpha: 0.55),
            borderRadius: AppRadii.r14All,
            border: Border.all(
              color: isActive
                  ? p.accent.withValues(alpha: 0.55)
                  : p.hairline,
              width: isActive ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isActive
                      ? p.accent.withValues(alpha: 0.20)
                      : p.surfaceContainer,
                  borderRadius: AppRadii.r10All,
                ),
                child: Icon(
                  icon,
                  size: 17,
                  color: isActive ? p.accent : p.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive ? p.accent : p.textSecondary,
                        fontSize: AppFontSize.caption,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A hero card displayed at the top of the Settings screen showing the user's
/// account identity, real-time Cloud Sync status, and quick sync/sign-out actions.
class SettingsHeroCard extends StatelessWidget {
  const SettingsHeroCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isCalm = p.isCalmDensity || GpuBudget.isEnabled;

    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        final authCubit = context.read<AuthCubit>();
        final user = state.user;
        final isSyncing = state.syncStatus == SyncStatus.syncing;

        String syncSubtitle = context.l10n.cloudSyncSubtitle;
        if (user != null) {
          if (isSyncing) {
            syncSubtitle = context.l10n.settingsSyncingLibrary;
          } else if (state.lastSyncedAt != null) {
            final diff = DateTime.now().difference(state.lastSyncedAt!);
            if (diff.inMinutes < 1) {
              syncSubtitle = context.l10n.lastSyncedJustNow;
            } else if (diff.inHours < 1) {
              syncSubtitle = context.l10n.lastSyncedMinutesAgo(diff.inMinutes);
            } else {
              syncSubtitle = context.l10n.lastSyncedHoursAgo(diff.inHours);
            }
          } else {
            syncSubtitle = context.l10n.connectedReadyToSync;
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: AppRadii.cardRadius,
            border: Border.all(color: isCalm ? p.borderSubtle : p.hairline),
            boxShadow: isCalm
                ? null
                : [
                    BoxShadow(
                      color: (user != null ? p.accent : Colors.black)
                          .withValues(alpha: p.isDark ? 0.08 : 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: AppRadii.cardRadius,
            child: Stack(
              children: [
                // Subtle accent gradient glow on top-right corner
                if (!isCalm)
                  PositionedDirectional(
                    top: -24,
                    end: -24,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            p.accent.withValues(alpha: 0.12),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (AppConfig.isCloudSyncAllowed) ...[
                        LayoutBuilder(builder: (context, constraints) {
                          final identity = Row(
                            children: [
                              // Avatar / Icon with online ring
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: user != null
                                          ? p.accent.withValues(alpha: 0.15)
                                          : p.surface,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: user != null
                                            ? p.accent.withValues(alpha: 0.4)
                                            : p.hairline,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: user?.photoURL != null
                                        ? ClipOval(
                                            child: Image.network(
                                              user!.photoURL!,
                                              fit: BoxFit.cover,
                                              cacheWidth: 104,
                                              cacheHeight: 104,
                                              loadingBuilder: (context, child,
                                                      progress) =>
                                                  progress == null
                                                      ? child
                                                      : const SkeletonBox(
                                                          width: 50,
                                                          height: 50,
                                                          radius: 25,
                                                        ),
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(
                                                Icons.person_rounded,
                                                color: p.accent,
                                                size: 26,
                                              ),
                                            ),
                                          )
                                        : Icon(
                                            user != null
                                                ? Icons.person_rounded
                                                : Icons.cloud_outlined,
                                            color: p.accent,
                                            size: 26,
                                          ),
                                  ),
                                  if (user != null)
                                    PositionedDirectional(
                                      bottom: 0,
                                      end: 0,
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color:
                                              isSyncing ? p.accent : p.success,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: p.surfaceContainer,
                                            width: 2.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: AppSpacing.s14),
                              // User details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            user?.displayName ??
                                                user?.email ??
                                                context.l10n.cloudSync,
                                            style: TextStyle(
                                              color: p.textPrimary,
                                              fontSize: AppFontSize.bodyLarge,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: AppTracking.title,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (user != null) ...[
                                          const SizedBox(width: AppSpacing.s6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: AppSpacing.s6,
                                                vertical: AppSpacing.s2),
                                            decoration: BoxDecoration(
                                              color: p.accent
                                                  .withValues(alpha: 0.15),
                                              borderRadius: AppRadii.r6All,
                                            ),
                                            child: Text(
                                              context.l10n.syncedLabel,
                                              style: TextStyle(
                                                color: p.accent,
                                                fontSize: AppFontSize.caption,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing:
                                                    AppTracking.medium,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.xxs),
                                    Semantics(
                                      liveRegion: isSyncing,
                                      child: Text(
                                        syncSubtitle,
                                        style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: AppFontSize.label,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                          final action = user == null
                              ? FilledButton.icon(
                                  onPressed: () => AuthSheet.show(context),
                                  icon:
                                      const Icon(Icons.login_rounded, size: 16),
                                  label: Text(context.l10n.signIn),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: p.accent,
                                    foregroundColor: p.onAccent,
                                    minimumSize: const Size(
                                      AppSpacing.minTouchTarget,
                                      AppSpacing.minTouchTarget,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.s14,
                                        vertical: AppSpacing.xs),
                                    textStyle: const TextStyle(
                                      fontFamily: fontFamily,
                                      fontFamilyFallback: fontFallbacks,
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.bodySmall,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: AppRadii.buttonRadius,
                                    ),
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton.filledTonal(
                                      constraints: const BoxConstraints(
                                          minWidth: AppSpacing.minTouchTarget,
                                          minHeight: AppSpacing.minTouchTarget),
                                      tooltip: context.l10n.syncNow,
                                      style: IconButton.styleFrom(
                                        backgroundColor:
                                            p.accent.withValues(alpha: 0.15),
                                        foregroundColor: p.accent,
                                        padding:
                                            const EdgeInsets.all(AppSpacing.xs),
                                      ),
                                      icon: isSyncing
                                          ? PulsrProgressBar.circular(
                                              size: AppSpacing.s18,
                                              strokeWidth: 2,
                                              color: p.accent,
                                            )
                                          : const Icon(Icons.sync_rounded,
                                              size: 20),
                                      onPressed: isSyncing
                                          ? null
                                          : () => authCubit.syncNow(),
                                    ),
                                    const SizedBox(width: AppSpacing.xxs),
                                    IconButton(
                                      constraints: const BoxConstraints(
                                          minWidth: AppSpacing.minTouchTarget,
                                          minHeight: AppSpacing.minTouchTarget),
                                      tooltip: context.l10n.signOut,
                                      icon: Icon(
                                        Icons.logout_rounded,
                                        color: p.textTertiary,
                                        size: 20,
                                      ),
                                      onPressed: () => authCubit.signOut(),
                                    ),
                                  ],
                                );
                          final stacked = (user != null &&
                                  constraints.maxWidth < 320) ||
                              (user == null && constraints.maxWidth < 360) ||
                              MediaQuery.textScalerOf(context).scale(14) > 18;
                          final body = stacked
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                      identity,
                                      const SizedBox(height: 12),
                                      Align(
                                        alignment:
                                            AlignmentDirectional.centerEnd,
                                        child: action,
                                      ),
                                    ])
                              : Row(children: [
                                  Expanded(child: identity),
                                  const SizedBox(width: 8),
                                  action
                                ]);

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: AppRadii.r12All,
                              onTap: user == null
                                  ? () => AuthSheet.show(context)
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.xxs),
                                child: body,
                              ),
                            ),
                          );
                        }),
                        if (state.syncError != null) ...[
                          const SizedBox(height: AppSpacing.s10),
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s10,
                                  vertical: AppSpacing.s6),
                              decoration: BoxDecoration(
                                color: p.error.withValues(alpha: 0.12),
                                borderRadius: AppRadii.r8All,
                                border: Border.all(
                                    color: p.error.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline_rounded,
                                      color: p.error, size: 16),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      state.syncError!.userMessage,
                                      style: TextStyle(
                                        color: p.error,
                                        fontSize: AppFontSize.label,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                      if (AppConfig.isCloudSyncAllowed &&
                          AppConfig.ytmEnabled) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: p.hairline,
                          ),
                        ),
                      ],
                      if (AppConfig.ytmEnabled) _buildYtmRow(context, p),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildYtmRow(BuildContext context, PulsrPalette p) {
    if (!getIt.isRegistered<YtmAccountService>()) {
      return const SizedBox.shrink();
    }
    final ytmAccount = getIt<YtmAccountService>();
    return ValueListenableBuilder<bool>(
      valueListenable: ytmAccount.loginState,
      builder: (context, isLoggedIn, _) {
        final accountName = ytmAccount.accountName;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadii.r12All,
            onTap: () async {
              if (isLoggedIn) {
                await showYtmAccountDisconnectDialog(context);
              } else {
                final ok = await YtmWebLoginSheet.show(context);
                if (ok == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.ytmConnected),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: isLoggedIn
                              ? AppColors.ytRed.withValues(alpha: 0.15)
                              : p.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isLoggedIn
                                ? AppColors.ytRed.withValues(alpha: 0.4)
                                : p.hairline,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: isLoggedIn ? AppColors.ytRed : p.textSecondary,
                          size: 26,
                        ),
                      ),
                      if (isLoggedIn)
                        PositionedDirectional(
                          bottom: 0,
                          end: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: p.success,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: p.surfaceContainer,
                                width: 2.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.s14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                isLoggedIn
                                    ? (accountName ?? 'YouTube Music')
                                    : 'YouTube Music',
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: AppFontSize.bodyLarge,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: AppTracking.title,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isLoggedIn) ...[
                              const SizedBox(width: AppSpacing.s6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.s6,
                                    vertical: AppSpacing.s2),
                                decoration: BoxDecoration(
                                  color: p.success.withValues(alpha: 0.15),
                                  borderRadius: AppRadii.r6All,
                                ),
                                child: Builder(
                                  builder: (_) {
                                    final status =
                                        context.l10n.settingsBadgeConnected;
                                    return Text(
                                      status,
                                      style: TextStyle(
                                        color: p.success,
                                        fontSize: AppFontSize.caption,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: AppTracking.medium,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          isLoggedIn
                              ? 'YouTube Music • ${context.l10n.settingsTapToManage}'
                              : context.l10n.connectYtmSubtitle,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  if (!isLoggedIn)
                    FilledButton.icon(
                      onPressed: () async {
                        final ok = await YtmWebLoginSheet.show(context);
                        if (ok == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.l10n.ytmConnected),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.login_rounded, size: 16),
                      label: Text(context.l10n.signIn),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.ytRed,
                        foregroundColor:
                            AppColors.textOnAccent(AppColors.ytRed),
                        minimumSize: const Size(
                          AppSpacing.minTouchTarget,
                          AppSpacing.minTouchTarget,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s14,
                            vertical: AppSpacing.xs),
                        textStyle: const TextStyle(
                          fontFamily: fontFamily,
                          fontFamilyFallback: fontFallbacks,
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.bodySmall,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.buttonRadius,
                        ),
                      ),
                    )
                  else
                    IconButton(
                      constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget),
                      tooltip: context.l10n.settingsManageYtm,
                      icon: Icon(
                        Icons.tune_rounded,
                        color: p.textTertiary,
                        size: 20,
                      ),
                      onPressed: () => showYtmAccountDisconnectDialog(context),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
