// test/features/auth/auth_cubit_error_mapping_test.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/auth/cubit/auth_cubit.dart';

void main() {
  group('AuthCubit.mapAuthError', () {
    test('maps typed FirebaseAuthException codes exhaustively', () {
      expect(
        AuthCubit.mapAuthError(
            FirebaseAuthException(code: 'user-not-found', message: 'x')),
        'No account found with this email.',
      );
      expect(
        AuthCubit.mapAuthError(
            FirebaseAuthException(code: 'wrong-password', message: 'x')),
        'Incorrect email or password.',
      );
      expect(
        AuthCubit.mapAuthError(
            FirebaseAuthException(code: 'email-already-in-use', message: 'x')),
        'This email is already registered.',
      );
      expect(
        AuthCubit.mapAuthError(
            FirebaseAuthException(code: 'weak-password', message: 'x')),
        'Password must be at least 6 characters.',
      );
      expect(
        AuthCubit.mapAuthError(FirebaseAuthException(
            code: 'network-request-failed', message: 'x')),
        contains('Network error'),
      );
      expect(
        AuthCubit.mapAuthError(
            FirebaseAuthException(code: 'too-many-requests', message: 'x')),
        contains('Too many attempts'),
      );
    });

    test('falls back to Firebase message when code is unrecognized', () {
      expect(
        AuthCubit.mapAuthError(
            FirebaseAuthException(code: 'something-new', message: 'custom')),
        'custom',
      );
    });

    test('maps Google Sign-In PlatformException codes', () {
      expect(
        AuthCubit.mapAuthError(PlatformException(code: 'sign_in_canceled')),
        'Sign-in was cancelled.',
      );
      expect(
        AuthCubit.mapAuthError(PlatformException(code: 'sign_in_failed')),
        contains('Google Sign-In failed'),
      );
      expect(
        AuthCubit.mapAuthError(PlatformException(code: '10')),
        contains('SHA-1 fingerprint'),
      );
    });

    test('falls back to string parsing for untyped errors', () {
      expect(
        AuthCubit.mapAuthError(Exception('ERROR: user not found in backend')),
        'No account found with this email.',
      );
      expect(
        AuthCubit.mapAuthError(
            Exception('SocketException: failed host lookup')),
        contains('Network error'),
      );
      expect(
        AuthCubit.mapAuthError(Exception('totally unknown failure')),
        'Sign-in failed. Please try again.',
      );
    });
  });
}
