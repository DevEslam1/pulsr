// Covers lib/features/settings/presentation/widgets/ytm_account_disconnect_dialog.dart
// (render, cancel, confirm/disconnect and the in-flight busy state).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/settings/presentation/widgets/ytm_account_disconnect_dialog.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockYtmAccountService extends Mock implements YtmAccountService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockYtmAccountService account;

  setUp(() {
    account = MockYtmAccountService();
    when(() => account.accountName).thenReturn('Test User');
    when(() => account.logout()).thenAnswer((_) async {});
    getIt.registerSingleton<YtmAccountService>(account);
  });

  tearDown(() async {
    await getIt.unregister<YtmAccountService>();
  });

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showYtmAccountDisconnectDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the connected account and all three actions',
      (tester) async {
    await openDialog(tester);

    expect(find.text(l10n.ytmAccount), findsOneWidget);
    expect(find.text(l10n.settingsConnectedAs('Test User')), findsOneWidget);
    expect(find.text(l10n.openWebPlayer), findsOneWidget);
    expect(find.text(l10n.cancel), findsOneWidget);
    expect(find.text(l10n.disconnect), findsOneWidget);
  });

  testWidgets('cancel closes the dialog without logging out', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    expect(find.text(l10n.disconnect), findsNothing);
    verifyNever(() => account.logout());
  });

  testWidgets('disconnect logs out, closes and shows a snackbar',
      (tester) async {
    await openDialog(tester);

    await tester.tap(find.text(l10n.disconnect));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => account.logout()).called(1);
    expect(find.text(l10n.disconnect), findsNothing);
    expect(find.text(l10n.ytmDisconnected), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('while disconnecting every action is disabled',
      (tester) async {
    final completer = Completer<void>();
    when(() => account.logout()).thenAnswer((_) => completer.future);

    await openDialog(tester);

    await tester.tap(find.text(l10n.disconnect));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final filled = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(filled.onPressed, isNull);
    for (final button in tester.widgetList<TextButton>(
      find.byType(TextButton),
    )) {
      expect(button.onPressed, isNull);
    }

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text(l10n.disconnect), findsNothing);
  });
}
