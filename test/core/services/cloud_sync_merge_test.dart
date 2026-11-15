import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/cloud_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('CloudSyncService LWW Merge & Timestamps', () {
    setUp(() {
      CloudSyncService.clearLocalModifiedFavoritesForTesting();
    });

    test('extractCloudTimestamp correctly parses Firestore Timestamp', () {
      final now = DateTime.now();
      final ts = Timestamp.fromDate(now);
      final data = <String, dynamic>{'modifiedAt': ts};
      expect(CloudSyncService.extractCloudTimestamp(data), ts.millisecondsSinceEpoch);
    });

    test('extractCloudTimestamp falls back to deviceTimestamp when modifiedAt is missing', () {
      const devTime = 1699999999000;
      final data = <String, dynamic>{'deviceTimestamp': devTime};
      expect(CloudSyncService.extractCloudTimestamp(data), devTime);
    });

    test('extractCloudTimestamp returns 0 when no timestamp fields are present', () {
      expect(CloudSyncService.extractCloudTimestamp({}), 0);
    });

    test('shouldCloudWin: newer local beats stale cloud', () {
      const local = 1000;
      const staleCloud = 500;
      expect(
        CloudSyncService.shouldCloudWin(cloudTimestamp: staleCloud, localTimestamp: local),
        isFalse,
      );
    });

    test('shouldCloudWin: newer cloud beats older local', () {
      const local = 500;
      const newerCloud = 1000;
      expect(
        CloudSyncService.shouldCloudWin(cloudTimestamp: newerCloud, localTimestamp: local),
        isTrue,
      );
    });

    test('shouldCloudWin: cloud wins when local timestamp is null or zero', () {
      expect(CloudSyncService.shouldCloudWin(cloudTimestamp: 100, localTimestamp: null), isTrue);
      expect(CloudSyncService.shouldCloudWin(cloudTimestamp: 100, localTimestamp: 0), isTrue);
    });

    test('shouldCloudWin: equal timestamps break ties in favor of cloud', () {
      expect(CloudSyncService.shouldCloudWin(cloudTimestamp: 1000, localTimestamp: 1000), isTrue);
    });

    test('local favorite modification timestamp persists across restart simulation',
        () async {
      SharedPreferences.setMockInitialValues({});
      CloudSyncService.clearLocalModifiedFavoritesForTesting();

      CloudSyncService.recordLocalFavoriteModified('fav-restart-1', 5000);
      await CloudSyncService.flushLocalModifiedFavoritesForTesting();

      CloudSyncService.simulateRestartForTesting();
      final restored =
          await CloudSyncService.localFavoriteModifiedAtForTesting('fav-restart-1');

      expect(restored, equals(5000));
      expect(
        CloudSyncService.shouldCloudWin(
          cloudTimestamp: 3000,
          localTimestamp: restored,
        ),
        isFalse,
      );
    });
  });
}
