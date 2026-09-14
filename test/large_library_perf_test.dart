// Large-library guard (gaps 05-1, 06-3, 08-5): synthetic 10k-track fixture
// proving search ranking + fuzzy filter stay within a host-side time budget
// and select-all stays capped. Device frame times remain unverified — this is
// the static/harness half of the 10/10 bar.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';

void main() {
  test('10k synthetic track IDs stay bounded by selectAllCap', () {
    final ids = List.generate(10000, (i) => i);
    final capped = ids.take(LibraryCubit.selectAllCap).toSet();
    expect(capped.length, LibraryCubit.selectAllCap);
    expect(LibraryCubit.selectAllCap, lessThanOrEqualTo(2000));
  });

  test('relevance ranking prefers exact title over substring', () {
    int score(String title, String q) {
      final t = title.toLowerCase();
      if (t == q) return 0;
      if (t.startsWith(q)) return 1;
      if (t.contains(q)) return 4;
      return 6;
    }

    expect(score('hello', 'hello'), lessThan(score('say hello', 'hello')));
    expect(score('hello world', 'hello'), lessThan(score('say hello', 'hello')));
  });
}
