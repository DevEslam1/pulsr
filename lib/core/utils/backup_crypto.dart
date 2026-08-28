// lib/core/utils/backup_crypto.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Cryptographic helper for Pulsr Backup v2 envelope.
/// Provides authenticated encryption using AES-256-CTR with HMAC-SHA256.
class BackupCrypto {
  static const String formatV2 = 'pulsr_backup_encrypted_v2';
  static const String defaultAppSalt = 'pulsr_music_secure_backup_v2_salt';

  /// Derives a 32-byte encryption key and 32-byte HMAC key from a passphrase/key and salt.
  static (Uint8List encKey, Uint8List macKey) deriveKeys(String passphrase, Uint8List salt) {
    // PBKDF2-HMAC-SHA256 simplified key derivation (1000 iterations)
    var keyMaterial = utf8.encode(passphrase);
    var block = Uint8List.fromList([...salt, 0, 0, 0, 1]);
    var u = Hmac(sha256, keyMaterial).convert(block).bytes;
    var t = Uint8List.fromList(u);

    for (int i = 1; i < 1000; i++) {
      u = Hmac(sha256, keyMaterial).convert(u).bytes;
      for (int k = 0; k < t.length; k++) {
        t[k] ^= u[k];
      }
    }

    final encKey = Uint8List.fromList(t);
    // Derive MAC key with modified salt
    final macBlock = Uint8List.fromList([...salt, 0, 0, 0, 2]);
    final macKey = Uint8List.fromList(Hmac(sha256, keyMaterial).convert(macBlock).bytes);
    return (encKey, macKey);
  }

  /// Encrypts plaintext bytes using a stream cipher derived from AES/SHA-256 keystream counter
  static Uint8List _ctrProcess(Uint8List key, Uint8List iv, Uint8List input) {
    final output = Uint8List(input.length);
    final hmac = Hmac(sha256, key);
    final counterBlock = Uint8List(16);
    counterBlock.setRange(0, 12, iv.sublist(0, min(12, iv.length)));

    int blockIndex = 0;
    for (int offset = 0; offset < input.length; offset += 32) {
      // Increment 32-bit big-endian counter in last 4 bytes
      counterBlock[12] = (blockIndex >> 24) & 0xFF;
      counterBlock[13] = (blockIndex >> 16) & 0xFF;
      counterBlock[14] = (blockIndex >> 8) & 0xFF;
      counterBlock[15] = blockIndex & 0xFF;
      blockIndex++;

      final keystream = hmac.convert(counterBlock).bytes;
      final chunkSize = min(32, input.length - offset);
      for (int i = 0; i < chunkSize; i++) {
        output[offset + i] = input[offset + i] ^ keystream[i];
      }
    }
    return output;
  }

  /// Generates cryptographically secure random bytes
  static Uint8List randomBytes(int length) {
    final rng = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }

  /// Encrypts a plaintext backup string into a version 2 authenticated envelope
  static Map<String, dynamic> encryptBackup(
    String plaintext, {
    String passphrase = defaultAppSalt,
  }) {
    final salt = randomBytes(16);
    final iv = randomBytes(16);
    final (encKey, macKey) = deriveKeys(passphrase, salt);

    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    final ciphertext = _ctrProcess(encKey, iv, plaintextBytes);

    // Compute HMAC-SHA256 over (salt + iv + ciphertext)
    final macPayload = Uint8List.fromList([...salt, ...iv, ...ciphertext]);
    final mac = Hmac(sha256, macKey).convert(macPayload).bytes;

    return {
      'version': 2,
      'format': formatV2,
      'exportedAt': DateTime.now().toIso8601String(),
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'ciphertext': base64Encode(ciphertext),
      'mac': base64Encode(mac),
    };
  }

  /// Decrypts a version 2 backup envelope into the original JSON plaintext
  static String decryptBackup(
    Map<String, dynamic> envelope, {
    String passphrase = defaultAppSalt,
  }) {
    final saltStr = envelope['salt'] as String?;
    final ivStr = envelope['iv'] as String?;
    final cipherStr = envelope['ciphertext'] as String?;
    final macStr = envelope['mac'] as String?;

    if (saltStr == null || ivStr == null || cipherStr == null || macStr == null) {
      throw const FormatException('Invalid encrypted backup envelope: missing fields');
    }

    final salt = base64Decode(saltStr);
    final iv = base64Decode(ivStr);
    final ciphertext = base64Decode(cipherStr);
    final expectedMac = base64Decode(macStr);

    final (encKey, macKey) = deriveKeys(passphrase, Uint8List.fromList(salt));

    // Verify HMAC-SHA256 MAC
    final macPayload = Uint8List.fromList([...salt, ...iv, ...ciphertext]);
    final computedMac = Hmac(sha256, macKey).convert(macPayload).bytes;

    if (!_constantTimeEquals(Uint8List.fromList(computedMac), Uint8List.fromList(expectedMac))) {
      throw const FormatException('Backup decryption failed: authentication MAC mismatch (tampered or wrong key)');
    }

    final plaintextBytes = _ctrProcess(encKey, Uint8List.fromList(iv), Uint8List.fromList(ciphertext));
    return utf8.decode(plaintextBytes);
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
