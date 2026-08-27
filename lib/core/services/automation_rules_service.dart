// lib/core/services/automation_rules_service.dart
import 'dart:convert';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_logger.dart';

enum AutomationTrigger {
  bluetoothConnected('Bluetooth Connected'),
  headphonesPlugged('Headphones Plugged In'),
  deviceCharging('Device Charging');

  final String label;
  const AutomationTrigger(this.label);
}

class AutomationRule {
  final String id;
  final AutomationTrigger trigger;
  final String targetProfileId;
  final bool enabled;

  const AutomationRule({
    required this.id,
    required this.trigger,
    required this.targetProfileId,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'trigger': trigger.name,
        'targetProfileId': targetProfileId,
        'enabled': enabled,
      };

  factory AutomationRule.fromJson(Map<String, dynamic> json) => AutomationRule(
        id: json['id'] as String,
        trigger: AutomationTrigger.values.firstWhere(
          (t) => t.name == json['trigger'],
          orElse: () => AutomationTrigger.bluetoothConnected,
        ),
        targetProfileId: json['targetProfileId'] as String,
        enabled: json['enabled'] as bool? ?? true,
      );
}

@singleton
class AutomationRulesService {
  static const String _keyRules = 'setting_automation_rules';

  Future<List<AutomationRule>> getRules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_keyRules);
      if (jsonStr != null) {
        final list = json.decode(jsonStr) as List<dynamic>;
        return list.map((e) => AutomationRule.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to load automation rules', error: e, stackTrace: st, category: 'AutomationRulesService');
    }
    return const [
      AutomationRule(
        id: 'rule_car_bt',
        trigger: AutomationTrigger.bluetoothConnected,
        targetProfileId: 'profile_car',
      ),
      AutomationRule(
        id: 'rule_headphones',
        trigger: AutomationTrigger.headphonesPlugged,
        targetProfileId: 'profile_home',
      ),
    ];
  }

  Future<void> saveRule(AutomationRule rule) async {
    final rules = await getRules();
    final updated = List<AutomationRule>.from(rules);
    final idx = updated.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      updated[idx] = rule;
    } else {
      updated.add(rule);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRules, json.encode(updated.map((r) => r.toJson()).toList()));
  }
}
