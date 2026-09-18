import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';

void main() {
  group('SmartCriteria.copyWith', () {
    const base = SmartCriteria(
      rules: [
        SmartRule(
            field: SmartRuleField.playCount,
            operator: SmartOperator.greaterThan,
            value: '0'),
      ],
      limit: 50,
      sortBy: 'playCount',
    );

    test('leaves limit unchanged when omitted', () {
      final updated = base.copyWith(sortBy: 'title');
      expect(updated.limit, 50);
      expect(updated.sortBy, 'title');
    });

    test('sets and clears the limit explicitly', () {
      expect(base.copyWith(limit: 10).limit, 10);
      // Passing null must clear it (the old copyWith could not express this).
      expect(base.copyWith(limit: null).limit, isNull);
    });

    test('round-trips through JSON with a cleared limit', () {
      final cleared = base.copyWith(limit: null);
      final decoded = SmartCriteria.fromJsonString(cleared.toJsonString());
      expect(decoded.limit, isNull);
      expect(decoded.rules.length, 1);
    });
  });
}
