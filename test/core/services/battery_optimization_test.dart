import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/battery_optimization_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BatteryOptimizationService Tests', () {
    test('Identifies aggressive OEMs correctly', () {
      expect(BatteryOptimizationService.isAggressiveOem('Xiaomi'), isTrue);
      expect(BatteryOptimizationService.isAggressiveOem('Redmi'), isTrue);
      expect(BatteryOptimizationService.isAggressiveOem('POCO'), isTrue);
      expect(BatteryOptimizationService.isAggressiveOem('Huawei'), isTrue);
      expect(BatteryOptimizationService.isAggressiveOem('Samsung'), isTrue);
      expect(BatteryOptimizationService.isAggressiveOem('Google'), isFalse);
    });

    test('Generates valid DontKillMyApp links for OEM', () {
      expect(BatteryOptimizationService.getDontKillMyAppUrl('Xiaomi'),
          'https://dontkillmyapp.com/xiaomi');
      expect(BatteryOptimizationService.getDontKillMyAppUrl('Huawei'),
          'https://dontkillmyapp.com/huawei');
      expect(BatteryOptimizationService.getDontKillMyAppUrl('Pixel'),
          'https://dontkillmyapp.com');
    });

    test('Manages dismissal state via SharedPreferences', () async {
      expect(await BatteryOptimizationService.isCardDismissed(), isFalse);
      await BatteryOptimizationService.dismissCard();
      expect(await BatteryOptimizationService.isCardDismissed(), isTrue);
    });
  });
}
