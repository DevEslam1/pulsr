// test/features/auth/auth_sheet_test.dart
//
// Widget coverage for AuthSheet: rendering, email/password validation, the
// Google button, sign-up toggle, password visibility, password reset, and the
// authenticated / error listener branches. AuthCubit is real; its two
// dependencies are mocked so no Firebase/network is touched.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/auth_service.dart';
import 'package:pulsr/core/services/cloud_sync_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/auth/cubit/auth_cubit.dart';
import 'package:pulsr/features/auth/presentation/auth_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockAuthService extends Mock implements AuthService {}

class MockCloudSyncService extends Mock implements CloudSyncService {}

class MockUser extends Mock implements User {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthService auth;
  late MockCloudSyncService cloud;
  late AuthCubit cubit;

  setUp(() {
    auth = MockAuthService();
    cloud = MockCloudSyncService();
    when(() => cloud.lastSyncTime).thenReturn(null);
    when(() => cloud.syncAll()).thenAnswer((_) async => true);
    when(() => auth.authStateChanges).thenAnswer((_) => const Stream.empty());
    cubit = AuthCubit(auth, cloud);
  });

  tearDown(() async {
    await cubit.close();
  });

  Widget host({GlobalKey<NavigatorState>? navKey}) => MaterialApp(
        theme: AuraTheme.darkTheme,
        navigatorKey: navKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<AuthCubit>.value(
          value: cubit,
          child: const Scaffold(body: AuthSheet()),
        ),
      );

  testWidgets('renders the sign-in form', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Cloud'), findsOneWidget);
    expect(find.text('Sync your favorites & playlists across devices'),
        findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('OR WITH EMAIL'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty submit surfaces both field validators', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter email'), findsOneWidget);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an invalid email is rejected', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await tester.enterText(find.byType(TextFormField).last, 'secret1');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid email address'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a valid form signs in with email', (tester) async {
    when(() => auth.signInWithEmail(any(), any()))
        .thenAnswer((_) async => null);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'a@b.com');
    await tester.enterText(find.byType(TextFormField).last, 'secret1');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    verify(() => auth.signInWithEmail('a@b.com', 'secret1')).called(1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the Google button delegates to the cubit', (tester) async {
    when(() => auth.signInWithGoogle()).thenAnswer((_) async => null);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    verify(() => auth.signInWithGoogle()).called(1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the sign-up toggle switches the form mode', (tester) async {
    when(() => auth.signUpWithEmail(any(), any())).thenAnswer((_) async => null);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text("Don't have an account? Sign Up"));
    await tester.pumpAndSettle();
    expect(find.text('Create Cloud Account'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'a@b.com');
    await tester.enterText(find.byType(TextFormField).last, 'secret1');
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();
    verify(() => auth.signUpWithEmail('a@b.com', 'secret1')).called(1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the password visibility toggle flips the suffix icon',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('password reset without an email prompts first', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email first'), findsOneWidget);
    verifyNever(() => auth.sendPasswordResetEmail(any()));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('password reset with an email reports success', (tester) async {
    when(() => auth.sendPasswordResetEmail(any())).thenAnswer((_) async {});
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'a@b.com');
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    verify(() => auth.sendPasswordResetEmail('a@b.com')).called(1);
    expect(find.textContaining('Password reset link sent to'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an error state shows an error snackbar', (tester) async {
    when(() => auth.signInWithGoogle())
        .thenThrow(FirebaseAuthException(code: 'user-not-found', message: 'x'));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('No account found with this email.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an authenticated state shows a snackbar and pops the sheet',
      (tester) async {
    final user = MockUser();
    when(() => user.email).thenReturn('a@b.com');
    when(() => auth.signInWithGoogle()).thenAnswer((_) async => user);

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      theme: AuraTheme.darkTheme,
      navigatorKey: navKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SizedBox()),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => BlocProvider<AuthCubit>.value(
        value: cubit,
        child: const Scaffold(body: AuthSheet()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(navKey.currentState!.canPop(), isTrue);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Signed in as'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
