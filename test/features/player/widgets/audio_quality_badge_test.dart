// test/features/player/widgets/audio_quality_badge_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_quality_badge.dart';

import 'player_sheet_test_support.dart';

void main() {
  testWidgets(
      'an unresolved YouTube stream shows the selected tier instead of Unknown',
      (tester) async {
    final settings = stubSettingsCubit();

    await tester.pumpWidget(sheetHost(
      settingsCubit: settings,
      child: const AudioQualityBadge(
        song: ytSong,
        activeColor: Colors.teal,
        compact: true,
        showDevice: false,
      ),
    ));
    await tester.pump();

    expect(find.text('YTM • HIGH'), findsOneWidget);
    expect(find.textContaining('Unknown'), findsNothing);
  });
}
