// test/core/services/automation_rules_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/automation_rules_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AutomationRulesService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = AutomationRulesService();
  });

  group('AutomationRulesService', () {
    test('getRules returns empty list initially', () async {
      expect(await service.getRules(), isEmpty);
    });

    test('saveRule, deleteRule, and clearRules persist correctly', () async {
      const rule1 = AutomationRule(
        id: 'r1',
        trigger: AutomationTrigger.headphonesPlugged,
        targetProfileId: 'p1',
      );
      await service.saveRule(rule1);

      var rules = await service.getRules();
      expect(rules.length, 1);
      expect(rules.first.id, 'r1');

      const rule2 = AutomationRule(
        id: 'r2',
        trigger: AutomationTrigger.usbDacConnected,
        targetProfileId: 'p2',
      );
      await service.saveRule(rule2);

      rules = await service.getRules();
      expect(rules.length, 2);

      await service.deleteRule('r1');
      rules = await service.getRules();
      expect(rules.length, 1);
      expect(rules.first.id, 'r2');

      await service.clearRules();
      expect(await service.getRules(), isEmpty);
    });

    test('concurrent saveRule calls serialize without overwriting each other', () async {
      final futures = List.generate(
        10,
        (i) => service.saveRule(
          AutomationRule(
            id: 'rule_$i',
            trigger: AutomationTrigger.bluetoothConnected,
            targetProfileId: 'prof_$i',
          ),
        ),
      );

      await Future.wait(futures);

      final rules = await service.getRules();
      expect(rules.length, 10);
    });
  });
}
