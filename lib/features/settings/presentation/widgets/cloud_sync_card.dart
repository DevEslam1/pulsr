// lib/features/settings/presentation/widgets/cloud_sync_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../auth/cubit/auth_cubit.dart';
import '../../../auth/cubit/auth_state.dart';
import '../../../auth/presentation/auth_sheet.dart';

/// Account / cloud-sync card pinned to the top of the settings screen.
/// Moved verbatim from settings_screen.dart (was `_buildCloudSyncCard`).
class CloudSyncCard extends StatelessWidget {
  const CloudSyncCard({super.key});

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
          if (state.lastSyncedAt != null) {
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
          margin: const EdgeInsets.only(bottom: 20, top: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: user != null
                          ? p.accent.withValues(alpha: 0.15)
                          : p.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.hairline),
                    ),
                    child: user?.photoURL != null
                        ? ClipOval(
                            child: Image.network(
                              user!.photoURL!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Icon(Icons.person_rounded, color: p.accent),
                            ),
                          )
                        : Icon(
                            user != null
                                ? Icons.person_rounded
                                : Icons.cloud_outlined,
                            color: p.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ??
                              user?.email ??
                              context.l10n.cloudSync,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          syncSubtitle,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (user == null) ...[
                    FilledButton(
                      onPressed: () => AuthSheet.show(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(context.l10n.signIn,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ] else ...[
                    IconButton(
                      tooltip: context.l10n.syncNow,
                      icon: isSyncing
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: p.accent))
                          : Icon(Icons.sync_rounded, color: p.accent),
                      onPressed: isSyncing ? null : () => authCubit.syncNow(),
                    ),
                    IconButton(
                      tooltip: context.l10n.signOut,
                      icon: Icon(Icons.logout_rounded,
                          color: p.textTertiary, size: 20),
                      onPressed: () => authCubit.signOut(),
                    ),
                  ],
                ],
              ),
              if (state.syncError != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.syncError!,
                  style: TextStyle(color: p.error, fontSize: 11),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
