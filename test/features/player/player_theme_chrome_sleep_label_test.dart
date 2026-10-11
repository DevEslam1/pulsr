// test/features/player/player_theme_chrome_sleep_label_test.dart
//
// The dock badge/tooltip must not round a sub-minute timer down to "0m" nor a
// 90-minute timer up to "90m".
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_chrome.dart';

void main() {
  test('sleep timer label formats seconds, minutes and hours truthfully', () {
    expect(formatSleepTimerRemaining(const Duration(seconds: 59)), '59s');
    expect(formatSleepTimerRemaining(const Duration(minutes: 1)), '1m');
    expect(formatSleepTimerRemaining(const Duration(minutes: 15)), '15m');
    expect(formatSleepTimerRemaining(const Duration(minutes: 59)), '59m');
    expect(formatSleepTimerRemaining(const Duration(minutes: 60)), '1h');
    expect(formatSleepTimerRemaining(const Duration(minutes: 90)), '1h 30m');
    expect(formatSleepTimerRemaining(const Duration(hours: 2)), '2h');
    expect(formatSleepTimerRemaining(Duration.zero), '0s');
    expect(formatSleepTimerRemaining(const Duration(seconds: -5)), '0s');
  });
}
