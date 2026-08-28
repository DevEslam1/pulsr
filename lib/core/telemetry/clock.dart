import 'package:injectable/injectable.dart';

/// Abstract clock for testable time measurement.
abstract class Clock {
  DateTime now();
}

/// System clock using real wall time.
@LazySingleton(as: Clock)
class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

/// Fake clock that can be advanced manually in tests.
class FakeClock implements Clock {
  DateTime _now;
  FakeClock(DateTime initial) : _now = initial;
  FakeClock.epoch() : _now = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }

  void setTime(DateTime time) {
    _now = time;
  }
}
