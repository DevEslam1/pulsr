import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../data/services/cloud_sync_service.dart';
import '../../../core/theme/aura_theme.dart';

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
  bool _syncHistory = true;
  bool _syncEqPresets = true;
  bool _syncSettings = true;

  @override
  void initState() {
    super.initState();
    _syncService = widget.syncService ?? getIt<CloudSyncService>();
  }

  Future<void> _performSync() async {
    setState(() => _isSyncing = true);
    final success = await _syncService.syncAll();
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Cloud backup & sync completed!'
              : 'Sync failed. Please check internet connection.'),
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
        lastSync != null ? '${lastSync.toLocal()}'.split('.').first : 'Never';

    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.surface,
        elevation: 0,
        title: Text(
          'Cloud Backup & Sync',
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          // Cloud Status Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: p.surfaceCard,
              borderRadius: BorderRadius.circular(20),
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
                        const SizedBox(width: 10),
                        Text(
                          'Cloud Storage Status',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: p.textPrimary),
                        ),
                      ],
                    ),
                    if (_isSyncing)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: p.primary),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Encrypted bidirectional Firestore backup across all your devices.',
                  style: TextStyle(fontSize: 13, color: p.textSecondary),
                ),
                const SizedBox(height: 14),
                Divider(color: p.hairline),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Last Synced:',
                        style: TextStyle(color: p.textSecondary, fontSize: 13)),
                    Text(lastSyncStr,
                        style: TextStyle(
                            color: p.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Selective Backup Targets',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: p.textPrimary),
          ),
          const SizedBox(height: 12),

          CheckboxListTile(
            title: Text('Starred & Favorite Songs',
                style: TextStyle(color: p.textPrimary)),
            value: _syncFavorites,
            activeColor: p.primary,
            onChanged: (val) => setState(() => _syncFavorites = val ?? true),
          ),
          CheckboxListTile(
            title: Text('Playlists & Smart Rules',
                style: TextStyle(color: p.textPrimary)),
            value: _syncPlaylists,
            activeColor: p.primary,
            onChanged: (val) => setState(() => _syncPlaylists = val ?? true),
          ),
          CheckboxListTile(
            title: Text('Play History & Track Counters',
                style: TextStyle(color: p.textPrimary)),
            value: _syncHistory,
            activeColor: p.primary,
            onChanged: (val) => setState(() => _syncHistory = val ?? true),
          ),
          CheckboxListTile(
            title: Text('Custom EQ Presets & DSP',
                style: TextStyle(color: p.textPrimary)),
            value: _syncEqPresets,
            activeColor: p.primary,
            onChanged: (val) => setState(() => _syncEqPresets = val ?? true),
          ),
          CheckboxListTile(
            title: Text('App Settings & Theme Profiles',
                style: TextStyle(color: p.textPrimary)),
            value: _syncSettings,
            activeColor: p.primary,
            onChanged: (val) => setState(() => _syncSettings = val ?? true),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: p.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              icon: Icon(Icons.sync_rounded, color: Colors.black),
              label: Text(
                _isSyncing ? 'Syncing...' : 'Sync Now',
                style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
              onPressed: _isSyncing ? null : _performSync,
            ),
          ),
        ],
      ),
    );
  }
}
