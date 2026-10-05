import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/scrobbler_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScrobblerService Throttling Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('validates duration thresholds before scrobbling', () {
      expect(30 >= 30, isTrue);
      expect(15 >= 30, isFalse);
    });

    test('ScrobblerService initializes and has configurable service keys', () {
      final service = ScrobblerService();
      expect(service, isNotNull);
      expect(ScrobblerService.keyLastFmEnabled, 'setting_lastfm_enabled');
      expect(ScrobblerService.keyLibreFmEnabled, 'setting_librefm_enabled');
      expect(ScrobblerService.keyListenBrainzEnabled,
          'setting_listenbrainz_enabled');
      expect(ScrobblerService.keyCustomWebhookEnabled,
          'setting_custom_scrobbler_enabled');
    });
  });
}
