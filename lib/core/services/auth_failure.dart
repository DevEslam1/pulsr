// lib/core/services/auth_failure.dart
//
// Typed authentication failures.
//
// `AuthService` used to throw bare `Exception('Firebase is not available…')`
// and let `AuthCubit` re-parse `toString()` to decide what to show. That made
// every caller responsible for guessing which recoveries were possible. This
// type carries the verdict (what failed) and the remedy (what the user can do)
// as data, while still implementing [AppError] so the app-wide taxonomy and
// crash reporting see one error shape.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../errors/app_error_base.dart';

enum AuthFailureKind {
  cancelled,
  invalidCredentials,
  accountNotFound,
  emailInUse,
  weakPassword,
  network,
  rateLimited,
  accountDisabled,
  notConfigured,
  googleUnavailable,
  platform,
  timeout,
  unknown,
}

/// The one action worth offering next to a failure message. `null`-like
/// [none] means the error is informational (e.g. the user cancelled).
enum AuthRecoveryAction {
  retry,
  editCredentials,
  resetPassword,
  useEmailSignIn,
  continueOffline,
  none,
}

class AuthFailure extends AppError {
  final AuthFailureKind kind;
  final AuthRecoveryAction recovery;

  const AuthFailure({
    required super.code,
    required super.userMessage,
    required this.kind,
    required this.recovery,
    super.cause,
    super.stackTrace,
  });

