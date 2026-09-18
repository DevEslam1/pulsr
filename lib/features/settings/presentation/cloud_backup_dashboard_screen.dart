import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class CloudBackupDashboardScreen extends StatefulWidget {
  final CloudSyncService? syncService;

  const CloudBackupDashboardScreen({super.key, this.syncService});

  @override
  State<CloudBackupDashboardScreen> createState() =>
      _CloudBackupDashboardScreenState();
}

class _CloudBackupDashboardScreenState
    extends State<CloudBackupDashboardScreen> {
  late final CloudSyncService _syncService;
  bool _isSyncing = false;
  bool _syncFavorites = true;
  bool _syncPlaylists = true;

  @override
  void initState() {
    super.initState();
    _syncService = widget.syncService ?? getIt<CloudSyncService>();
    _loadSyncScopes();
  }

  Future<void> _loadSyncScopes() async {
    try {
      final fav = await _syncService.isFavoritesSyncEnabled;
      final pl = await _syncService.isPlaylistsSyncEnabled;
      if (!mounted) return;
      setState(() {
        _syncFavorites = fav;
        _syncPlaylists = pl;
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to load cloud sync scope toggles',
          error: e, stackTrace: st, category: 'CloudBackupDashboard');
    }
  }

  Future<void> _performSync() async {
    setState(() => _isSyncing = true);
    final success = await _syncService.syncAll();
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? context.l10n.settingsCloudSyncCompleted
              : context.l10n.settingsCloudSyncFailed),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lastSync = _syncService.lastSyncTime;
    final lastSyncStr =
        lastSync != null ? '${lastSync.toLocal()}'.split('.').first : context.l10n.settingsNeverLabel;

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          backgroundColor: p.surface,
          elevation: 0,
          leading: const PulsrBackButton(),
          title: Text(context.l10n.cloudBackupSync,
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, 120),
        children: [
          // Cloud Status Card
          Container(
            padding: const EdgeInsets.all(AppSpacing.s18),
            decoration: BoxDecoration(
              color: p.surfaceCard,
              borderRadius: BorderRadius.circular(AppRadii.r20),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud_done_rounded,
                            color: p.primary, size: 24),
                        const SizedBox(width: AppSpacing.s10),
                        Text(context.l10n.cloudStorageStatus,
                          style: TextStyle(
                              fontSize: AppFontSize.bodyLarge,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary),
                        ),
                      ],
                    ),
                    if (_isSyncing)
                      SizedBox(width: AppSpacing.s20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: p.primary),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(context.l10n.cloudBackupDesc,
                  style: TextStyle(fontSize: AppFontSize.bodySmall, color: p.textSecondary),
                ),
                const SizedBox(height: AppSpacing.s14),
                Divider(color: p.hairline),
                const SizedBox(height: AppSpacing.s10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.l10n.lastSynced,
                        style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall)),
                    Text(lastSyncStr,
                        style: TextStyle(
                            color: p.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: AppFontSize.bodySmall)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text(context.l10n.whatGetsSynced,
            style: TextStyle(
                fontSize: AppFontSize.callout,
                fontWeight: FontWeight.w700,
                color: p.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.cloudSyncItemsDesc,
            style: TextStyle(fontSize: AppFontSize.bodySmall, color: p.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),

          // Per-scope sync toggles (previously the service exposed them but
          // no UI ever set or read them, so syncAll always synced everything).
          _SyncScopeTile(
            icon: Icons.favorite_rounded,
            title: context.l10n.cloudSyncFavoritesLabel,
            subtitle: context.l10n.cloudSyncFavoritesDesc,
            value: _syncFavorites,
            onChanged: (v) async {
              setState(() => _syncFavorites = v);
              await _syncService.setFavoritesSyncEnabled(v);
            },
          ),
          _SyncScopeTile(
            icon: Icons.queue_music_rounded,
            title: context.l10n.cloudSyncPlaylistsLabel,
            subtitle: context.l10n.cloudSyncPlaylistsDesc,
            value: _syncPlaylists,
            onChanged: (v) async {
              setState(() => _syncPlaylists = v);
              await _syncService.setPlaylistsSyncEnabled(v);
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: p.primary,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.r16)),
              ),
              icon: Icon(Icons.sync_rounded, color: Colors.black),
              label: Text(
                _isSyncing ? context.l10n.settingsSyncing : context.l10n.syncNow,
                style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.callout),
              ),
              onPressed: _isSyncing ? null : _performSync,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _SyncScopeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SyncScopeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.r12),
            ),
            child: Icon(icon, color: p.primary, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: AppFontSize.body,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: AppFontSize.label, color: p.textSecondary),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
