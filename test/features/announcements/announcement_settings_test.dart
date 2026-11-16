// test/features/announcements/announcement_settings_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/announcements/announcement_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loads the documented defaults on a fresh install', () async {
    final settings = await AnnouncementSettings.load();
    addTearDown(settings.dispose);

    expect(settings.enabled, isFalse);
    expect(settings.elements, [
      AnnouncementElement.title,
      AnnouncementElement.artist,
    ]);
    expect(settings.delayMs, 1500);
    expect(settings.volume, 0.8);
    expect(settings.duckAudio, isTrue);
    expect(settings.skipWhenCasting, isTrue);
    expect(settings.skipWhenBitPerfect, isTrue);
    expect(settings.voiceId, '');
    expect(settings.localeId, '');
    expect(settings.maxLength, 160);
  });

  test('round-trips every field through the preference store', () async {
    final settings = await AnnouncementSettings.load();
    settings.setEnabled(true);
    settings.setElements([
      AnnouncementElement.album,
      AnnouncementElement.title,
      AnnouncementElement.year,
    ]);
    settings.setDelayMs(2500);
    settings.setVolume(0.45);
    settings.setDuckAudio(false);
    settings.setSkipWhenCasting(false);
    settings.setSkipWhenBitPerfect(false);
    settings.setVoiceId('en-gb-x-gba-local');
    settings.setLocaleId('en-GB');
    settings.setMaxLength(220);
    await settings.save();
    settings.dispose();

    final restored = await AnnouncementSettings.load();
    addTearDown(restored.dispose);

    expect(restored.enabled, isTrue);
    expect(restored.elements, [
      AnnouncementElement.album,
      AnnouncementElement.title,
      AnnouncementElement.year,
    ]);
    expect(restored.delayMs, 2500);
    expect(restored.volume, 0.45);
    expect(restored.duckAudio, isFalse);
    expect(restored.skipWhenCasting, isFalse);
    expect(restored.skipWhenBitPerfect, isFalse);
    expect(restored.voiceId, 'en-gb-x-gba-local');
    expect(restored.localeId, 'en-GB');
    expect(restored.maxLength, 220);
  });

  test('ignores element names this build does not know', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AnnouncementSettings.keyElements: [
        'title',
        'speakerBias',
        'album',
        'title',
      ],
    });

    final settings = await AnnouncementSettings.load();
    addTearDown(settings.dispose);

    expect(settings.elements, [
      AnnouncementElement.title,
      AnnouncementElement.album,
    ]);
  });

  test('falls back to defaults when every stored name is unknown', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AnnouncementSettings.keyElements: ['speakerBias', 'mood'],
    });

    final settings = await AnnouncementSettings.load();
    addTearDown(settings.dispose);

    expect(settings.elements, AnnouncementSettings.defaultElements);
  });

  test('keeps an empty element list as an explicit choice', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AnnouncementSettings.keyElements: <String>[],
    });

    final settings = await AnnouncementSettings.load();
    addTearDown(settings.dispose);

    expect(settings.elements, isEmpty);
  });

  test('clamps persisted values into their supported ranges', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AnnouncementSettings.keyDelayMs: 99999,
      AnnouncementSettings.keyVolume: 3.0,
      AnnouncementSettings.keyMaxLength: 5000,
    });

    final settings = await AnnouncementSettings.load();
    addTearDown(settings.dispose);

    expect(settings.delayMs, AnnouncementSettings.maxDelayMs);
    expect(settings.volume, AnnouncementSettings.maxVolume);
    expect(settings.maxLength, AnnouncementSettings.maxMaxLength);
  });

  test('setters clamp their input and notify listeners once', () async {
    final settings = await AnnouncementSettings.load();
    addTearDown(settings.dispose);
    var notifications = 0;
    settings.addListener(() => notifications++);

    settings.setDelayMs(-500);
    settings.setVolume(0.1);
    settings.setMaxLength(1);

    expect(settings.delayMs, AnnouncementSettings.minDelayMs);
    expect(settings.volume, AnnouncementSettings.minVolume);
    expect(settings.maxLength, AnnouncementSettings.minMaxLength);
    expect(notifications, 3);
  });

  test('adds elements in selection order and removes on toggle off', () async {
    final settings = await AnnouncementSettings.load();
    addTearDown(settings.dispose);

    settings.setElements([AnnouncementElement.title]);
    settings.setElementEnabled(AnnouncementElement.album, true);
    settings.setElementEnabled(AnnouncementElement.artist, true);
    expect(settings.elements, [
      AnnouncementElement.title,
      AnnouncementElement.album,
      AnnouncementElement.artist,
    ]);

    settings.setElementEnabled(AnnouncementElement.title, false);
    expect(settings.elements, [
      AnnouncementElement.album,
      AnnouncementElement.artist,
    ]);
  });
}