  factory AuthFailure.fromAny(Object error, [StackTrace? stackTrace]) {
    if (error is AuthFailure) return error;
    if (error is FirebaseAuthException) {
      return AuthFailure.fromFirebase(error, stackTrace);
    }
    if (error is GoogleSignInException) {
      return AuthFailure.fromGoogle(error, stackTrace);
    }
    if (error is PlatformException) {
      return AuthFailure.fromPlatform(error, stackTrace);
    }
    if (error is TimeoutException) {
      return AuthFailure.timeout(error, stackTrace);
    }

    final text = error.toString().toLowerCase();
    if (text.contains('user-not-found') || text.contains('user not found')) {
      return AuthFailure(
        code: 'AUTH_USER_NOT_FOUND',
        userMessage: 'No account found with this email.',
        kind: AuthFailureKind.accountNotFound,
        recovery: AuthRecoveryAction.editCredentials,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (text.contains('wrong-password') ||
        text.contains('wrong password') ||
        text.contains('invalid-credential') ||
        text.contains('invalid-email')) {
      return AuthFailure(
        code: 'AUTH_INVALID_CREDENTIALS',
        userMessage: 'Incorrect email or password.',
        kind: AuthFailureKind.invalidCredentials,
        recovery: AuthRecoveryAction.editCredentials,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (text.contains('email-already-in-use') ||
        text.contains('email already in use')) {
      return AuthFailure(
        code: 'AUTH_EMAIL_IN_USE',
        userMessage: 'This email is already registered.',
        kind: AuthFailureKind.emailInUse,
        recovery: AuthRecoveryAction.useEmailSignIn,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (text.contains('weak-password') || text.contains('weak password')) {
      return AuthFailure(
        code: 'AUTH_WEAK_PASSWORD',
        userMessage: 'Password must be at least 6 characters.',
        kind: AuthFailureKind.weakPassword,
        recovery: AuthRecoveryAction.editCredentials,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (text.contains('network-request-failed') ||
        text.contains('network error') ||
        text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection')) {
      return AuthFailure(
        code: 'AUTH_NETWORK',
        userMessage: 'Network error. Check your internet connection.',
        kind: AuthFailureKind.network,
        recovery: AuthRecoveryAction.retry,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (text.contains('apiexception') && text.contains('10')) {
      return AuthFailure(
        code: 'AUTH_GOOGLE_CONFIG',
        userMessage:
            'Google Sign-In needs SHA-1 fingerprint registered in Firebase Console. You can sign in with Email below!',
        kind: AuthFailureKind.googleUnavailable,
        recovery: AuthRecoveryAction.useEmailSignIn,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return AuthFailure(
      code: 'AUTH_UNKNOWN',
      userMessage: 'Sign-in failed. Please try again.',
      kind: AuthFailureKind.unknown,
      recovery: AuthRecoveryAction.retry,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  factory AuthFailure.fromFirebase(FirebaseAuthException error,
      [StackTrace? stackTrace]) {
    switch (error.code) {
      case 'user-not-found':
        return AuthFailure(
          code: 'AUTH_USER_NOT_FOUND',
          userMessage: 'No account found with this email.',
          kind: AuthFailureKind.accountNotFound,
          recovery: AuthRecoveryAction.editCredentials,
          cause: error,
          stackTrace: stackTrace,
        );
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-email':
        return AuthFailure(
          code: 'AUTH_INVALID_CREDENTIALS',
          userMessage: 'Incorrect email or password.',
          kind: AuthFailureKind.invalidCredentials,
          recovery: AuthRecoveryAction.editCredentials,
          cause: error,
          stackTrace: stackTrace,
        );
      case 'email-already-in-use':
        return AuthFailure(
          code: 'AUTH_EMAIL_IN_USE',
          userMessage: 'This email is already registered.',
          kind: AuthFailureKind.emailInUse,
          recovery: AuthRecoveryAction.useEmailSignIn,
          cause: error,
          stackTrace: stackTrace,
        );
      case 'weak-password':
        return AuthFailure(
          code: 'AUTH_WEAK_PASSWORD',
          userMessage: 'Password must be at least 6 characters.',
          kind: AuthFailureKind.weakPassword,
          recovery: AuthRecoveryAction.editCredentials,
          cause: error,
          stackTrace: stackTrace,
        );
      case 'network-request-failed':
        return AuthFailure(
          code: 'AUTH_NETWORK',
          userMessage: 'Network error. Check your internet connection.',
          kind: AuthFailureKind.network,
          recovery: AuthRecoveryAction.retry,
          cause: error,
          stackTrace: stackTrace,
        );
      case 'too-many-requests':
        return AuthFailure(
          code: 'AUTH_RATE_LIMITED',
          userMessage: 'Too many attempts. Please try again later.',
          kind: AuthFailureKind.rateLimited,
          recovery: AuthRecoveryAction.retry,
          cause: error,
          stackTrace: stackTrace,
        );
      case 'user-disabled':
        return AuthFailure(
          code: 'AUTH_ACCOUNT_DISABLED',
          userMessage: 'This account has been disabled.',
          kind: AuthFailureKind.accountDisabled,
          recovery: AuthRecoveryAction.none,
          cause: error,
          stackTrace: stackTrace,
        );
      case 'operation-not-allowed':
        return AuthFailure(
          code: 'AUTH_NOT_CONFIGURED',
          userMessage: 'Email sign-in is not enabled for this app.',
          kind: AuthFailureKind.notConfigured,
          recovery: AuthRecoveryAction.continueOffline,
          cause: error,
          stackTrace: stackTrace,
        );
      default:
        final message = error.message?.trim();
        return AuthFailure(
          code: 'AUTH_FIREBASE_${error.code.toUpperCase()}',
          userMessage: message != null && message.isNotEmpty
              ? message
              : 'Sign-in failed. Please try again.',
          kind: AuthFailureKind.unknown,
          recovery: AuthRecoveryAction.retry,
          cause: error,
          stackTrace: stackTrace,
        );
    }
  }

  factory AuthFailure.fromGoogle(GoogleSignInException error,
      [StackTrace? stackTrace]) {
    if (error.code == GoogleSignInExceptionCode.canceled) {
      return AuthFailure(
        code: 'AUTH_CANCELLED',
        userMessage: 'Sign-in was cancelled.',
        kind: AuthFailureKind.cancelled,
        recovery: AuthRecoveryAction.none,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return AuthFailure(
      code: 'AUTH_GOOGLE_FAILED',
      userMessage:
          'Google Sign-In failed. Please check network and Google Play Services.',
      kind: AuthFailureKind.googleUnavailable,
      recovery: AuthRecoveryAction.retry,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  factory AuthFailure.fromPlatform(PlatformException error,
      [StackTrace? stackTrace]) {
    switch (error.code) {
      case 'sign_in_canceled':
      case 'sign_in_cancelled':
        return AuthFailure(
          code: 'AUTH_CANCELLED',
          userMessage: 'Sign-in was cancelled.',
          kind: AuthFailureKind.cancelled,
          recovery: AuthRecoveryAction.none,
          cause: error,
          stackTrace: stackTrace,
        );
      case 'sign_in_failed':
        return AuthFailure(
          code: 'AUTH_GOOGLE_FAILED',
          userMessage:
              'Google Sign-In failed. Please check network and Google Play Services.',
          kind: AuthFailureKind.googleUnavailable,
          recovery: AuthRecoveryAction.retry,
          cause: error,
          stackTrace: stackTrace,
        );
      case 'network_error':
        return AuthFailure(
          code: 'AUTH_NETWORK',
          userMessage: 'Network error. Check your internet connection.',
          kind: AuthFailureKind.network,
          recovery: AuthRecoveryAction.retry,
          cause: error,
          stackTrace: stackTrace,
        );
      case '10':
        return AuthFailure(
          code: 'AUTH_GOOGLE_CONFIG',
          userMessage:
              'Google Sign-In configuration mismatch (SHA-1 fingerprint required).',
          kind: AuthFailureKind.googleUnavailable,
          recovery: AuthRecoveryAction.useEmailSignIn,
          cause: error,
          stackTrace: stackTrace,
        );
      default:
        final message = error.message?.trim();
        return AuthFailure(
          code: 'AUTH_PLATFORM_${error.code}',
          userMessage: message != null && message.isNotEmpty
              ? message
              : 'Sign-in failed. Please try again.',
          kind: AuthFailureKind.platform,
          recovery: AuthRecoveryAction.retry,
          cause: error,
          stackTrace: stackTrace,
        );
    }
  }

  factory AuthFailure.timeout(Object error, [StackTrace? stackTrace]) =>
      AuthFailure(
        code: 'AUTH_TIMEOUT',
        userMessage: 'Sign-in timed out. Check your connection and try again.',
        kind: AuthFailureKind.timeout,
        recovery: AuthRecoveryAction.retry,
        cause: error,
        stackTrace: stackTrace,
      );

  factory AuthFailure.unavailable(Object error, [StackTrace? stackTrace]) =>
      AuthFailure(
        code: 'AUTH_UNAVAILABLE',
        userMessage:
            'Sign-in is not available on this device. You can keep listening offline.',
        kind: AuthFailureKind.notConfigured,
        recovery: AuthRecoveryAction.continueOffline,
        cause: error,
        stackTrace: stackTrace,
      );
}
