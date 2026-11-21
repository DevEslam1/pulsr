import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/party/listen_together_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ListenTogetherService', () {
    test('resets lastHandledSeq to -1 on leaveParty across rooms', () async {
      final service = ListenTogetherService();
      addTearDown(() => service.dispose());

      expect(service.lastHandledSeq, equals(-1));

      // Simulate handling updates in Room A up to seq 42
      service.debugLastHandledSeq = 42;
      expect(service.lastHandledSeq, equals(42));

      // Leave Room A
      await service.leaveParty();

      // Verify sequence is reset so Room B (starting at seq 0 or low seq) is not dropped
      expect(service.lastHandledSeq, equals(-1),
          reason: 'lastHandledSeq must be reset to -1 so new room updates are not ignored');
    });
  });
}
