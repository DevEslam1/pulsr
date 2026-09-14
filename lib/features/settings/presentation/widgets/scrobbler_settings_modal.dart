// lib/features/settings/presentation/widgets/scrobbler_settings_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/scrobbler_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';

void showScrobblerSettingsModal(BuildContext context) {
  final p = context.palette;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const ScrobblerConfigSheet(),
  );
}

class ScrobblerConfigSheet extends StatefulWidget {
  const ScrobblerConfigSheet({super.key});

  @override
  State<ScrobblerConfigSheet> createState() => _ScrobblerConfigSheetState();
}

class _ScrobblerConfigSheetState extends State<ScrobblerConfigSheet> {
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

  @override
  void dispose() {
    _listenBrainzTokenController.dispose();
    _lastFmApiKeyController.dispose();
    _lastFmSecretController.dispose();
    _lastFmSessionKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadScrobblerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final secureStorage = getIt<FlutterSecureStorage>();
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
    if (!mounted) return;
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
    final secureStorage = getIt<FlutterSecureStorage>();
    await prefs.setBool(
        ScrobblerService.keyListenBrainzEnabled, _listenBrainzEnabled);
    final lbToken = _listenBrainzTokenController.text.trim();
    if (lbToken.isNotEmpty) {
      await secureStorage.write(
          key: ScrobblerService.keyListenBrainzTokenSecure, value: lbToken);
    } else {
      await secureStorage.delete(
          key: ScrobblerService.keyListenBrainzTokenSecure);
      await prefs.remove(ScrobblerService.keyListenBrainzToken);
    }

    await prefs.setBool(ScrobblerService.keyLastFmEnabled, _lastFmEnabled);
    final lKey = _lastFmApiKeyController.text.trim();
    final lSec = _lastFmSecretController.text.trim();
    final lSession = _lastFmSessionKeyController.text.trim();

    if (lKey.isNotEmpty) {
      await secureStorage.write(
          key: ScrobblerService.keyLastFmApiKeySecure, value: lKey);
    } else {
      await secureStorage.delete(key: ScrobblerService.keyLastFmApiKeySecure);
      await prefs.remove(ScrobblerService.keyLastFmApiKey);
    }

    if (lSec.isNotEmpty) {
      await secureStorage.write(
          key: ScrobblerService.keyLastFmSecretSecure, value: lSec);
    } else {
      await secureStorage.delete(key: ScrobblerService.keyLastFmSecretSecure);
      await prefs.remove(ScrobblerService.keyLastFmSecret);
    }

    if (lSession.isNotEmpty) {
      await secureStorage.write(
          key: ScrobblerService.keyLastFmSessionKeySecure, value: lSession);
    } else {
      await secureStorage.delete(
          key: ScrobblerService.keyLastFmSessionKeySecure);
      await prefs.remove(ScrobblerService.keyLastFmSessionKey);
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.scrobblerSaved)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: 24 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.equalizer_rounded, color: p.accent, size: 24),
                const SizedBox(width: 8),
                Text(
                  context.l10n.scrobblerSettings,
                  style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.listenBrainzRestScrobbler,
              style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.enableListenBrainz,
                  style: TextStyle(color: p.textPrimary, fontSize: 14)),
              value: _listenBrainzEnabled,
              activeThumbColor: p.accent,
              onChanged: (val) =>
                  setState(() => _listenBrainzEnabled = val),
            ),
            if (_listenBrainzEnabled) ...[
              TextField(
                controller: _listenBrainzTokenController,
                style: TextStyle(color: p.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: context.l10n.userToken,
                  hintText: context.l10n.enterListenBrainzUserToken,
                  labelStyle: TextStyle(color: p.textSecondary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Divider(color: p.hairline),
            const SizedBox(height: 12),
            Text(
              context.l10n.lastFmRestScrobbler,
              style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.enableLastFmDirectScrobbling,
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
                  labelText: context.l10n.lastFmApiKey,
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
                  labelText: context.l10n.lastFmSharedSecret,
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
                  labelText: context.l10n.lastFmSessionKey,
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
                child: Text(context.l10n.saveSettings,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.black)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
