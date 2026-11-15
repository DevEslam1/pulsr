import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_pill_tab_bar.dart';
import 'package:pulsr/core/widgets/pulsr_scroll_edge_fade.dart';
import 'package:pulsr/core/widgets/pulsr_segmented_control.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AuraTheme.darkTheme,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'PulsrPillTabBar uses EQ pill container and solid accent pill indicator',
      (tester) async {
    await tester.pumpWidget(
      _host(
        DefaultTabController(
          length: 3,
          child: Builder(
            builder: (context) => PulsrPillTabBar(
              controller: DefaultTabController.of(context),
              tabs: const [
                Tab(text: 'Equalizer'),
                Tab(text: 'AutoEq'),
                Tab(text: 'Spatial & DSP'),
              ],
            ),
          ),
        ),
      ),
    );

    final palette = tester.element(find.byType(PulsrPillTabBar)).palette;
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(PulsrPillTabBar),
            matching: find.byType(Container),
          )
          .first,
    );
    final outerDecoration = container.decoration! as BoxDecoration;
    expect(outerDecoration.color, palette.surfaceContainer);
    expect(outerDecoration.borderRadius, AppRadii.r20All);

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    final indicator = tabBar.indicator! as BoxDecoration;
    expect(indicator.color, palette.accent);
    expect(indicator.borderRadius, AppRadii.r20All);
    expect(tabBar.indicatorSize, TabBarIndicatorSize.tab);
    expect(tabBar.labelColor, palette.onAccent);
    expect(tabBar.unselectedLabelColor, palette.textSecondary);
    expect(tabBar.dividerColor, Colors.transparent);

    await tester.tap(find.text('AutoEq'));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(TabBar));
    expect(DefaultTabController.of(ctx).index, 1);
  });

  testWidgets('PulsrPillTabBar supports scrollable tabs with edge fade',
      (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 240,
          child: DefaultTabController(
            length: 5,
            child: Builder(
              builder: (context) => PulsrPillTabBar(
                controller: DefaultTabController.of(context),
                isScrollable: true,
                scrollEdgeFade: true,
                tabs: const [
                  Tab(text: 'Songs'),
                  Tab(text: 'Downloaded'),
                  Tab(text: 'Albums'),
                  Tab(text: 'Artists'),
                  Tab(text: 'Favorites'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(PulsrScrollEdgeFade), findsOneWidget);
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.isScrollable, isTrue);
    expect(tabBar.tabAlignment, TabAlignment.start);
  });

  testWidgets(
      'PulsrSegmentedControl uses EQ pill styling in sliding and static modes',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PulsrSegmentedControl(
          segments: const [
            PulsrSegment(label: 'Local', icon: Icons.folder_rounded),
            PulsrSegment(label: 'Online', icon: Icons.cloud_rounded),
          ],
          selectedIndex: 0,
          onChanged: (_) {},
        ),
      ),
    );

    final palette = tester.element(find.byType(PulsrSegmentedControl)).palette;

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(PulsrSegmentedControl),
            matching: find.byType(Container),
          )
          .first,
    );
    final outerDecoration = container.decoration! as BoxDecoration;
    expect(outerDecoration.color, palette.surfaceContainer);
    expect(outerDecoration.borderRadius, AppRadii.r20All);

    final indicator = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(AnimatedPositionedDirectional),
        matching: find.byType(DecoratedBox),
      ),
    );
    final indicatorDecoration = indicator.decoration as BoxDecoration;
    expect(indicatorDecoration.color, palette.accent);
    expect(indicatorDecoration.borderRadius, AppRadii.r20All);

    int selected = 0;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => PulsrSegmentedControl(
            slidingIndicator: false,
            segments: const [
              PulsrSegment(label: 'Local', icon: Icons.folder_rounded),
              PulsrSegment(label: 'Online', icon: Icons.cloud_rounded),
            ],
            selectedIndex: selected,
            onChanged: (i) => setState(() => selected = i),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });
}
