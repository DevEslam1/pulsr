// Privacy/flavor gating (defects 29-01/29-02): the prod manifest must strip
// INTERNET while the base manifest declares it. Fails loudly if the flavor
// property regresses and a "private" artifact ships with network capability.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prod flavor strips INTERNET (29-01)', () {
    final base = File('android/app/src/main/AndroidManifest.xml');
    final prod = File('android/app/src/prod/AndroidManifest.xml');
    expect(base.existsSync(), isTrue, reason: 'base manifest missing');
    expect(prod.existsSync(), isTrue, reason: 'prod manifest missing');
    final baseText = base.readAsStringSync();
    final prodText = prod.readAsStringSync();
    expect(baseText.contains('android.permission.INTERNET'), isTrue);
    expect(prodText.contains('tools:node="remove"'), isTrue,
        reason: 'prod manifest must remove INTERNET: $prod');
  });
}
