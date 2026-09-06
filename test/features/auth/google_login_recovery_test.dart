// test/features/auth/google_login_recovery_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/auth/utils/google_login_recovery.dart';

void main() {
  group('GoogleBlockRecovery', () {
    test('the ladder advances instead of oscillating between two rungs', () {
      final recovery =
          GoogleBlockRecovery(maxAttempts: 4, initialIdentity: BrowserIdentity.mobile);

      // Picking "the first entry that differs from the current one" sent the
      // ladder mobile → safariMobile → mobile → safariMobile forever, so a
      // desktop identity — the one most likely to clear a mobile-flagged
      // block — was never presented.
      expect(recovery.onBlocked()!.nextIdentity,
          equals(BrowserIdentity.safariMobile));
      expect(recovery.onBlocked()!.nextIdentity, equals(BrowserIdentity.desktop));
      expect(recovery.onBlocked()!.nextIdentity,
          equals(BrowserIdentity.chromeDesktop));
      expect(recovery.onBlocked()!.nextIdentity, equals(BrowserIdentity.mobile));
    });

    test('never returns the identity it was already presenting', () {
      var identity = BrowserIdentity.desktop;
      final recovery =
          GoogleBlockRecovery(maxAttempts: 8, initialIdentity: identity);
      for (var i = 0; i < 8; i++) {
        final step = recovery.onBlocked()!;
        expect(step.nextIdentity, isNot(equals(identity)),
            reason: 'reloading with the same UA repeats the blocked request');
        identity = step.nextIdentity;
      }
    });

    test('stops rather than looping once the attempts are spent', () {
      final recovery = GoogleBlockRecovery(maxAttempts: 2);
      expect(recovery.onBlocked(), isNotNull);
      expect(recovery.onBlocked(), isNotNull);
      expect(recovery.exhausted, isTrue);
      expect(recovery.onBlocked(), isNull,
          reason: 'the sheet shows the manual recovery card instead');
    });

    test('a manual retry re-arms the ladder from the current identity', () {
      final recovery =
          GoogleBlockRecovery(maxAttempts: 2, initialIdentity: BrowserIdentity.mobile);
      recovery.onBlocked();
      recovery.onBlocked();
      expect(recovery.onBlocked(), isNull);

      recovery.reset();

      expect(recovery.attempt, isZero);
      // Resumes where it stopped (desktop → chromeDesktop) rather than
      // re-trying the identities that were just refused.
      expect(recovery.identity, equals(BrowserIdentity.desktop));
      expect(recovery.onBlocked()!.nextIdentity,
          equals(BrowserIdentity.chromeDesktop));
    });
  });
}
