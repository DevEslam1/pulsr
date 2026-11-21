import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/config/app_config.dart';
import 'package:pulsr/core/services/bluetooth_latency_calibrator.dart';
import 'package:pulsr/core/services/lrclib_service.dart';
import 'package:pulsr/core/services/radio_station_store.dart';
import 'package:pulsr/domain/models/radio_station.dart';
import 'package:pulsr/data/usecases/backup_usecases.dart';

void main() {
  test('7 lyrics batch: empty + blank titles short-circuit without network',
      () async {
    final svc = LrclibService();
    expect(await svc.fetchMissingLyrics([]), isEmpty);
    expect(
        await svc.fetchMissingLyrics([
          {'title': '', 'artist': 'X'},
          {'title': '   ', 'artist': 'Y'},
        ]),
        isEmpty);
    svc.dispose();
  });

  test('12 radio curated directory imports without dupes', () async {
    final dir = RadioStationStore.curatedDirectory();
    expect(dir.length, greaterThanOrEqualTo(8));
    for (final s in dir) {
      expect(RadioStation.isHttpUrl(s.url), isTrue);
    }
    final store = RadioStationStore();
    await store.ready;
    final added1 = await store.importCurated();
    expect(added1, dir.length);
    final added2 = await store.importCurated();
    expect(added2, 0);
  });

  test('13 backup v5 schema accepts version 5, rejects 6', () {
    ImportBackupUseCase.validateSchema({'version': 5, 'favorites': []});
    expect(() => ImportBackupUseCase.validateSchema({'version': 6}),
        throwsFormatException);
    // v4 and v3 still accepted (backwards compatible).
    ImportBackupUseCase.validateSchema({'version': 4, 'favorites': []});
    ImportBackupUseCase.validateSchema({'version': 3, 'favorites': []});
  });

  test('10 pure runtime check returns null-or-bool without crash', () async {
    final r = await AppConfig.verifyPureNoInternet();
    expect(r, anyOf(isNull, isA<bool>()));
  });

  test('tap calibration still green', () {
    expect(
      BluetoothLatencyCalibrator()
          .offsetFromTapDeltas([428, 432, 431, 429, 433, 430]),
      251,
    );
  });
}
