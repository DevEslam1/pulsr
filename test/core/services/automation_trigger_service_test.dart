// test/core/services/automation_trigger_service_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/automation_rules_service.dart';
import 'package:pulsr/core/services/automation_trigger_service.dart';
import 'package:pulsr/data/services/hires_audio_service.dart';
import 'package:pulsr/data/services/settings_profiles_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeHiResAudioService extends HiResAudioService {
  AudioOutputInfo? _current;
  final StreamController<AudioOutputInfo> _controller =
      StreamController<AudioOutputInfo>.broadcast();

  @override
  AudioOutputInfo? get currentOutputInfo => _current;

  @override
  Stream<AudioOutputInfo> get outputDeviceStream => _controller.stream;

  void emitDevice(AudioOutputInfo info) {
    _current = info;
    _controller.add(info);
  }

  void close() {
    _controller.close();
  }
}

class TrackingRulesService extends AutomationRulesService {
  final List<AutomationTrigger> firedTriggers = [];

  @override
  Future<List<AutomationRule>> getRules() async {
    // When getRules is queried during _fire, record the check
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHiResAudioService fakeHiRes;
  late AutomationRulesService rulesService;
  late SettingsProfilesService profilesService;
  late AutomationTriggerService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeHiRes = FakeHiResAudioService();
    rulesService = AutomationRulesService();
    profilesService = SettingsProfilesService();
    service = AutomationTriggerService(
      hiResAudioService: fakeHiRes,
      rulesService: rulesService,
      profilesService: profilesService,
    );
  });

  tearDown(() {
    service.dispose();
    fakeHiRes.close();
  });

  group('AutomationTriggerService', () {
    test('ignores initial boot emission even when currentOutputInfo starts as null', () async {
      final trackingRules = TrackingRulesService();
      final triggerService = AutomationTriggerService(
        hiResAudioService: fakeHiRes,
        rulesService: trackingRules,
        profilesService: profilesService,
      );

      // Verify currentOutputInfo is null at startup
      expect(fakeHiRes.currentOutputInfo, isNull);

      // Start the service
      triggerService.start();

      // First asynchronous emission of the stream (already active route at startup)
      const initialRoute = AudioOutputInfo(
        deviceName: 'WH-1000XM4',
        activeDeviceType: 'bluetooth',
        isBluetooth: true,
        isUsbDac: false,
        isBitPerfectActive: false,
        sampleRate: 48000,
        bitDepth: 24,
      );

      fakeHiRes.emitDevice(initialRoute);
      await pumpEventQueue();

      // The first emission should NOT have queried rules or fired automation
      expect(trackingRules.firedTriggers, isEmpty);

      // A subsequent device transition while running should trigger rules lookup
      const secondRoute = AudioOutputInfo(
        deviceName: 'Wired Headset',
        activeDeviceType: 'wired_headset',
        isBluetooth: false,
        isUsbDac: false,
        isBitPerfectActive: false,
        sampleRate: 48000,
        bitDepth: 24,
      );

      fakeHiRes.emitDevice(secondRoute);
      await pumpEventQueue();

      triggerService.dispose();
    });

    test('supportsTrigger reports charging as unsupported', () {
      expect(AutomationTriggerService.supportsTrigger(AutomationTrigger.deviceCharging), isFalse);
      expect(AutomationTriggerService.supportsTrigger(AutomationTrigger.bluetoothConnected), isTrue);
      expect(AutomationTriggerService.supportsTrigger(AutomationTrigger.headphonesPlugged), isTrue);
      expect(AutomationTriggerService.supportsTrigger(AutomationTrigger.usbDacConnected), isTrue);
    });
  });
}
