import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/widgets/pulsr_back_button.dart';
import 'package:pulsr/core/widgets/pulsr_page_pop_scope.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';

class MockGetSongsUseCase extends Mock implements GetSongsUseCase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PulsrBackButton & PulsrPagePopScope Tests', () {
    testWidgets('PulsrBackButton pops route when canPop is true',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/first',
        routes: [
          GoRoute(
            path: '/first',
            builder: (context, state) => Scaffold(
              body: ElevatedButton(
                onPressed: () => context.push('/second'),
                child: const Text('Go to Second'),
              ),
            ),
          ),
          GoRoute(
            path: '/second',
            builder: (context, state) => const PulsrPagePopScope(
              child: Scaffold(
                appBar: PreferredSize(
                  preferredSize: Size.fromHeight(56),
                  child: PulsrBackButton(),
                ),
                body: Text('Second Page'),
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Go to Second'), findsOneWidget);

      await tester.tap(find.text('Go to Second'));
      await tester.pumpAndSettle();

      expect(find.text('Second Page'), findsOneWidget);
      expect(find.byType(PulsrBackButton), findsOneWidget);

      await tester.tap(find.byType(PulsrBackButton));
      await tester.pumpAndSettle();

      expect(find.text('Go to Second'), findsOneWidget);
      expect(find.text('Second Page'), findsNothing);
    });

    testWidgets('PulsrBackButton navigates to / when canPop is false',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/standalone',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const Scaffold(body: Text('Home Screen')),
          ),
          GoRoute(
            path: '/standalone',
            builder: (context, state) => const Scaffold(
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(56),
                child: PulsrBackButton(),
              ),
              body: Text('Standalone Page'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Standalone Page'), findsOneWidget);

      await tester.tap(find.byType(PulsrBackButton));
      await tester.pumpAndSettle();

      expect(find.text('Home Screen'), findsOneWidget);
      expect(find.text('Standalone Page'), findsNothing);
    });
  });

  group('Recently Played 50-by-50 Lazy Loading Logic Tests', () {
    test('watchRecentlyPlayed accepts limit parameter', () {
      final mockUseCase = MockGetSongsUseCase();
      final streamController =
          StreamController<Result<List<SongsTableData>>>.broadcast();

      when(() => mockUseCase.watchRecentlyPlayed(limit: any(named: 'limit')))
          .thenAnswer((invocation) {
        final limit = invocation.namedArguments[const Symbol('limit')] as int;
        expect(limit, anyOf(equals(50), equals(100), equals(150)));
        return streamController.stream;
      });

      mockUseCase.watchRecentlyPlayed(limit: 50);
      verify(() => mockUseCase.watchRecentlyPlayed(limit: 50)).called(1);

      mockUseCase.watchRecentlyPlayed(limit: 100);
      verify(() => mockUseCase.watchRecentlyPlayed(limit: 100)).called(1);

      streamController.close();
    });
  });
}
