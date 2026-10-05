import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/failures.dart';

void main() {
  group('AppFailure Value Equality Tests', () {
    test('Same class with identical message and error are equal', () {
      const f1 = DatabaseFailure('Failed to query table', 'sqlite_err_5');
      const f2 = DatabaseFailure('Failed to query table', 'sqlite_err_5');

      expect(f1, equals(f2));
      expect(f1.hashCode, equals(f2.hashCode));
    });

    test('Different classes with identical message are not equal', () {
      const dbFailure = DatabaseFailure('Disk error');
      const storageFailure = StorageFailure('Disk error');

      expect(dbFailure, isNot(equals(storageFailure)));
    });

    test('Same class with different messages are not equal', () {
      const f1 = AudioPlaybackFailure('File missing');
      const f2 = AudioPlaybackFailure('Codec unsupported');

      expect(f1, isNot(equals(f2)));
      expect(f1.hashCode, isNot(equals(f2.hashCode)));
    });

    test('Result Either comparisons work by value', () {
      final Result<String> r1 = Result.left(const DatabaseFailure('Error 1'));
      final Result<String> r2 = Result.left(const DatabaseFailure('Error 1'));
      final Result<String> r3 = Result.left(const DatabaseFailure('Error 2'));

      expect(r1 == r2, isTrue);
      expect(r1 == r3, isFalse);
    });
  });
}
