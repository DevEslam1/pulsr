import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/error_logger.dart';

void main() {
  group('P5-2: Sentry PII Scrubber Verification', () {
    test('redactPii scrubs email addresses', () {
      final input = 'Error connecting user test.user@example.com to server';
      final output = ErrorLogger.redactPii(input);
      expect(output, contains('[REDACTED_EMAIL]'));
      expect(output, isNot(contains('test.user@example.com')));
    });

    test('redactPii scrubs auth tokens, cookies, and bearer credentials', () {
      final input1 = 'Cookie: SAPISID=abcdef123456; HSID=789xyz; visitor_data=vis999;';
      final output1 = ErrorLogger.redactPii(input1);
      expect(output1, contains('SAPISID=[REDACTED_TOKEN]'));
      expect(output1, contains('HSID=[REDACTED_TOKEN]'));
      expect(output1, isNot(contains('abcdef123456')));

      final input2 = 'Request headers: Authorization: Bearer eyJhbGciOiJIUzI1Ni...';
      final output2 = ErrorLogger.redactPii(input2);
      expect(output2, contains('[REDACTED_TOKEN]'));
      expect(output2, isNot(contains('eyJhbGciOiJIUzI1Ni...')));
    });

    test('redactPii scrubs user and home directory paths (Windows, macOS, Linux)', () {
      final winPath = r'Failed to open C:\Users\Eslam\Music\track.flac';
      final winOutput = ErrorLogger.redactPii(winPath);
      expect(winOutput, contains('[REDACTED_USER_PATH]'));
      expect(winOutput, isNot(contains(r'C:\Users\Eslam')));

      final macPath = 'Failed to open /Users/eslam/Music/track.flac';
      final macOutput = ErrorLogger.redactPii(macPath);
      expect(macOutput, contains('[REDACTED_USER_PATH]'));
      expect(macOutput, isNot(contains('/Users/eslam')));

      final linuxPath = 'Failed to open /home/eslam/Music/track.flac';
      final linuxOutput = ErrorLogger.redactPii(linuxPath);
      expect(linuxOutput, contains('[REDACTED_USER_PATH]'));
      expect(linuxOutput, isNot(contains('/home/eslam')));
    });

    test('redactPii scrubs Android internal app and storage directory paths', () {
      final appPath = 'Database file at /data/user/0/com.pulsr.music/databases/pulsr.db';
      final appOutput = ErrorLogger.redactPii(appPath);
      expect(appOutput, contains('[REDACTED_DEVICE_PATH]'));
      expect(appOutput, isNot(contains('/data/user/0/com.pulsr.music')));

      final storagePath = 'Scanned file at /storage/emulated/0/Music/song.mp3';
      final storageOutput = ErrorLogger.redactPii(storagePath);
      expect(storageOutput, contains('[REDACTED_DEVICE_PATH]'));
      expect(storageOutput, isNot(contains('/storage/emulated/0')));
    });

    test('redactPii scrubs user and member identifiers', () {
      final input1 = 'Party sync error for userId: "u_secret_48291"';
      final output1 = ErrorLogger.redactPii(input1);
      expect(output1, contains('userId: [REDACTED_ID]'));
      expect(output1, isNot(contains('u_secret_48291')));

      final input2 = 'WebSocket disconnect memberId="m_992144"';
      final output2 = ErrorLogger.redactPii(input2);
      expect(output2, contains('memberId: [REDACTED_ID]'));
      expect(output2, isNot(contains('m_992144')));
    });
  });
}
