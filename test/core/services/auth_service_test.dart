// test/core/services/auth_service_test.dart
//
// AuthService is a thin wrapper over FirebaseAuth + GoogleSignIn. Both are
// platform plugins that must never be reached for real in a unit test. In the
// test environment no Firebase app is configured and no platform handler is
// registered, so `initialize()` deterministically falls back to
// `_isFirebaseAvailable == false` and every networked entry point throws. These
// tests pin that degradation path — the exact behaviour the app relies on when
// Firebase is unavailable on a device.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService when Firebase is unavailable', () {
    late AuthService service;

    setUp(() {
      service = AuthService();
    });

    test('reports Firebase unavailable before initialize()', () {
      expect(service.isFirebaseAvailable, isFalse);
    });

    test('initialize() degrades gracefully instead of throwing', () async {
      await service.initialize();
      expect(service.isFirebaseAvailable, isFalse);
    });

    test('is safe to initialize() twice', () async {
      await service.initialize();
      await service.initialize();
      expect(service.isFirebaseAvailable, isFalse);
    });

    test('currentUser is null', () {
      expect(service.currentUser, isNull);
    });

    test('authStateChanges is a single null event', () async {
      final events = await service.authStateChanges.toList();
      expect(events, [null]);
    });

    test('signInWithGoogle throws a plain Exception', () async {
      await expectLater(
        service.signInWithGoogle(),
        throwsA(isA<Exception>()),
      );
      // The failure must not falsely flip availability to true.
      expect(service.isFirebaseAvailable, isFalse);
    });

    test('signInWithEmail throws a plain Exception', () async {
      await expectLater(
        service.signInWithEmail('a@b.com', 'secret'),
        throwsA(isA<Exception>()),
      );
    });

    test('signUpWithEmail throws a plain Exception', () async {
      await expectLater(
        service.signUpWithEmail('a@b.com', 'secret'),
        throwsA(isA<Exception>()),
      );
    });

    test('sendPasswordResetEmail throws a plain Exception', () async {
      await expectLater(
        service.sendPasswordResetEmail('a@b.com'),
        throwsA(isA<Exception>()),
      );
    });

    test('signOut completes without reaching Firebase', () async {
      // With no Firebase session this must be a best-effort no-op, never a throw.
      await service.signOut();
      expect(service.isFirebaseAvailable, isFalse);
    });
  });
}
