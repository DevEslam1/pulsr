// test/features/auth/auth_cubit_test.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/auth_service.dart';
import 'package:pulsr/core/services/cloud_sync_service.dart';
import 'package:pulsr/features/auth/cubit/auth_cubit.dart';
import 'package:pulsr/features/auth/cubit/auth_state.dart';

class MockAuthService extends Mock implements AuthService {}

class MockCloudSyncService extends Mock implements CloudSyncService {}

class MockUser extends Mock implements User {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthService auth;
  late MockCloudSyncService cloud;
  late MockUser user;
  final syncedAt = DateTime.utc(2026, 1, 1, 12);

  setUpAll(() {
    registerFallbackValue(<String, String>{});
  });

  setUp(() {
    auth = MockAuthService();
    cloud = MockCloudSyncService();
    user = MockUser();
    when(() => cloud.lastSyncTime).thenReturn(syncedAt);
    when(() => cloud.syncAll()).thenAnswer((_) async => true);
    when(() => auth.authStateChanges).thenAnswer((_) => const Stream.empty());
  });

  AuthCubit build() => AuthCubit(auth, cloud);

  /// Lets the cubit's unawaited `syncNow()` settle.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('constructor / authStateChanges', () {
    test('seeds state with the last sync timestamp', () {
      final cubit = build();
      expect(cubit.state.status, AuthStatus.initial);
      expect(cubit.state.lastSyncedAt, syncedAt);
      cubit.close();
    });

    test('a signed-in update marks authenticated and triggers a sync',
        () async {
      final controller = StreamController<User?>.broadcast();
      when(() => auth.authStateChanges).thenAnswer((_) => controller.stream);

      final cubit = build();
      controller.add(user);
      await settle();

      expect(cubit.state.status, AuthStatus.authenticated);
      expect(cubit.state.user, same(user));
      verify(() => cloud.syncAll()).called(1);

      await cubit.close();
      await controller.close();
    });

