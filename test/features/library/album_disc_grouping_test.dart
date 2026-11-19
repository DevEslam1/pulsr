// test/features/library/album_disc_grouping_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/library/domain/album_disc_grouping.dart';

void main() {
  AlbumDiscTrack<String> track(
    String id, {
    int? disc,
    int? number,
    String? title,
  }) =>
      AlbumDiscTrack<String>(
        track: id,
        id: id,
        title: title ?? id,
        discNumber: disc,
        trackNumber: number,
      );

  test('all-null disc numbers form one group sorted by track then title', () {
    final groups = groupAlbumDiscs([
      track('b', number: 2, title: 'Beta'),
      track('z', number: 1, title: 'Zulu'),
      track('a', number: 1, title: 'Alpha'),
      track('c', title: 'Charlie'), // no track number -> last
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.discNumber, isNull);
    expect(groups.single.label, 'Unnumbered');
    expect(groups.single.tracks, ['a', 'z', 'b', 'c']);
    expect(groups.isMultiDisc, isFalse);
  });

  test('explicit single-disc albums stay one group without headers', () {
    final groups = groupAlbumDiscs([
      track('b', disc: 1, number: 2),
      track('a', disc: 1, number: 1),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.discNumber, 1);
    expect(groups.single.label, 'Disc 1');
    expect(groups.single.tracks, ['a', 'b']);
    expect(groups.isMultiDisc, isFalse);
  });

  test('multi-disc albums order discs numerically then tracks', () {
    final groups = groupAlbumDiscs([
      track('ten-b', disc: 10, number: 2),
      track('two', disc: 2, number: 1),
      track('ten-a', disc: 10, number: 1),
      track('one', disc: 1, number: 1),
    ]);

    expect(groups.map((group) => group.discNumber), [1, 2, 10]);
    expect(groups.map((group) => group.label), ['Disc 1', 'Disc 2', 'Disc 10']);
    expect(groups[2].tracks, ['ten-a', 'ten-b']);
    expect(groups.isMultiDisc, isTrue);
  });

  test('unnumbered tracks join disc 1 when disc 1 has no explicit tracks', () {
    final groups = groupAlbumDiscs([
      track('disc2', disc: 2, number: 1),
      track('loose-b', number: 2, title: 'Loose B'),
      track('loose-a', number: 1, title: 'Loose A'),
    ]);

    expect(groups.map((group) => group.discNumber), [1, 2]);
    expect(groups.first.label, 'Disc 1');
    expect(groups.first.tracks, ['loose-a', 'loose-b']);
    expect(groups.isMultiDisc, isTrue);
  });

  test('unnumbered tracks get a trailing group when disc 1 is explicit', () {
    final groups = groupAlbumDiscs([
      track('disc1', disc: 1, number: 1),
      track('disc2', disc: 2, number: 1),
      track('loose', number: 1, title: 'Loose'),
    ]);

    expect(groups.map((group) => group.discNumber), [1, 2, null]);
    expect(groups.last.label, 'Unnumbered');
    expect(groups.last.tracks, ['loose']);
    expect(groups.isMultiDisc, isTrue);
  });

  test('disc numbers <= 0 are unnumbered and follow the merge rule', () {
    final merged = groupAlbumDiscs([
      track('zero', disc: 0, number: 2),
      track('negative', disc: -3, number: 1),
      track('disc2', disc: 2, number: 1),
    ]);
    expect(merged.map((group) => group.discNumber), [1, 2]);
    expect(merged.first.tracks, ['negative', 'zero']);

    final trailing = groupAlbumDiscs([
      track('disc1', disc: 1, number: 1),
      track('zero', disc: 0, number: 1),
    ]);
    expect(trailing.map((group) => group.discNumber), [1, null]);
    expect(trailing.last.tracks, ['zero']);
  });

  test('ordering is deterministic for any input order, input is not mutated',
      () {
    final tracks = [
      track('z', disc: 2, number: 2, title: 'Zed'),
      track('a', disc: 1, number: 1, title: 'Alpha'),
      track('b', disc: 1, number: 1, title: 'Alpha'),
      track('c', disc: 2, number: 1, title: 'Cat'),
    ];

    final forward = groupAlbumDiscs(tracks);
    final backward = groupAlbumDiscs(tracks.reversed);

    expect(backward.map((group) => group.discNumber), [1, 2]);
    expect(backward.map((group) => group.tracks), [
      ['a', 'b'],
      ['c', 'z'],
    ]);
    expect(forward.map((group) => group.tracks), [
      ['a', 'b'],
      ['c', 'z'],
    ]);
    // Input order is preserved as-is.
    expect(tracks.map((entry) => entry.id), ['z', 'a', 'b', 'c']);
  });

  test('an empty album has no groups and is not multi-disc', () {
    final groups = groupAlbumDiscs<String>([]);

    expect(groups, isEmpty);
    expect(groups.isMultiDisc, isFalse);
  });
}
