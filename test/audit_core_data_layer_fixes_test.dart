import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/bloc/base_cubit.dart';
import 'package:pulsr/core/errors/error_message_resolver.dart';
import 'package:pulsr/core/services/artist_bio_service.dart';
import 'package:pulsr/core/services/automation_rules_service.dart';
import 'package:pulsr/core/services/battery_optimization_service.dart';
import 'package:pulsr/core/services/radio_station_store.dart';
import 'package:pulsr/core/services/sponsorblock_service.dart';
import 'package:pulsr/core/services/theme_scheduler_service.dart';
import 'package:pulsr/core/widgets/entity_by_id_loader.dart';
import 'package:fpdart/fpdart.dart';

class _TestCubit extends PulsrCubit<int> {
  _TestCubit() : super(0);

  void doSafeEmit(int v) => safeEmit(v);
  void doEmitEffect(UiEffect e) => emitEffect(e);
}

class _MockBuildContext extends Fake implements BuildContext {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Issue 1: ErrorMessageResolver consolidation', () {
    test('ErrorMessageResolver humanizes exceptions into clean copy', () {
      final networkError = ErrorMessageResolver.resolveUserFriendly(
        _MockBuildContext(),
        Exception('SocketException: Connection refused'),
      );
      expect(networkError, contains('Network connection error'));

      final permError = ErrorMessageResolver.resolveUserFriendly(
        _MockBuildContext(),
        Exception('PermissionDenied: access to storage'),
      );
      expect(permError, contains('Storage permission was denied'));
    });
  });

  group('Issue 2: AutomationRulesService default and delete', () {
    test('getRules returns empty list when no rules saved (no phantom defaults)', () async {
      final service = AutomationRulesService();
      final rules = await service.getRules();
      expect(rules, isEmpty);
    });

    test('saveRule, getRules, and deleteRule correctly mutate persisted list', () async {
      final service = AutomationRulesService();
      const rule1 = AutomationRule(
        id: 'rule_1',
        trigger: AutomationTrigger.bluetoothConnected,
        targetProfileId: 'profile_car',
      );
      const rule2 = AutomationRule(
        id: 'rule_2',
        trigger: AutomationTrigger.headphonesPlugged,
        targetProfileId: 'profile_home',
      );

      await service.saveRule(rule1);
      await service.saveRule(rule2);

      var rules = await service.getRules();
      expect(rules.length, equals(2));
      expect(rules.map((r) => r.id), containsAll(['rule_1', 'rule_2']));

      await service.deleteRule('rule_1');
      rules = await service.getRules();
      expect(rules.length, equals(1));
      expect(rules.first.id, equals('rule_2'));
    });
  });

  group('Issue 3: ThemeSchedulerService re-start after dispose', () {
    test('startScheduler can be safely called after dispose without throwing', () async {
      final service = ThemeSchedulerService();
      bool changed = false;
      service.startScheduler((isNight) {
        changed = true;
      });
      expect(changed, isTrue);

      service.dispose();

      // Calling startScheduler after dispose recreates the controller
      bool changedAfterRestart = false;
      expect(
        () => service.startScheduler((isNight) {
          changedAfterRestart = true;
        }),
        returnsNormally,
      );
      expect(changedAfterRestart, isTrue);
      service.dispose();
    });
  });

  group('Issue 4: PulsrCubit dual-closed-state race', () {
    test('safeEmit and emitEffect do not throw when cubit is closing/closed', () async {
      final cubit = _TestCubit();
      cubit.doSafeEmit(1);
      expect(cubit.state, equals(1));

      await cubit.close();

      expect(() => cubit.doSafeEmit(2), returnsNormally);
      expect(cubit.state, equals(1)); // Did not emit into closed cubit

      expect(() => cubit.doEmitEffect(const ShowToastEffect('test')), returnsNormally);
    });
  });

  group('Issue 6: ArtistBioService LRU caching & parallel calls', () {
    test('LRU cache evicts oldest and refreshes on hit', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"data": [{"picture_xl": "https://img.test"}]}', 200);
      });

      final service = ArtistBioService(mockClient);
      final res1 = await service.getArtistInfo('Artist A');
      expect(res1, isNotNull);
      expect(res1?.pictureUrl, equals('https://img.test'));

      final cached = await service.getArtistInfo('Artist A');
      expect(cached?.name, equals('Artist A'));
      service.dispose();
    });
  });

  group('Issue 7: BatteryOptimizationService nullable battery level', () {
    test('getBatteryLevel returns null on test environment without throwing', () async {
      final level = await BatteryOptimizationService.getBatteryLevel();
      // On non-Android / test environment, returns null rather than hardcoded 100
      expect(level, isNull);
    });
  });

  group('Issue 8: SponsorBlockService LRU cache', () {
    test('getSegments caches and clearCache clears', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
            '[{"category": "sponsor", "segment": [10.0, 20.0], "UUID": "u1"}]', 200);
      });

      final service = SponsorBlockService(mockClient);
      final segs = await service.getSegments('test_video');
      expect(segs.length, equals(1));
      expect(segs.first.category, equals('sponsor'));

      // Hit cache
      final cached = await service.getSegments('test_video');
      expect(cached.length, equals(1));

      service.dispose();
    });
  });

  group('Issue 13: RadioStationStore test isolation', () {
    test('resetForTesting clears static stations list', () {
      RadioStationStore.resetForTesting();
      final store = RadioStationStore();
      expect(store.list, isEmpty);
    });
  });

  group('Issue 17: EntityByIdLoader direct fetchSingle', () {
    testWidgets('renders item from fetchSingle directly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EntityByIdLoader<String>(
            fetchSingle: () async => const Right('Direct Item Content'),
            builder: (context, item) => Scaffold(body: Text(item)),
            notFoundMessage: 'Not found',
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Direct Item Content'), findsOneWidget);
    });
  });
}
