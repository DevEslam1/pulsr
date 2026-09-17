// Verifies the display-site localization of PlayerCubit error strings:
// known literals resolve (EN here), parameterized templates keep data, and
// unknown literals pass through unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/error_message_resolver.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('resolveUiErrorMessage maps known errors', (tester) async {
    final results = <String, String>{};
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            String r(String m) => resolveUiErrorMessage(context, m);
            results['static'] = r('Shuffle failed');
            results['song'] = r('Failed to play Hello');
            results['queueFull'] = r('Queue full (50) - cannot add more');
            results['dsp'] = r('Failed to set bass boost: boom');
            results['search'] = r('Search failed');
            results['playlistName'] = r('Please enter a playlist name');
            results['wifiOnly'] =
                r('Wi-Fi Only Mode is active. Connect to Wi-Fi to download.');
            results['storage'] =
                r('Insufficient storage space for downloading audio');
            results['unknown'] = r('Something entirely new');
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(results['static'], 'Shuffle failed');
    expect(results['song'], 'Failed to play "Hello"');
    expect(results['queueFull'], 'Queue is full (50) — cannot add more');
    expect(results['dsp'], 'Failed to apply audio setting: boom');
    expect(results['search'], isNot('Search failed'));
    expect(results['playlistName'], isNot('Please enter a playlist name'));
    expect(results['wifiOnly'], contains('Wi-Fi'));
    expect(results['storage'], isNot('Insufficient storage space for downloading audio'));
    expect(results['unknown'], 'Something entirely new');
  });
}
