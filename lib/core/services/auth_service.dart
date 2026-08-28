// lib/core/services/auth_service.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:injectable/injectable.dart';
import '../utils/error_logger.dart';

@singleton
class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
  );

  bool _isFirebaseAvailable = false;
  bool get isFirebaseAvailable => _isFirebaseAvailable;

  User? get currentUser =>
      _isFirebaseAvailable ? FirebaseAuth.instance.currentUser : null;
  Stream<User?> get authStateChanges => _isFirebaseAvailable
      ? FirebaseAuth.instance.authStateChanges()
      : Stream<User?>.value(null);

  Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _isFirebaseAvailable = true;
    } catch (e, st) {
      _isFirebaseAvailable = false;
      ErrorLogger.log('Firebase init skipped or unavailable',
          error: e, stackTrace: st, category: 'AuthService');
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      if (!_isFirebaseAvailable) await initialize();
      if (!_isFirebaseAvailable) {
        throw Exception('Firebase is not available on this device');
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the sign-in dialog
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      return userCredential.user;
    } catch (e, st) {
      ErrorLogger.log('Google Sign-In failed',
          error: e, stackTrace: st, category: 'AuthService');
      rethrow;
    }
  }

  Future<User?> signInWithEmail(String email, String password) async {
    try {
      if (!_isFirebaseAvailable) await initialize();
      if (!_isFirebaseAvailable) {
        throw Exception('Firebase is not available on this device');
      }

      final UserCredential cred =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return cred.user;
    } catch (e, st) {
      ErrorLogger.log('Email Sign-In failed',
          error: e, stackTrace: st, category: 'AuthService');
      rethrow;
    }
  }

  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      if (!_isFirebaseAvailable) await initialize();
      if (!_isFirebaseAvailable) {
        throw Exception('Firebase is not available on this device');
      }

      final UserCredential cred =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return cred.user;
    } catch (e, st) {
      ErrorLogger.log('Email Sign-Up failed',
          error: e, stackTrace: st, category: 'AuthService');
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      if (!_isFirebaseAvailable) await initialize();
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
    } catch (e, st) {
      ErrorLogger.log('Password reset failed',
          error: e, stackTrace: st, category: 'AuthService');
      rethrow;
    }
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
