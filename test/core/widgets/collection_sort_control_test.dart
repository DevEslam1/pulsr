import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/presentation/widgets/collection_sort_control.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

enum _TestSort { name, date, size }

Widget _host({
  required _TestSort currentSort,
  required bool ascending,
  required ValueChanged<_TestSort> onSortChanged,
  required ValueChanged<bool> onDirectionChanged,
}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: CollectionSortControl<_TestSort>(
            currentSort: currentSort,
            ascending: ascending,
            options: const [
              CollectionSortOption(
                value: _TestSort.name,
                label: 'Name',
                icon: Icons.sort_by_alpha_rounded,
              ),
              CollectionSortOption(
                value: _TestSort.date,
                label: 'Date',
                icon: Icons.calendar_today_rounded,
              ),
              CollectionSortOption(
                value: _TestSort.size,
                label: 'Size',
                icon: Icons.storage_rounded,
              ),
            ],
            onSortChanged: onSortChanged,
            onDirectionChanged: onDirectionChanged,
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders sort mode label and direction icon', (tester) async {
    await tester.pumpWidget(_host(
      currentSort: _TestSort.name,
      ascending: true,
      onSortChanged: (_) {},
      onDirectionChanged: (_) {},
    ));
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
  });

  testWidgets('changing sort mode invokes onSortChanged', (tester) async {
    _TestSort? changed;
    await tester.pumpWidget(_host(
      currentSort: _TestSort.name,
      ascending: true,
      onSortChanged: (v) => changed = v,
      onDirectionChanged: (_) {},
    ));
    await tester.pumpAndSettle();

    final dropdown = find.byType(DropdownButton<_TestSort>);
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Date').last);
    await tester.pumpAndSettle();

    expect(changed, _TestSort.date);
  });

  testWidgets('tapping direction button invokes onDirectionChanged',
      (tester) async {
    bool? newAsc;
    await tester.pumpWidget(_host(
      currentSort: _TestSort.name,
      ascending: true,
      onSortChanged: (_) {},
      onDirectionChanged: (v) => newAsc = v,
    ));
    await tester.pumpAndSettle();

    final directionBtn = find.byType(InkWell).last;
    await tester.tap(directionBtn);
    await tester.pumpAndSettle();

    expect(newAsc, isFalse);
  });
}
