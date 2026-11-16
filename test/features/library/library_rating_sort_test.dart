import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';

void main() {
  final keys = <({int index, int rating, String title})>[
    (index: 0, rating: 3, title: 'b'),
    (index: 1, rating: 5, title: 'a'),
    (index: 2, rating: 5, title: 'c'),
    (index: 3, rating: 0, title: 'a'),
  ];

  test('rating sort keeps the legacy ordering', () {
    expect(sortSongIndicesByRating(keys, false), [1, 2, 0, 3]);
    expect(sortSongIndicesByRating(keys, true), [3, 0, 1, 2]);
  });

  test('rating sort is sendable and gives identical results in an isolate',
      () async {
    final inIsolate =
        await Isolate.run(() => sortSongIndicesByRating(keys, false));
    expect(inIsolate, sortSongIndicesByRating(keys, false));
  });
}