    test('a signed-out update marks unauthenticated and clears the user',
        () async {
      final controller = StreamController<User?>.broadcast();
      when(() => auth.authStateChanges).thenAnswer((_) => controller.stream);

      final cubit = build();
      controller.add(user);
      await settle();
      controller.add(null);
      await settle();

      expect(cubit.state.status, AuthStatus.unauthenticated);
      expect(cubit.state.user, isNull);
      expect(cubit.state.errorMessage, isNull);

      await cubit.close();
      await controller.close();
    });
  });

  group('signInWithGoogle', () {
    test('success emits authenticated and syncs', () async {
      when(() => auth.signInWithGoogle()).thenAnswer((_) async => user);

      final cubit = build();
      await cubit.signInWithGoogle();

      expect(cubit.state.status, AuthStatus.authenticated);
      expect(cubit.state.user, same(user));
      expect(cubit.state.syncStatus, SyncStatus.success);
      verify(() => cloud.syncAll()).called(1);
      await cubit.close();
    });

    test('a null result emits unauthenticated', () async {
      when(() => auth.signInWithGoogle()).thenAnswer((_) async => null);

      final cubit = build();
      await cubit.signInWithGoogle();

      expect(cubit.state.status, AuthStatus.unauthenticated);
      expect(cubit.state.user, isNull);
      verifyNever(() => cloud.syncAll());
      await cubit.close();
    });

    test('a thrown error maps to an error state', () async {
      when(() => auth.signInWithGoogle()).thenThrow(
            FirebaseAuthException(code: 'user-not-found', message: 'nope'),
          );

      final cubit = build();
      await cubit.signInWithGoogle();

      expect(cubit.state.status, AuthStatus.error);
      expect(cubit.state.errorMessage, 'No account found with this email.');
      await cubit.close();
    });
  });

  group('signInWithEmail', () {
    test('success emits authenticated and syncs', () async {
      when(() => auth.signInWithEmail(any(), any()))
          .thenAnswer((_) async => user);

      final cubit = build();
      await cubit.signInWithEmail('a@b.com', 'secret');

      expect(cubit.state.status, AuthStatus.authenticated);
      expect(cubit.state.user, same(user));
      verify(() => auth.signInWithEmail('a@b.com', 'secret')).called(1);
      await cubit.close();
    });

    test('a null result emits unauthenticated with a retry message', () async {
      when(() => auth.signInWithEmail(any(), any()))
          .thenAnswer((_) async => null);

      final cubit = build();
      await cubit.signInWithEmail('a@b.com', 'secret');

      expect(cubit.state.status, AuthStatus.unauthenticated);
      expect(cubit.state.errorMessage, 'Sign in failed. Please try again.');
      await cubit.close();
    });

    test('a thrown error maps to an error state', () async {
      when(() => auth.signInWithEmail(any(), any())).thenThrow(
            FirebaseAuthException(code: 'wrong-password', message: 'bad'),
          );

      final cubit = build();
      await cubit.signInWithEmail('a@b.com', 'secret');

      expect(cubit.state.status, AuthStatus.error);
      expect(cubit.state.errorMessage, 'Incorrect email or password.');
      await cubit.close();
    });
  });

  group('signUpWithEmail', () {
    test('success emits authenticated and syncs', () async {
      when(() => auth.signUpWithEmail(any(), any()))
          .thenAnswer((_) async => user);

      final cubit = build();
      await cubit.signUpWithEmail('a@b.com', 'secret');

      expect(cubit.state.status, AuthStatus.authenticated);
      expect(cubit.state.user, same(user));
      await cubit.close();
    });

    test('a null result emits unauthenticated with a retry message', () async {
      when(() => auth.signUpWithEmail(any(), any()))
          .thenAnswer((_) async => null);

      final cubit = build();
      await cubit.signUpWithEmail('a@b.com', 'secret');

      expect(cubit.state.status, AuthStatus.unauthenticated);
      expect(cubit.state.errorMessage, 'Sign up failed. Please try again.');
      await cubit.close();
    });

    test('a thrown error maps to an error state', () async {
      when(() => auth.signUpWithEmail(any(), any())).thenThrow(
            FirebaseAuthException(
                code: 'email-already-in-use', message: 'taken'),
          );

      final cubit = build();
      await cubit.signUpWithEmail('a@b.com', 'secret');

      expect(cubit.state.status, AuthStatus.error);
      expect(cubit.state.errorMessage, 'This email is already registered.');
      await cubit.close();
    });
  });

  group('sendPasswordReset', () {
    test('returns true and clears the error on success', () async {
      when(() => auth.sendPasswordResetEmail(any())).thenAnswer((_) async {});

      final cubit = build();
      final ok = await cubit.sendPasswordReset('a@b.com');

      expect(ok, isTrue);
      expect(cubit.state.errorMessage, isNull);
      verify(() => auth.sendPasswordResetEmail('a@b.com')).called(1);
      await cubit.close();
    });

    test('returns false and surfaces the mapped error on failure', () async {
      when(() => auth.sendPasswordResetEmail(any())).thenThrow(
            FirebaseAuthException(code: 'too-many-requests', message: 'x'),
          );

      final cubit = build();
      final ok = await cubit.sendPasswordReset('a@b.com');

      expect(ok, isFalse);
      expect(cubit.state.errorMessage, contains('Too many attempts'));
      await cubit.close();
    });
  });

  group('syncNow', () {
    test('is a no-op when there is no signed-in user', () async {
      final cubit = build();
      await cubit.syncNow();
      verifyNever(() => cloud.syncAll());
      expect(cubit.state.syncStatus, SyncStatus.idle);
      await cubit.close();
    });

    test('deduplicates a second call inside the sync window', () async {
      when(() => auth.signInWithGoogle()).thenAnswer((_) async => user);

      final cubit = build();
      await cubit.signInWithGoogle();
      await cubit.syncNow(); // inside the 2s Stopwatch window

      verify(() => cloud.syncAll()).called(1);
      await cubit.close();
    });

    test('reports failure when syncAll returns false', () async {
      when(() => auth.signInWithGoogle()).thenAnswer((_) async => user);
      when(() => cloud.syncAll()).thenAnswer((_) async => false);

      final cubit = build();
      await cubit.signInWithGoogle();

      expect(cubit.state.syncStatus, SyncStatus.failure);
      expect(cubit.state.syncError, contains('Failed to sync'));
      await cubit.close();
    });

    test('reports failure when syncAll throws', () async {
      when(() => auth.signInWithGoogle()).thenAnswer((_) async => user);
      when(() => cloud.syncAll()).thenThrow(Exception('network down'));

      final cubit = build();
      await cubit.signInWithGoogle();

      expect(cubit.state.syncStatus, SyncStatus.failure);
      expect(cubit.state.syncError, contains('Failed to sync'));
      await cubit.close();
    });
  });

  group('signOut', () {
    test('delegates to AuthService and emits unauthenticated', () async {
      when(() => auth.signOut()).thenAnswer((_) async {});

      final cubit = build();
      await cubit.signOut();

      expect(cubit.state.status, AuthStatus.unauthenticated);
      expect(cubit.state.user, isNull);
      verify(() => auth.signOut()).called(1);
      await cubit.close();
    });
  });

  group('mapAuthError remaining branches', () {
    test('falls back for unknown Firebase auth codes with an empty message',
        () {
      expect(
        AuthCubit.mapAuthError(
            FirebaseAuthException(code: 'unknown', message: '   ')),
        'Sign-in failed. Please try again.',
      );
    });

    test('maps disabled and not-allowed Firebase codes', () {
      expect(
        AuthCubit.mapAuthError(
            FirebaseAuthException(code: 'user-disabled', message: 'x')),
        'This account has been disabled.',
      );
      expect(
        AuthCubit.mapAuthError(
            FirebaseAuthException(code: 'operation-not-allowed', message: 'x')),
        'Email sign-in is not enabled for this app.',
      );
    });

    test('maps PlatformException fallbacks', () {
      expect(
        AuthCubit.mapAuthError(PlatformException(code: 'other', message: 'oops')),
        'oops',
      );
      expect(
        AuthCubit.mapAuthError(PlatformException(code: 'other')),
        'Sign-in failed. Please try again.',
      );
      expect(
        AuthCubit.mapAuthError(
            PlatformException(code: 'sign_in_cancelled')),
        'Sign-in was cancelled.',
      );
    });

    test('maps untyped string fallbacks', () {
      expect(
        AuthCubit.mapAuthError(Exception('email already in use')),
        'This email is already registered.',
      );
      expect(
        AuthCubit.mapAuthError(Exception('weak password supplied')),
        'Password must be at least 6 characters.',
      );
      expect(
        AuthCubit.mapAuthError(Exception('ApiException: 10 DEVELOPER_ERROR')),
        contains('SHA-1 fingerprint'),
      );
    });
  });
}
