// test/features/assistant/assistant_settings_screen_test.dart
//
// The suggestion toggle is the only assistant surface with a side effect on
// tap. These tests pin that turning it off clears the native cache, and that a
// failing clear is reported through ErrorLogger (never debugPrint) without
// escaping into the widget tree.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/utils/error_logger.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/features/assistant/assistant_search_channel.dart';
import 'package:pulsr/features/assistant/assistant_settings.dart';
import 'package:pulsr/features/assistant/assistant_settings_screen.dart';
import 'package:pulsr/features/assistant/assistant_strings.dart';
import 'package:pulsr/features/assistant/assistant_suggestion_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockRepository extends Mock implements IMusicRepository {}

class _RecordingSync extends AssistantSuggestionSync {
  _RecordingSync()
      : super(
          repository: _MockRepository(),
          channel: AssistantSearchChannel(
            channel: const MethodChannel('test/assistant'),
          ),
        );

  bool cleared = false;
  bool pushed = false;

  @override
  Future<void> clear() async {
    cleared = true;
  }

  @override
  Future<int> pushRecent({int limit = 20}) async {
    pushed = true;
    return 1;
  }
}

class _ExplodingSync extends AssistantSuggestionSync {
  _ExplodingSync()
      : super(
          repository: _MockRepository(),
          channel: AssistantSearchChannel(
            channel: const MethodChannel('test/assistant'),
          ),
        );

  @override
  Future<void> clear() async => throw StateError('channel unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<({Object error, String category})> reported;

  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    reported = <({Object error, String category})>[];
    ErrorLogger.onCrashReported = (error, stackTrace, category) {
      reported.add((error: error as Object, category: category));
    };
  });

  tearDown(() => ErrorLogger.onCrashReported = null);

  Future<AssistantSettings> enabledSettings() async {
    final settings = await AssistantSettings.load();
    addTearDown(settings.dispose);
    settings.setSuggestionsEnabled(true);
    return settings;
  }

  testWidgets('turning suggestions off clears the native cache', (tester) async {
    final settings = await enabledSettings();
    final sync = _RecordingSync();

    await tester.pumpWidget(
      MaterialApp(
        home: AssistantSettingsScreen(settings: settings, suggestionSync: sync),
      ),
    );
    await tester.tap(find.text(AssistantStrings.suggestionsTitle));
    await tester.pumpAndSettle();

    expect(settings.suggestionsEnabled, isFalse);
    expect(sync.cleared, isTrue);
    expect(find.text(AssistantStrings.suggestionsOffNotice), findsOneWidget);
    expect(reported, isEmpty);
  });

  testWidgets('a failing clear is logged, not printed', (tester) async {
    final settings = await enabledSettings();

    await tester.pumpWidget(
      MaterialApp(
        home: AssistantSettingsScreen(
          settings: settings,
          suggestionSync: _ExplodingSync(),
        ),
      ),
    );
    await tester.tap(find.text(AssistantStrings.suggestionsTitle));
    await tester.pumpAndSettle();

    expect(settings.suggestionsEnabled, isFalse);
    expect(tester.takeException(), isNull);
    expect(reported, hasLength(1));
    expect(reported.single.category, 'Assistant');
    expect(reported.single.error, isStateError);
  });

  testWidgets('turning suggestions on pushes recent suggestions', (tester) async {
    final settings = await AssistantSettings.load();
    addTearDown(settings.dispose);
    settings.setSuggestionsEnabled(false);
    final sync = _RecordingSync();

    await tester.pumpWidget(
      MaterialApp(
        home: AssistantSettingsScreen(settings: settings, suggestionSync: sync),
      ),
    );
    await tester.tap(find.text(AssistantStrings.suggestionsTitle));
    await tester.pumpAndSettle();

    expect(settings.suggestionsEnabled, isTrue);
    expect(sync.pushed, isTrue);
  });
}
