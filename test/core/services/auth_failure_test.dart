// test/core/services/auth_failure_test.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pulsr/core/services/auth_failure.dart';

void main() {
  group('AuthFailure.fromFirebase', () {
    test('maps every actionable Firebase code to a kind and a remedy', () {
      final cases = <String, (AuthFailureKind, AuthRecoveryAction)>{
        'user-not-found': (
          AuthFailureKind.accountNotFound,
          AuthRecoveryAction.editCredentials,
        ),
        'wrong-password': (
          AuthFailureKind.invalidCredentials,
          AuthRecoveryAction.editCredentials,
        ),
        'invalid-credential': (
          AuthFailureKind.invalidCredentials,
          AuthRecoveryAction.editCredentials,
        ),
        'email-already-in-use': (
          AuthFailureKind.emailInUse,
          AuthRecoveryAction.useEmailSignIn,
        ),
        'weak-password': (
          AuthFailureKind.weakPassword,
          AuthRecoveryAction.editCredentials,
        ),
        'network-request-failed': (
          AuthFailureKind.network,
          AuthRecoveryAction.retry,
        ),
        'too-many-requests': (
          AuthFailureKind.rateLimited,
          AuthRecoveryAction.retry,
        ),
        'user-disabled': (
          AuthFailureKind.accountDisabled,
          AuthRecoveryAction.none,
        ),
        'operation-not-allowed': (
          AuthFailureKind.notConfigured,
          AuthRecoveryAction.continueOffline,
        ),
      };

      cases.forEach((code, expected) {
        final failure =
            AuthFailure.fromFirebase(FirebaseAuthException(code: code));
        expect(failure.kind, expected.$1, reason: code);
        expect(failure.recovery, expected.$2, reason: code);
      });
    });

    test('keeps an unrecognised Firebase message but still types the failure',
        () {
      final failure = AuthFailure.fromFirebase(
        FirebaseAuthException(code: 'something-new', message: 'custom text'),
      );

      expect(failure.kind, AuthFailureKind.unknown);
      expect(failure.userMessage, 'custom text');
      expect(failure.code, 'AUTH_FIREBASE_SOMETHING-NEW');
    });
  });

  group('AuthFailure.fromAny', () {
    test('returns an existing typed failure unchanged', () {
      const original = AuthFailure(
        code: 'AUTH_TEST',
        userMessage: 'x',
        kind: AuthFailureKind.timeout,
        recovery: AuthRecoveryAction.retry,
      );

      expect(identical(AuthFailure.fromAny(original), original), isTrue);
    });

    test('maps a TimeoutException to a retryable timeout', () {
      final failure = AuthFailure.fromAny(TimeoutException('slow'));

      expect(failure.kind, AuthFailureKind.timeout);
      expect(failure.recovery, AuthRecoveryAction.retry);
    });

    test('maps a Google cancellation without offering a meaningless retry', () {
      final failure = AuthFailure.fromGoogle(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        ),
      );

      expect(failure.kind, AuthFailureKind.cancelled);
      expect(failure.recovery, AuthRecoveryAction.none);
    });

    test('maps a platform sign-in failure to a retryable Google failure', () {
      final failure = AuthFailure.fromPlatform(
        PlatformException(code: 'sign_in_failed'),
      );

      expect(failure.kind, AuthFailureKind.googleUnavailable);
      expect(failure.recovery, AuthRecoveryAction.retry);
    });

    test('keeps the legacy string fallbacks for untyped errors', () {
      expect(
        AuthFailure.fromAny(Exception('ERROR: user not found in backend')).kind,
        AuthFailureKind.accountNotFound,
      );
      expect(
        AuthFailure.fromAny(Exception('SocketException: failed host lookup'))
            .kind,
        AuthFailureKind.network,
      );
      expect(
        AuthFailure.fromAny(Exception('totally unknown failure')).kind,
        AuthFailureKind.unknown,
      );
    });
  });

  test('unavailable sign-in offers continue-offline rather than a retry loop',
      () {
    final failure = AuthFailure.unavailable(StateError('no firebase'));

    expect(failure.kind, AuthFailureKind.notConfigured);
    expect(failure.recovery, AuthRecoveryAction.continueOffline);
    expect(failure.userMessage, contains('offline'));
  });
}
