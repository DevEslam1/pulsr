import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/restore_detection_service.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMediaScannerService mockScanner;

  setUp(() {
    mockScanner = MockMediaScannerService();
    SharedPreferences.setMockInitialValues({});
  });

  group('RestoreDetectionService Tests', () {
    test('First fresh run sets token and returns false', () async {
      when(() => mockScanner.checkPermission()).thenAnswer((_) async => true);
      when(() => mockScanner.scanDeviceLibrary()).thenAnswer((_) async => 0);

      final result = await RestoreDetectionService.checkAndHandleRestore(mockScanner);
      expect(result, isFalse);
    });
  });
}
