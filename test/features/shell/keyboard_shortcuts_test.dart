import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/shell/presentation/widgets/player_shortcut_scope.dart';

void main() {
  late Map<String, int> calls;

  void hit(String name) => calls[name] = (calls[name] ?? 0) + 1;

  Widget build({bool withTextField = false}) {
    return MaterialApp(
      home: PlayerShortcutScope(
        onTogglePlayPause: () => hit('playPause'),
        onSeekForward: () => hit('seekForward'),
        onSeekBackward: () => hit('seekBackward'),
        onVolumeUp: () => hit('volumeUp'),
        onVolumeDown: () => hit('volumeDown'),
        onNext: () => hit('next'),
        onPrevious: () => hit('previous'),
        onToggleMute: () => hit('mute'),
        onToggleLyrics: () => hit('lyrics'),
        onToggleQueue: () => hit('queue'),
        child: Scaffold(
          body: withTextField
              ? const Center(child: TextField())
              : const SizedBox.expand(),
        ),
      ),
    );
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  setUp(() => calls = <String, int>{});

  testWidgets('space toggles play/pause', (tester) async {
    await tester.pumpWidget(build());
    await tester.pump();
    await press(tester, LogicalKeyboardKey.space);
    expect(calls['playPause'], 1);
  });

  testWidgets('arrow keys seek and adjust volume', (tester) async {
    await tester.pumpWidget(build());
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(calls['seekForward'], 1);
    expect(calls['seekBackward'], 1);
    expect(calls['volumeUp'], 1);
    expect(calls['volumeDown'], 1);
  });

  testWidgets('N/P/M/L/Q map to their actions', (tester) async {
    await tester.pumpWidget(build());
    await tester.pump();
    await press(tester, LogicalKeyboardKey.keyN);
    await press(tester, LogicalKeyboardKey.keyP);
    await press(tester, LogicalKeyboardKey.keyM);
    await press(tester, LogicalKeyboardKey.keyL);
    await press(tester, LogicalKeyboardKey.keyQ);
    expect(calls['next'], 1);
    expect(calls['previous'], 1);
    expect(calls['mute'], 1);
    expect(calls['lyrics'], 1);
    expect(calls['queue'], 1);
  });

  testWidgets('shortcuts are suppressed while a text field is focused',
      (tester) async {
    await tester.pumpWidget(build(withTextField: true));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.space);
    await press(tester, LogicalKeyboardKey.keyN);
    expect(calls['playPause'], isNull);
    expect(calls['next'], isNull);
  });

  testWidgets('isTextInputFocused is false with no focus', (tester) async {
    expect(PlayerShortcutScope.isTextInputFocused(), isFalse);
  });
}
