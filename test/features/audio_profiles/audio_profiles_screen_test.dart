// test/features/audio_profiles/audio_profiles_screen_test.dart
//
// Screen wiring test: the default-profile action opens the selector, persists
// the choice through AudioProfileService.setGlobalDefaults and can clear it.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/features/audio_profiles/audio_profile.dart';
import 'package:pulsr/features/audio_profiles/audio_profile_service.dart';
import 'package:pulsr/features/audio_profiles/audio_profile_strings.dart';
import 'package:pulsr/features/audio_profiles/audio_profiles_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory service so the screen test never touches the file system.
class _FakeAudioProfileService extends AudioProfileService {
  _FakeAudioProfileService({
    required super.prefs,
    required this.profiles,
  });

  final List<AudioProfile> profiles;
  String? _defaultId;
  int defaultWrites = 0;

  @override
  String? get defaultProfileId => _defaultId;

  @override
  Future<List<AudioProfile>> list() async => profiles;

  @override
  Future<bool> setGlobalDefaults(String? profileId) async {
    defaultWrites++;
    _defaultId = profileId;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _FakeAudioProfileService service;
  late AudioProfile profile;

  setUp(() async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    profile = AudioProfile(
      id: 'ap_screen',
      name: 'Desk setup',
      createdAt: DateTime.utc(2026, 1, 2),
      appVersion: '1.0.0',
    );
    service = _FakeAudioProfileService(
      prefs: prefs,
      profiles: <AudioProfile>[profile],
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AudioProfilesScreen(service: service)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('default selector sets and clears the default profile',
      (tester) async {
    await pumpScreen(tester);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.star_border_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip(AudioProfileStrings.defaultTooltip));
    await tester.pumpAndSettle();
    expect(find.text(AudioProfileStrings.defaultDialogTitle), findsOneWidget);

    await tester.tap(find.text('Desk setup').last);
    await tester.pumpAndSettle();

    expect(service.defaultWrites, 1);
    expect(service.defaultProfileId, profile.id);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip(AudioProfileStrings.defaultTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AudioProfileStrings.defaultNone));
    await tester.pumpAndSettle();

    expect(service.defaultWrites, 2);
    expect(service.defaultProfileId, isNull);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.star_border_rounded),
      ),
      findsOneWidget,
    );
  });
}
