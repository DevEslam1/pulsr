// lib/features/settings/presentation/widgets/automation_rules_sheet.dart
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/automation_rules_service.dart';
import '../../../../core/services/automation_trigger_service.dart';
import '../../../../core/services/settings_profiles_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_switch.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

void showAutomationRulesSheet(BuildContext context) {
  PulsrSheetHelper.showPulsrSheet<void>(
    context: context,
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

  Future<void> _delete(AutomationRule rule, int index) async {
    setState(() {
      _rules = _rules.where((r) => r.id != rule.id).toList();
    });
    await _rulesService.deleteRule(rule.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(rule.trigger.label),
        action: SnackBarAction(
          label: context.l10n.undo,
          onPressed: () async {
            await _rulesService.saveRule(rule);
            if (mounted) {
              setState(() {
                final list = List<AutomationRule>.from(_rules);
                if (index <= list.length) {
                  list.insert(index, rule);
                } else {
                  list.add(rule);
                }
                _rules = list;
              });
            }
          },
        ),
      ),
    );
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
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.s20, AppSpacing.s20, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: p.accent, size: 24),
                  const SizedBox(width: AppSpacing.s10),
                  Text(context.l10n.automationRules,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: AppFontSize.title,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s6),
              Text(context.l10n.automationRulesDesc,
                style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_rules.isEmpty)
                Text(context.l10n.noAutomationRules,
                  style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
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
    return Dismissible(
      key: ValueKey(rule.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.s10),
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppRadii.r16),
        ),
        child: Icon(Icons.delete_outline_rounded, color: p.error),
      ),
      onDismissed: (_) => _delete(rule, _rules.indexOf(rule)),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.s10),
        decoration: BoxDecoration(
          color: p.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadii.r16),
          border: Border.all(color: p.hairline),
        ),
        child: PulsrSwitchListTile(
          value: rule.enabled && supported,
          onChanged: supported ? (v) => _toggle(rule, v) : null,
          leading: Icon(
            icon,
            color: supported ? p.accent : p.textTertiary,
          ),
          title: Text(
            rule.trigger.label,
            style: TextStyle(
              color: p.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: AppFontSize.body,
            ),
          ),
          subtitle: Text(
            supported
                ? context.l10n.settingsApplyProfileName(profileName)
                : context.l10n.settingsNotDetectable,
            style: TextStyle(
              color: supported ? p.textSecondary : p.error,
              fontSize: AppFontSize.label,
            ),
          ),
        ),
      ),
    );
  }
}
