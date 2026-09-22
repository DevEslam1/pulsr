// test/errors/app_error_taxonomy_test.dart
// FIX-D1: Unit tests verifying AppError taxonomy and resolution
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/app_error.dart';

void main() {
  group('Phase D: AppError Taxonomy & Classifier Tests', () {
    test('SocketException resolves to NetworkError', () {
      final socketEx = const SocketException('Connection refused');
      final error = resolveAppError(socketEx);

      expect(error, isA<NetworkError>());
      final netError = error as NetworkError;
      expect(netError.code, equals('NET_SOCKET_ERROR'));
      expect(netError.cause, equals(socketEx));
      expect(netError.userMessage, contains('connection failed'));
    });

    test('PlatformException with permission denial resolves to PermissionError', () {
      final permEx = PlatformException(
        code: 'permission_DENIED_storage',
        message: 'Storage permission permanently denied',
      );
      final error = resolveAppError(permEx);

      expect(error, isA<PermissionError>());
      final permError = error as PermissionError;
      expect(permError.code, equals('PERM_DENIED'));
      expect(permError.permissionName, equals('permission_DENIED_storage'));
      expect(permError.userMessage, contains('Storage permission'));
    });

    test('FileSystemException resolves to StorageError and preserves path', () {
      final fsEx = const FileSystemException('Failed to write file', '/sdcard/music/test.flac');
      final error = resolveAppError(fsEx);

      expect(error, isA<StorageError>());
      final storageError = error as StorageError;
      expect(storageError.code, equals('FS_IO_ERROR'));
      expect(storageError.path, equals('/sdcard/music/test.flac'));
    });

    test('Bot-block message resolves to YtmError with isBotBlock = true', () {
      final ex = Exception('Sign in to confirm you’re not a bot to continue');
      final error = resolveAppError(ex);

      expect(error, isA<YtmError>());
      final ytmError = error as YtmError;
      expect(ytmError.code, equals('YTM_BOT_BLOCK'));
      expect(ytmError.isBotBlock, isTrue);
      expect(ytmError.userMessage, contains('bot check triggered'));
    });

    test('Timeout exception resolves to NetworkError with isTimeout = true', () {
      final ex = Exception('HTTP request timeout on endpoint');
      final error = resolveAppError(ex);

      expect(error, isA<NetworkError>());
      final netError = error as NetworkError;
      expect(netError.code, equals('NET_TIMEOUT'));
      expect(netError.isTimeout, isTrue);
      expect(netError.userMessage, contains('timed out'));
    });

    test('Unrecognized exception resolves to GenericAppError with intact message', () {
      final ex = Exception('Arbitrary unknown domain failure');
      final error = resolveAppError(ex);

      expect(error, isA<GenericAppError>());
      expect(error.code, equals('GENERIC_ERROR'));
      expect(error.userMessage, contains('Arbitrary unknown domain failure'));
    });

    test('Existing AppError passes through resolveAppError unmodified', () {
      const existing = AudioError(
        code: 'AUDIO_DECODE_ERR',
        userMessage: 'Corrupt FLAC header',
        trackId: 42,
      );
      final resolved = resolveAppError(existing);

      expect(identical(resolved, existing), isTrue);
      expect(resolved.code, equals('AUDIO_DECODE_ERR'));
    });
  });
}
