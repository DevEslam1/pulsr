import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/repositories/music_repository.dart';

void main() {
  test('forwards data from watched-result streams', () async {
    final stream = Stream<Either<AppFailure, int>>.value(const Right(5))
        .onResultError((e, st) => const Left(DatabaseFailure('failed')));
    final value = await stream.first;
    expect(value.getOrElse((_) => -1), 5);
  });

  test('emits a failure value instead of discarding the error', () async {
    final stream = Stream<Either<AppFailure, int>>.error(Exception('boom'))
        .onResultError((e, st) => const Left(DatabaseFailure('failed')));
    final value = await stream.first;
    expect(value.isLeft(), isTrue);
  });

  test('keeps forwarding data after a recoverable error', () async {
    final controller = StreamController<Either<AppFailure, int>>.broadcast();
    addTearDown(controller.close);
    final recovered = controller.stream
        .onResultError((e, st) => const Left(DatabaseFailure('failed')));
    final emitted = <Either<AppFailure, int>>[];
    final sub = recovered.listen(emitted.add);
    addTearDown(sub.cancel);

    controller.addError(Exception('transient'));
    controller.add(const Right(9));
    await Future<void>.delayed(Duration.zero);

    expect(emitted.length, 2);
    expect(emitted.first.isLeft(), isTrue);
    expect(emitted.last.getOrElse((_) => 0), 9);
  });
}
