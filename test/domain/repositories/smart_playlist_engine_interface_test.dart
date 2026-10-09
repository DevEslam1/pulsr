// test/domain/repositories/smart_playlist_engine_interface_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/repositories/smart_playlist_engine_interface.dart';

class _StubEngine extends ISmartPlaylistEngine {
  @override
  Future<List<SongsTableData>> evaluateCriteria(SmartCriteria criteria) async =>
      const [];

  @override
  Stream<List<SongsTableData>> watchCriteria(SmartCriteria criteria) =>
      const Stream.empty();
  // validateRules is intentionally not overridden so the interface default runs.
}

void main() {
  test('default validateRules returns no invalid rules', () {
    final engine = _StubEngine();
    expect(engine.validateRules(const SmartCriteria()), isEmpty);
    expect(
      engine.validateRules(const SmartCriteria(rules: [
        SmartRule(
            field: SmartRuleField.playCount,
            operator: SmartOperator.equals,
            value: 'x'),
      ])),
      isEmpty,
    );
  });
}
