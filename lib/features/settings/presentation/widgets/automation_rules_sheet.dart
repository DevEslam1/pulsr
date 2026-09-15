// lib/features/settings/presentation/widgets/automation_rules_sheet.dart
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/automation_rules_service.dart';
import '../../../../core/services/automation_trigger_service.dart';
import '../../../../core/services/settings_profiles_service.dart';
import '../../../../core/theme/aura_theme.dart';

void showAutomationRulesSheet(BuildContext context) {
  final p = context.palette;
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: p.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const AutomationRulesSheet(),
  );
}

class AutomationRulesSheet extends StatefulWidget {
  const AutomationRulesSheet({super.key});

  @override
  State<AutomationRulesSheet> createState() => _AutomationRulesSheetState();
}

class _AutomationRulesSheetState extends State<AutomationRulesSheet> {
  final AutomationRulesService _rulesService = getIt<AutomationRulesService>();
  final SettingsProfilesService _profilesService =
      getIt<SettingsProfilesService>();

  List<AutomationRule> _rules = const [];
  Map<String, String> _profileNames = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rules = await _rulesService.getRules();
      final profiles = await _profilesService.getProfiles();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _profileNames = {for (final p in profiles) p.id: p.name};
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(AutomationRule rule, bool value) async {
    final updated = rule.copyWith(enabled: value);
    setState(() {
      _rules = [
        for (final r in _rules) if (r.id == rule.id) updated else r,
      ];
    });
    await _rulesService.saveRule(updated);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: p.accent, size: 24),
                  const SizedBox(width: 10),
                  Text(context.l10n.automationRules,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(context.l10n.automationRulesDesc,
                style: TextStyle(color: p.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_rules.isEmpty)
                Text(context.l10n.noAutomationRules,
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final rule in _rules) _ruleTile(p, rule),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ruleTile(PulsrPalette p, AutomationRule rule) {
    final supported = AutomationTriggerService.supportsTrigger(rule.trigger);
    final profileName =
        _profileNames[rule.targetProfileId] ?? rule.targetProfileId;
    final IconData icon;
    switch (rule.trigger) {
      case AutomationTrigger.bluetoothConnected:
        icon = Icons.bluetooth_rounded;
        break;
      case AutomationTrigger.headphonesPlugged:
        icon = Icons.headphones_rounded;
        break;
      case AutomationTrigger.deviceCharging:
        icon = Icons.battery_charging_full_rounded;
        break;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: p.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: SwitchListTile(
        value: rule.enabled && supported,
        onChanged: supported ? (v) => _toggle(rule, v) : null,
        secondary: Icon(
          icon,
          color: supported ? p.accent : p.textTertiary,
        ),
        title: Text(
          rule.trigger.label,
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          supported ? 'Apply: $profileName' : 'Not detectable on this platform',
          style: TextStyle(
            color: supported ? p.textSecondary : p.error,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
