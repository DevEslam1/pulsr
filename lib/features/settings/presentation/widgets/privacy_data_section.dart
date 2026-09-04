// lib/features/settings/presentation/widgets/privacy_data_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/scrobbler_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../cubit/settings_state.dart';
import 'backup_section.dart';
import 'settings_section.dart';
import 'settings_tiles.dart';

/// Cloud backup, scrobbling and privacy guarantees.
class PrivacyDataSection extends StatelessWidget {
  final SettingsState state;

  const PrivacyDataSection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SettingsSection(
      icon: Icons.security_rounded,
      title: context.l10n.privacyAndData,
      children: [
        const BackupSection(),
        settingsCardDivider(p),
        SettingsNavTile(
          Icons.equalizer_outlined,
          'Scrobbling (Last.fm & ListenBrainz)',
          'Direct API scrobbling and Now Playing notifications',
          onTap: () => _showScrobblerSettingsModal(context),
        ),
        settingsCardDivider(p),
        SettingsNavTile(
            Icons.security_rounded,
            context.l10n.privacyGuarantee,
            context.l10n.privacyGuaranteeSubtitle,
            onTap: () {}),
      ],
    );
  }
}

void _showScrobblerSettingsModal(BuildContext context) {
  final p = context.palette;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _ScrobblerConfigSheet(),
  );
}

class _ScrobblerConfigSheet extends StatefulWidget {
  const _ScrobblerConfigSheet();

  @override
  State<_ScrobblerConfigSheet> createState() => _ScrobblerConfigSheetState();
}

class _ScrobblerConfigSheetState extends State<_ScrobblerConfigSheet> {
  bool _listenBrainzEnabled = false;
  final _listenBrainzTokenController = TextEditingController();

