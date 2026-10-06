// test/support/fake_clock.dart
/// Controllable clock for deterministic time manipulation in tests.
class FakeClock {
  DateTime _now;

  FakeClock([DateTime? initialTime])
      : _now = initialTime ?? DateTime(2026, 10, 7, 12, 0, 0);

  DateTime get now => _now;

  DateTime call() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }

  void setTime(DateTime time) {
    _now = time;
  }
}
