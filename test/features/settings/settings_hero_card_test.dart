// Covers lib/features/settings/presentation/widgets/settings_hero_card.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/auth/cubit/auth_cubit.dart';
import 'package:pulsr/features/auth/cubit/auth_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_hero_card.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockAuthCubit extends Mock implements AuthCubit {}

class MockUser extends Mock implements User {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockAuthCubit auth;

  setUp(() {
    auth = MockAuthCubit();
  });

  void stubState(AuthState state) {
    when(() => auth.state).thenReturn(state);
    when(() => auth.stream).thenAnswer((_) => const Stream<AuthState>.empty());
  }

  Future<void> pump(
    WidgetTester tester, {
    AuthState? state,
    Size size = const Size(420, 900),
  }) async {
    auth = MockAuthCubit();
    stubState(state ?? const AuthState());
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      BlocProvider<AuthCubit>.value(
        value: auth,
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SettingsHeroCard()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('signed-out state shows cloud sync copy and sign-in action',
      (tester) async {
    await pump(tester, state: const AuthState());

    expect(find.text(l10n.cloudSync), findsOneWidget);
    expect(find.text(l10n.cloudSyncSubtitle), findsOneWidget);
    expect(find.text(l10n.signIn), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    expect(find.text(l10n.syncedLabel), findsNothing);
  });

  testWidgets('signed-in idle state shows identity, synced badge and actions',
      (tester) async {
    final user = MockUser();
    when(() => user.displayName).thenReturn('Eslam');
    when(() => user.email).thenReturn('eslam@example.com');
    when(() => user.photoURL).thenReturn(null);

    await pump(
      tester,
      state: AuthState(
        status: AuthStatus.authenticated,
        user: user,
        syncStatus: SyncStatus.idle,
      ),
    );

    expect(find.text('Eslam'), findsOneWidget);
    expect(find.text(l10n.syncedLabel), findsOneWidget);
    expect(find.text(l10n.connectedReadyToSync), findsOneWidget);
    expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
  });

  testWidgets('sync-now and sign-out actions call the auth cubit',
      (tester) async {
    final user = MockUser();
    when(() => user.displayName).thenReturn('Eslam');
    when(() => user.email).thenReturn(null);
    when(() => user.photoURL).thenReturn(null);

    await pump(
      tester,
      state: AuthState(
        status: AuthStatus.authenticated,
        user: user,
        syncStatus: SyncStatus.idle,
      ),
    );
    when(() => auth.syncNow()).thenAnswer((_) async {});
    when(() => auth.signOut()).thenAnswer((_) async {});

    await tester.tap(find.byIcon(Icons.sync_rounded));
    await tester.pump();
    verify(() => auth.syncNow()).called(1);

    await tester.tap(find.byIcon(Icons.logout_rounded));
    await tester.pump();
    verify(() => auth.signOut()).called(1);
  });

  testWidgets('syncing state shows spinner and updates subtitle',
      (tester) async {
    final user = MockUser();
    when(() => user.displayName).thenReturn('Eslam');
    when(() => user.email).thenReturn(null);
    when(() => user.photoURL).thenReturn(null);

    await pump(
      tester,
      state: AuthState(
        status: AuthStatus.authenticated,
        user: user,
        syncStatus: SyncStatus.syncing,
      ),
    );

    expect(find.text(l10n.settingsSyncingLibrary), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('last-synced copy covers just-now, minutes and hours branches',
      (tester) async {
    final user = MockUser();
    when(() => user.displayName).thenReturn('Eslam');
    when(() => user.email).thenReturn(null);
    when(() => user.photoURL).thenReturn(null);

    await pump(
      tester,
      state: AuthState(
        status: AuthStatus.authenticated,
        user: user,
        syncStatus: SyncStatus.success,
        lastSyncedAt: DateTime.now(),
      ),
    );
    expect(find.text(l10n.lastSyncedJustNow), findsOneWidget);

    final tenMinAgo = DateTime.now().subtract(const Duration(minutes: 10));
    await pump(
      tester,
      state: AuthState(
        status: AuthStatus.authenticated,
        user: user,
        syncStatus: SyncStatus.success,
        lastSyncedAt: tenMinAgo,
      ),
    );
    final expectedMinutes = DateTime.now().difference(tenMinAgo).inMinutes;
    expect(find.text(l10n.lastSyncedMinutesAgo(expectedMinutes)),
        findsOneWidget);

    final fiveHoursAgo = DateTime.now().subtract(const Duration(hours: 5));
    await pump(
      tester,
      state: AuthState(
        status: AuthStatus.authenticated,
        user: user,
        syncStatus: SyncStatus.success,
        lastSyncedAt: fiveHoursAgo,
      ),
    );
    expect(find.text(l10n.lastSyncedHoursAgo(5)), findsOneWidget);
  });

  testWidgets('sync error renders the error banner', (tester) async {
    final user = MockUser();
    when(() => user.displayName).thenReturn('Eslam');
    when(() => user.email).thenReturn(null);
    when(() => user.photoURL).thenReturn(null);

    await pump(
      tester,
      state: AuthState(
        status: AuthStatus.authenticated,
        user: user,
        syncStatus: SyncStatus.failure,
        syncError: 'Network unavailable',
      ),
    );

    expect(find.text('Network unavailable'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  testWidgets('narrow width stacks identity above the action row',
      (tester) async {
    final user = MockUser();
    when(() => user.displayName).thenReturn('Eslam');
    when(() => user.email).thenReturn(null);
    when(() => user.photoURL).thenReturn(null);

    await pump(
      tester,
      size: const Size(340, 900),
      state: AuthState(
        status: AuthStatus.authenticated,
        user: user,
        syncStatus: SyncStatus.idle,
      ),
    );

    expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
    expect(find.text('Eslam'), findsOneWidget);
  });

  testWidgets('falls back to email when display name is missing',
      (tester) async {
    final user = MockUser();
    when(() => user.displayName).thenReturn(null);
    when(() => user.email).thenReturn('eslam@example.com');
    when(() => user.photoURL).thenReturn(null);

    await pump(
      tester,
      state: AuthState(
        status: AuthStatus.authenticated,
        user: user,
        syncStatus: SyncStatus.idle,
      ),
    );

    expect(find.text('eslam@example.com'), findsOneWidget);
  });

  testWidgets('network avatar uses the error builder when the image fails',
      (tester) async {
    final user = MockUser();
    when(() => user.displayName).thenReturn('Eslam');
    when(() => user.email).thenReturn(null);
    when(() => user.photoURL).thenReturn('https://example.com/avatar.png');

    await pump(
      tester,
      state: AuthState(
        status: AuthStatus.authenticated,
        user: user,
        syncStatus: SyncStatus.idle,
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
  });
}
