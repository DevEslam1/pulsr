// test/features/player/widgets/audio_signal_path_card_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/audio_signal_path.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_signal_path_card.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';
void main() {
  testWidgets('AudioSignalPathCard displays all 4 real-time signal stages',
      (tester) async {
    final path = AudioSignalPath.fromOutputInfo(
      sourceCodec: 'FLAC',
      sourceSampleRate: 192000,
      sourceBitDepth: 24,
      uac2DirectActive: true,
      output: const AudioOutputInfo(
        deviceName: 'Chord Mojo 2',
        isUsbDac: true,
        sampleRate: 192000,
        bitDepth: 24,
        decodedSampleRate: 192000,
        decodedBitDepth: 24,
        decodedPcmEncoding: 21,
        isBitPerfectActive: true,
        activeDeviceType: 'usb',
        usbAudioClass: 2,
        supportedEncodings: ['16', '24', '32'],
        supportedChannelCounts: [2],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AudioSignalPathCard(
              signalPath: path,
              activeColor: Colors.amber,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Audio Signal Path'), findsOneWidget);
    expect(find.text('FLAC (24-bit / 192 kHz)'), findsOneWidget);
    expect(find.text('PCM 24-bit Packed (24-bit / 192 kHz)'), findsOneWidget);
    expect(
        find.textContaining('USB-C DAC (UAC2) • Chord Mojo 2'), findsOneWidget);
    expect(find.textContaining('Encodings: 16, 24, 32'), findsOneWidget);
    expect(
      find.text('Pulsr UAC2 Isochronous • 24-bit / 192 kHz (Bit-Perfect)'),
      findsOneWidget,
    );
  });
}
