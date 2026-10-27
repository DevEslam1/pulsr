// lib/core/services/auth_service.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:injectable/injectable.dart';
import '../config/app_config.dart';
import '../utils/error_logger.dart';
import 'auth_failure.dart';

@lazySingleton
class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleSignInInitialized = false;

  /// A sign-in that never resolves leaves the auth sheet spinning forever.
  /// Thirty seconds is long enough for a slow mobile network and short enough
  /// that the user gets a retry affordance in the same interaction.
  static const Duration _operationTimeout = Duration(seconds: 30);

  bool _isFirebaseAvailable = false;
  bool get isFirebaseAvailable => _isFirebaseAvailable;

  User? get currentUser =>
      _isFirebaseAvailable ? FirebaseAuth.instance.currentUser : null;
  Stream<User?> get authStateChanges => _isFirebaseAvailable
      ? FirebaseAuth.instance.authStateChanges()
      : Stream<User?>.value(null);

  Future<void>? _initFuture;

  Future<void> initialize() async {
    if (!AppConfig.isCloudSyncAllowed) return;
    final inFlight = _initFuture;
    if (inFlight != null) return inFlight;

    final future = _performInitialize();
    _initFuture = future;
    try {
      await future;
    } finally {
      if (_initFuture == future) {
        _initFuture = null;
      }
    }
  }

  Future<void> _performInitialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp().timeout(_operationTimeout);
      }
      _isFirebaseAvailable = true;
    } catch (e, st) {
      _isFirebaseAvailable = false;
      ErrorLogger.log('Firebase init skipped or unavailable',
          error: e, stackTrace: st, category: 'AuthService');
    }

    if (!_googleSignInInitialized) {
      try {
        await _googleSignIn.initialize().timeout(_operationTimeout);
        _googleSignInInitialized = true;
      } catch (e, st) {
        ErrorLogger.log('GoogleSignIn init failed',
            error: e, stackTrace: st, category: 'AuthService');
      }
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      if (!_isFirebaseAvailable) await initialize();
      if (!_isFirebaseAvailable) {
        throw AuthFailure.unavailable(
            StateError('Firebase is not available on this device'));
      }

      if (!_googleSignInInitialized) {
        await _googleSignIn.initialize().timeout(_operationTimeout);
        _googleSignInInitialized = true;
      }

      final GoogleSignInAccount googleUser;
      try {
        googleUser = await _googleSignIn
            .authenticate(scopeHint: ['email']).timeout(_operationTimeout);
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) {
          return null;
        }
        rethrow;
      }

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final authz = await googleUser.authorizationClient
          .authorizationForScopes(['email']).timeout(_operationTimeout);
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: authz?.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(_operationTimeout);
      return userCredential.user;
    } catch (e, st) {
      throw _fail('Google Sign-In failed', e, st);
    }
  }

  Future<User?> signInWithEmail(String email, String password) async {
    try {
      if (!_isFirebaseAvailable) await initialize();
      if (!_isFirebaseAvailable) {
        throw AuthFailure.unavailable(
            StateError('Firebase is not available on this device'));
      }

      final UserCredential cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          )
          .timeout(_operationTimeout);
      return cred.user;
    } catch (e, st) {
      throw _fail('Email Sign-In failed', e, st);
    }
  }

  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      if (!_isFirebaseAvailable) await initialize();
      if (!_isFirebaseAvailable) {
        throw AuthFailure.unavailable(
            StateError('Firebase is not available on this device'));
      }

      final UserCredential cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          )
          .timeout(_operationTimeout);
      return cred.user;
    } catch (e, st) {
      throw _fail('Email Sign-Up failed', e, st);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      if (!_isFirebaseAvailable) await initialize();
      if (!_isFirebaseAvailable) {
        throw AuthFailure.unavailable(
            StateError('Firebase is not available on this device'));
      }
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: email.trim())
          .timeout(_operationTimeout);
    } catch (e, st) {
      throw _fail('Password reset failed', e, st);
    }
  }

  /// Logs once and rethrows as a typed failure, preserving the original cause.
  AuthFailure _fail(String operation, Object error, StackTrace stackTrace) {
    ErrorLogger.log(operation,
        error: error, stackTrace: stackTrace, category: 'AuthService');
    return AuthFailure.fromAny(error, stackTrace);
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e, st) {
      ErrorLogger.log('Google sign-out failed',
          error: e, stackTrace: st, category: 'AuthService');
    }
    try {
      if (_isFirebaseAvailable) {
        await FirebaseAuth.instance.signOut();
      }
    } catch (e, st) {
      ErrorLogger.log('Firebase sign-out failed',
          error: e, stackTrace: st, category: 'AuthService');
    }
  }
}
