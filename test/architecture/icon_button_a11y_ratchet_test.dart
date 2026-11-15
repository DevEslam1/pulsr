import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';

import '../helpers/screen_harness.dart';

String _balancedParenBlock(String text, int startIdx) {
  final openIdx = text.indexOf('(', startIdx);
  if (openIdx == -1) return '';
  var depth = 0;
  for (var i = openIdx; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if (code == 40) {
      depth++;
    } else if (code == 41) {
      depth--;
      if (depth == 0) {
        return text.substring(startIdx, i + 1);
      }
    }
  }
  return text.substring(startIdx);
}

void main() {
  test('every IconButton in lib/ specifies a tooltip', () {
    final root = Directory('lib');
    final pattern = RegExp(
      r'\bIconButton(?:\.(?:filled|filledTonal|outlined))?\s*\(',
    );
    final offenders = <String>[];

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final m in pattern.allMatches(text)) {
        final blk = _balancedParenBlock(text, m.start);
        if (!blk.contains('tooltip:')) {
          final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
          offenders.add('${entity.path}:$line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Every IconButton must have a localized tooltip for accessibility.',
    );
  });

  testWidgets('SongTile more IconButton meets 48dp minimum touch target',
      (tester) async {
    const song = SongsTableData(
      id: 1,
      title: 'Test Track',
      artist: 'Test Artist',
      album: 'Test Album',
      durationMs: 120000,
      path: '/music/test.mp3',
      dateAdded: 0,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
      source: 'local',
    );
    await tester.pumpWidget(
      screenHarness(
        providers: [
          BlocProvider<PlayerCubit>.value(value: stubPlayerCubit()),
        ],
        child: Scaffold(
          body: SongTile(
            song: song,
            onTap: () {},
            onMorePressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final moreFinder = find.widgetWithIcon(IconButton, Icons.more_vert_rounded);
    expect(moreFinder, findsOneWidget);
    final size = tester.getSize(moreFinder);
    expect(size.width, greaterThanOrEqualTo(48.0));
    expect(size.height, greaterThanOrEqualTo(48.0));
  });
}
