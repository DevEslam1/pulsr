// Regression tests for the O(1) Bloc buildWhen gate helper.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/list_content_diff.dart';

void main() {
  group('listContentDiffers', () {
    test('identical references do not differ', () {
      final a = [1, 2, 3];
      expect(listContentDiffers(a, a), isFalse);
    });

    test('length change signals a difference', () {
      expect(listContentDiffers([1, 2], [1, 2, 3]), isTrue);
    });

    test('empty lists never differ', () {
      expect(listContentDiffers(<int>[], <int>[]), isFalse);
    });

    test('same length, different first element differs', () {
      expect(listContentDiffers([1, 2, 3], [9, 2, 3]), isTrue);
    });

    test('same length, different last element differs', () {
      expect(listContentDiffers([1, 2, 3], [1, 2, 9]), isTrue);
    });

    test('same length and endpoints but different middle is a documented miss',
        () {
      expect(listContentDiffers([1, 2, 3], [1, 9, 3]), isFalse);
    });

    test('equal content in distinct list instances does not differ', () {
      expect(listContentDiffers(['a', 'b'], ['a', 'b']), isFalse);
    });
  });
}