  bool _lastFmEnabled = false;
  final _lastFmApiKeyController = TextEditingController();
  final _lastFmSecretController = TextEditingController();
  final _lastFmSessionKeyController = TextEditingController();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadScrobblerPrefs();
  }

  Future<void> _loadScrobblerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();
    String lbToken = '';
    String lastFmKey = '';
    String lastFmSec = '';
    String lastFmSession = '';
    try {
      lbToken = await secureStorage.read(
              key: ScrobblerService.keyListenBrainzTokenSecure) ??
          '';
      lastFmKey = await secureStorage.read(
              key: ScrobblerService.keyLastFmApiKeySecure) ??
          '';
      lastFmSec = await secureStorage.read(
              key: ScrobblerService.keyLastFmSecretSecure) ??
          '';
      lastFmSession = await secureStorage.read(
              key: ScrobblerService.keyLastFmSessionKeySecure) ??
          '';
    } catch (_) {}
    if (lbToken.isEmpty) {
      lbToken = prefs.getString(ScrobblerService.keyListenBrainzToken) ?? '';
    }
    if (lastFmKey.isEmpty) {
      lastFmKey = prefs.getString(ScrobblerService.keyLastFmApiKey) ?? '';
    }
    if (lastFmSec.isEmpty) {
      lastFmSec = prefs.getString(ScrobblerService.keyLastFmSecret) ?? '';
    }
    if (lastFmSession.isEmpty) {
      lastFmSession =
          prefs.getString(ScrobblerService.keyLastFmSessionKey) ?? '';
    }
    setState(() {
      _listenBrainzEnabled =
          prefs.getBool(ScrobblerService.keyListenBrainzEnabled) ?? false;
      _listenBrainzTokenController.text = lbToken;

      _lastFmEnabled =
          prefs.getBool(ScrobblerService.keyLastFmEnabled) ?? false;
      _lastFmApiKeyController.text = lastFmKey;
      _lastFmSecretController.text = lastFmSec;
      _lastFmSessionKeyController.text = lastFmSession;
      _isLoading = false;
    });
  }

  Future<void> _saveScrobblerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();
    await prefs.setBool(
        ScrobblerService.keyListenBrainzEnabled, _listenBrainzEnabled);
    final lbToken = _listenBrainzTokenController.text.trim();
    if (lbToken.isNotEmpty) {
      await secureStorage.write(
          key: ScrobblerService.keyListenBrainzTokenSecure, value: lbToken);
    } else {
      await secureStorage.delete(
          key: ScrobblerService.keyListenBrainzTokenSecure);
    }
    await prefs.remove(ScrobblerService.keyListenBrainzToken);

    await prefs.setBool(ScrobblerService.keyLastFmEnabled, _lastFmEnabled);
    final lastFmKey = _lastFmApiKeyController.text.trim();
    final lastFmSec = _lastFmSecretController.text.trim();
    final lastFmSession = _lastFmSessionKeyController.text.trim();

    if (lastFmKey.isNotEmpty) {
      await secureStorage.write(
          key: ScrobblerService.keyLastFmApiKeySecure, value: lastFmKey);
    } else {
      await secureStorage.delete(key: ScrobblerService.keyLastFmApiKeySecure);
    }
    if (lastFmSec.isNotEmpty) {
      await secureStorage.write(
          key: ScrobblerService.keyLastFmSecretSecure, value: lastFmSec);
    } else {
      await secureStorage.delete(key: ScrobblerService.keyLastFmSecretSecure);
    }
    if (lastFmSession.isNotEmpty) {
      await secureStorage.write(
          key: ScrobblerService.keyLastFmSessionKeySecure,
          value: lastFmSession);
    } else {
      await secureStorage.delete(
          key: ScrobblerService.keyLastFmSessionKeySecure);
    }
    await prefs.remove(ScrobblerService.keyLastFmApiKey);
    await prefs.remove(ScrobblerService.keyLastFmSecret);
    await prefs.remove(ScrobblerService.keyLastFmSessionKey);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scrobbler configuration saved!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _listenBrainzTokenController.dispose();
    _lastFmApiKeyController.dispose();
    _lastFmSecretController.dispose();
    _lastFmSessionKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
        left: 20,
        right: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.equalizer_rounded, color: p.accent, size: 24),
                const SizedBox(width: 10),
                Text(
                  'Scrobbler Settings',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'ListenBrainz REST Scrobbler',
              style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Enable ListenBrainz',
                  style: TextStyle(color: p.textPrimary, fontSize: 14)),
              value: _listenBrainzEnabled,
              activeThumbColor: p.accent,
              onChanged: (val) => setState(() => _listenBrainzEnabled = val),
            ),
            if (_listenBrainzEnabled)
              TextField(
                controller: _listenBrainzTokenController,
                style: TextStyle(color: p.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'User Token',
                  hintText: 'Enter ListenBrainz User Token',
                  labelStyle: TextStyle(color: p.textSecondary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            const SizedBox(height: 20),
            Divider(color: p.hairline),
            const SizedBox(height: 8),
            Text(
              'Last.fm REST Scrobbler',
              style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Enable Last.fm Direct Scrobbling',
                  style: TextStyle(color: p.textPrimary, fontSize: 14)),
              value: _lastFmEnabled,
              activeThumbColor: p.accent,
              onChanged: (val) => setState(() => _lastFmEnabled = val),
            ),
            if (_lastFmEnabled) ...[
              TextField(
                controller: _lastFmApiKeyController,
                style: TextStyle(color: p.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Last.fm API Key',
                  labelStyle: TextStyle(color: p.textSecondary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lastFmSecretController,
                style: TextStyle(color: p.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Last.fm Shared Secret',
                  labelStyle: TextStyle(color: p.textSecondary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lastFmSessionKeyController,
                style: TextStyle(color: p.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Last.fm Session Key (sk)',
                  labelStyle: TextStyle(color: p.textSecondary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saveScrobblerPrefs,
                child: const Text('Save Settings',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.black)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
