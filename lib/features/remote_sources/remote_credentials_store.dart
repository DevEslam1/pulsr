// lib/features/remote_sources/remote_credentials_store.dart
//
// P0-1 "remote sources": password storage for network libraries.
//
// Secrets go to flutter_secure_storage (Android Keystore / iOS Keychain) under
// one slot per source id. They are never written to SharedPreferences, never
// logged and never included in RemoteSource.toJson(), so a prefs backup or a
// crash report cannot leak them.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/utils/error_logger.dart';

/// Minimal key/value secret storage.
///
/// Abstracted so [RemoteCredentialsStore] can be unit-tested without the
/// platform keystore (a fake map implementation is enough).
abstract class RemoteCredentialStorage {
  /// Reads the raw value stored under [key], or `null` when absent.
  Future<String?> read(String key);

  /// Writes [value] under [key], replacing any previous value.
  Future<void> write(String key, String value);

  /// Removes [key] if present.
  Future<void> delete(String key);
}

/// [RemoteCredentialStorage] backed by the platform keystore.
class SecureStorageCredentialStorage implements RemoteCredentialStorage {
  /// Creates the production storage.
  ///
  /// `resetOnError` keeps a corrupted Android Keystore entry from wedging the
  /// whole settings screen: the slot is dropped and the user is asked to sign
  /// in again instead of every read throwing forever.
  SecureStorageCredentialStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Login name and password for one remote source.
///
/// The username is also persisted (harmlessly) in the source record; it is
/// repeated here so the pair can be written and cleared atomically.
@immutable
class RemoteCredentials {
  /// Creates a credential pair.
  const RemoteCredentials({required this.username, required this.password});

  /// Restores credentials from the JSON blob written by [toJson].
  factory RemoteCredentials.fromJson(Map<String, dynamic> json) {
    return RemoteCredentials(
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
    );
  }

  /// Login name; empty string for anonymous access.
  final String username;

  /// Password or access token; may be empty.
  final String password;

  /// Whether this pair carries no secret at all (anonymous access).
  bool get isEmpty => username.isEmpty && password.isEmpty;

  /// Serializes the pair for the keystore blob.
  Map<String, dynamic> toJson() => {'username': username, 'password': password};

  /// Redacted representation: safe to print in a debugger.
  @override
  String toString() => 'RemoteCredentials(username: $username, password: ***)';
}

/// Persists one [RemoteCredentials] per source id in secure storage.
class RemoteCredentialsStore {
  /// Creates the store, optionally over a custom [storage] (tests).
  RemoteCredentialsStore([RemoteCredentialStorage? storage])
      : _storage = storage ?? SecureStorageCredentialStorage();

  /// Prefix of every secure-storage slot owned by this module.
  static const String keyPrefix = 'remote_source_cred_v1_';

  final RemoteCredentialStorage _storage;

  /// Secure-storage key for [sourceId].
  static String keyFor(String sourceId) => '$keyPrefix$sourceId';

  /// Writes [credentials] for [sourceId], replacing any previous secret.
  ///
  /// A keystore failure is logged and rethrown as a [StateError] so the caller
  /// can show "could not save the password" without importing plugin
  /// exception types.
  Future<void> save(String sourceId, RemoteCredentials credentials) async {
    try {
      await _storage.write(keyFor(sourceId), jsonEncode(credentials.toJson()));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to persist remote credentials',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'sourceId': sourceId},
      );
      throw StateError('Could not save the password for this source.');
    }
  }

  /// Writes [incoming] for [sourceId], keeping the stored password when the
  /// caller left it blank, and never deleting an existing secret.
  ///
  /// This is the save path used by the editor. "Blank password" means "keep
  /// the saved one" there, and replacing a source by id (an added endpoint that
  /// normalizes to an existing id) must not silently wipe the secret that
  /// belongs to it. Deletion is explicit: [delete], used when the source itself
  /// is removed.
  Future<RemoteCredentials> mergeAndSave(
    String sourceId,
    RemoteCredentials incoming, {
    bool clearPassword = false,
  }) async {
    final existing = await read(sourceId);
    final password = clearPassword
        ? incoming.password
        : (incoming.password.isNotEmpty
            ? incoming.password
            : (existing?.password ?? ''));
    final merged = RemoteCredentials(
      username: clearPassword
          ? incoming.username
          : (incoming.username.isNotEmpty
              ? incoming.username
              : (existing?.username ?? '')),
      password: password,
    );
    if (clearPassword && merged.isEmpty) {
      await delete(sourceId);
      return merged;
    }
    if (merged.isEmpty) return merged;
    await save(sourceId, merged);
    return merged;
  }

  /// Reads the credentials for [sourceId], or `null` when none are stored.
  Future<RemoteCredentials?> read(String sourceId) async {
    try {
      final raw = await _storage.read(keyFor(sourceId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        ErrorLogger.log(
          'Discarding unreadable remote credentials blob',
          category: 'RemoteSources',
          meta: {'sourceId': sourceId},
        );
        return null;
      }
      return RemoteCredentials.fromJson(decoded);
    } catch (e, st) {
      // A malformed blob or a keystore read failure must not block browsing
      // with anonymous access, so the caller falls back to "no credentials".
      ErrorLogger.log(
        'Failed to read remote credentials',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'sourceId': sourceId},
      );
      return null;
    }
  }

  /// Deletes the secret belonging to [sourceId], if any.
  Future<void> delete(String sourceId) async {
    try {
      await _storage.delete(keyFor(sourceId));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to delete remote credentials',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'sourceId': sourceId},
      );
    }
  }
}
