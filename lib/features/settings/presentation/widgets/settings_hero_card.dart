// lib/features/settings/presentation/widgets/settings_hero_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/ytm_account_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../auth/cubit/auth_cubit.dart';
import '../../../auth/cubit/auth_state.dart';
import '../../../auth/presentation/auth_sheet.dart';
import '../../../auth/presentation/ytm_web_login_sheet.dart';
import 'ytm_account_disconnect_dialog.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

/// A hero card displayed at the top of the Settings screen showing the user's
/// account identity, real-time Cloud Sync status, and quick sync/sign-out actions.
class SettingsHeroCard extends StatelessWidget {
  const SettingsHeroCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

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
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: p.hairline),
            boxShadow: [
              BoxShadow(
                color: (user != null ? p.accent : Colors.black)
                    .withValues(alpha: p.isDark ? 0.08 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Stack(
              children: [
                // Subtle accent gradient glow on top-right corner
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
                        Row(
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
                                            errorBuilder: (_, __, ___) => Icon(
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
                                        color: isSyncing ? p.accent : p.success,
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
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (user != null) ...[
                                        const SizedBox(width: AppSpacing.s6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(

                                              horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
                                          decoration: BoxDecoration(
                                            color: p.accent
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(AppRadii.r6),
                                          ),
                                          child: Text(
                                            context.l10n.syncedLabel,
                                            style: TextStyle(
                                              color: p.accent,
                                              fontSize: AppFontSize.tiny,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: AppTracking.medium,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xxs),
                                  Text(
                                    syncSubtitle,
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: AppFontSize.label,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            // Action buttons
                            if (user == null)
                              FilledButton.icon(
                                onPressed: () => AuthSheet.show(context),
                                icon: const Icon(Icons.login_rounded, size: 16),
                                label: Text(context.l10n.signIn),
                                style: FilledButton.styleFrom(
                                  backgroundColor: p.accent,
                                  foregroundColor: p.onAccent,
                                  padding: const EdgeInsets.symmetric(

                                      horizontal: AppSpacing.s14, vertical: AppSpacing.xs),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: AppFontSize.bodySmall,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(AppRadii.button),
                                  ),
                                ),
                              )
                            else
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton.filledTonal(
                                    tooltip: context.l10n.syncNow,
                                    style: IconButton.styleFrom(
                                      backgroundColor:
                                          p.accent.withValues(alpha: 0.15),
                                      foregroundColor: p.accent,
                                      padding: const EdgeInsets.all(AppSpacing.xs),
                                    ),
                                    icon: isSyncing
                                        ? SizedBox(width: AppSpacing.s18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: p.accent,
                                            ),
                                          )
                                        : const Icon(Icons.sync_rounded,
                                            size: 20),
                                    onPressed: isSyncing
                                        ? null
                                        : () => authCubit.syncNow(),
                                  ),
                                  const SizedBox(width: AppSpacing.xxs),
                                  IconButton(
                                    tooltip: context.l10n.signOut,
                                    icon: Icon(
                                      Icons.logout_rounded,
                                      color: p.textTertiary,
                                      size: 20,
                                    ),
                                    onPressed: () => authCubit.signOut(),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        if (state.syncError != null) ...[
                          const SizedBox(height: AppSpacing.s10),
                          Container(
                            padding: const EdgeInsets.symmetric(

                                horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
                            decoration: BoxDecoration(
                              color: p.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadii.r8),
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
                                    state.syncError!,
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
                        ],
                      ],
                      if (AppConfig.isCloudSyncAllowed &&
                          AppConfig.ytmEnabled) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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
    final ytmAccount = getIt<YtmAccountService>();
    return ValueListenableBuilder<bool>(
      valueListenable: ytmAccount.loginState,
      builder: (context, isLoggedIn, _) {
        final accountName = ytmAccount.accountName;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.r12),
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
                          color: isLoggedIn
                              ? AppColors.ytRed
                              : p.textSecondary,
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

                                    horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
                                decoration: BoxDecoration(
                                  color: p.success.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(AppRadii.r6),
                                ),
                                child: Builder(
                                  builder: (_) {
                                    final status = context.l10n.settingsBadgeConnected;
                                    return Text(
                                      status,
                                      style: TextStyle(
                                        color: p.success,
                                        fontSize: AppFontSize.tiny,
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
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(

                            horizontal: AppSpacing.s14, vertical: AppSpacing.xs),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.bodySmall,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.button),
                        ),
                      ),
                    )
                  else
                    IconButton(
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
