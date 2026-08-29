import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/auth/utils/google_login_recovery.dart';

void main() {
  group('GoogleBlockRecovery ladder state machine', () {
    test('ladder flips desktop → mobile → desktop then exhausts', () {
      final r = GoogleBlockRecovery();
      expect(r.exhausted, isFalse);
      expect(r.identity, BrowserIdentity.desktop);

      final s1 = r.onBlocked();
      expect(s1, isNotNull);
      expect(s1!.nextIdentity, BrowserIdentity.mobile);
      expect(r.attempt, 1);

      final s2 = r.onBlocked();
      expect(s2, isNotNull);
      expect(s2!.nextIdentity, BrowserIdentity.desktop);
      expect(r.attempt, 2);
      expect(r.exhausted, isTrue);

      // Third block: stop — never loop.
      expect(r.onBlocked(), isNull);
      expect(r.attempt, 2);
    });

    test('reset() allows a fresh manual full ladder', () {
      final r = GoogleBlockRecovery();
      r.onBlocked();
      r.onBlocked();
      expect(r.onBlocked(), isNull);

      r.reset();
      expect(r.exhausted, isFalse);
      expect(r.attempt, 0);

      final s = r.onBlocked();
      expect(s, isNotNull);
      expect(s!.nextIdentity, BrowserIdentity.mobile);
    });

    test('respects a custom maxAttempts', () {
      final r = GoogleBlockRecovery(maxAttempts: 1);
      expect(r.onBlocked(), isNotNull);
      expect(r.onBlocked(), isNull);
    });

    test('initial identity is preserved in the first flip target', () {
      final r = GoogleBlockRecovery(initialIdentity: BrowserIdentity.mobile);
      final s = r.onBlocked();
      expect(s!.nextIdentity, BrowserIdentity.desktop);
    });
  });
}
