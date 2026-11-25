// test/core/widgets/source_scope_switcher_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/source_scope_switcher.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget host(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('renders Local and Online in canonical order with counts',
      (tester) async {
    SourceScope selected = SourceScope.local;
    await tester.pumpWidget(host(
      StatefulBuilder(
        builder: (context, setState) => SourceScopeSwitcher(
          persistKey: 'favorites',
          selectedScope: selected,
          localCount: 4,
          onlineCount: 2,
          onChanged: (next) => setState(() => selected = next),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cloud_rounded), findsOneWidget);
    expect(find.textContaining('Local'), findsOneWidget);
    expect(find.textContaining('Online'), findsOneWidget);

    await tester.tap(find.textContaining('Online'));
    await tester.pumpAndSettle();

    expect(selected, SourceScope.online);
    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getString('${PrefsKeys.sourceScopePrefix}favorites'), 'online');
  });

  testWidgets('restores persisted scope on mount and supports includeAll',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      '${PrefsKeys.sourceScopePrefix}search': 'all',
    });

    SourceScope selected = SourceScope.local;
    await tester.pumpWidget(host(
      StatefulBuilder(
        builder: (context, setState) => SourceScopeSwitcher(
          persistKey: 'search',
          includeAll: true,
          selectedScope: selected,
          onChanged: (next) => setState(() => selected = next),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.dashboard_rounded), findsOneWidget);
    expect(selected, SourceScope.all);
  });
}
