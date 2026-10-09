// test/core/utils/l10n_holder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/utils/l10n_holder.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _MockAppLocalizations extends Mock implements AppLocalizations {}

void main() {
  test('starts empty and holds / clears the active localization bundle', () {
    expect(L10nHolder.current, isNull,
        reason: 'fresh isolate has no active AppLocalizations');

    final l10n = _MockAppLocalizations();
    L10nHolder.current = l10n;
    expect(L10nHolder.current, same(l10n));

    final other = _MockAppLocalizations();
    L10nHolder.current = other;
    expect(L10nHolder.current, same(other));

    L10nHolder.current = null;
    expect(L10nHolder.current, isNull);
  });
}
