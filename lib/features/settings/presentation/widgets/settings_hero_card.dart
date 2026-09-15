// lib/features/settings/presentation/widgets/settings_hero_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../auth/cubit/auth_cubit.dart';
import '../../../auth/cubit/auth_state.dart';
import '../../../auth/presentation/auth_sheet.dart';

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
            syncSubtitle = 'Syncing your library...';
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
          margin: const EdgeInsets.only(bottom: 18, top: 4),
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
                Positioned(
                  top: -24,
                  right: -24,
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                Positioned(
                                  bottom: 0,
                                  right: 0,
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
                          const SizedBox(width: 14),
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
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (user != null) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: p.accent.withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(context.l10n.syncedLabel,
                                          style: TextStyle(
                                            color: p.accent,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  syncSubtitle,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
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
                                    horizontal: 14, vertical: 8),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
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
                                    padding: const EdgeInsets.all(8),
                                  ),
                                  icon: isSyncing
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: p.accent,
                                          ),
                                        )
                                      : const Icon(Icons.sync_rounded, size: 20),
                                  onPressed: isSyncing
                                      ? null
                                      : () => authCubit.syncNow(),
                                ),
                                const SizedBox(width: 4),
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
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: p.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: p.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  color: p.error, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  state.syncError!,
                                  style: TextStyle(
                                    color: p.error,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
}
