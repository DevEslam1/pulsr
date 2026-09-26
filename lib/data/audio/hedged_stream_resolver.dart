// F3: Hedged stream resolution (race clients, take first success).
import 'dart:async';

/// Races multiple resolution attempts and returns the first success.
/// Failures are collected; if all fail, the first error is rethrown.
class HedgedStreamResolver {
  /// Default safety ceiling for hedged races so hanging attempts cannot block forever.
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Race [attempts] with optional stagger between launches.
  /// [hedgeDelay] staggers the 2nd+ attempt so the fast path usually wins
  /// without paying double cost on every resolve.
  static Future<T> race<T>(
    List<Future<T> Function()> attempts, {
    Duration hedgeDelay = const Duration(milliseconds: 250),
    Duration? timeout,
  }) async {
    if (attempts.isEmpty) throw StateError('No attempts provided');
    final effectiveTimeout = timeout ?? defaultTimeout;
    if (attempts.length == 1) {
      return attempts.first().timeout(effectiveTimeout);
    }
    final completer = Completer<T>();
    final errors = <Object>[];
    var remaining = attempts.length;
    var settled = false;

    Future<void> run(int index) async {
      if (index > 0 && hedgeDelay > Duration.zero) {
        await Future.delayed(hedgeDelay);
        if (settled) return;
      }
      try {
        final value = await attempts[index]().timeout(effectiveTimeout);
        if (!settled) {
          settled = true;
          completer.complete(value);
        }
      } catch (e) {
        errors.add(e);
        remaining--;
        if (remaining == 0 && !settled) {
          settled = true;
          completer.completeError(errors.first);
        }
      }
    }

    for (var i = 0; i < attempts.length; i++) {
      unawaited(run(i));
    }
    return completer.future.timeout(effectiveTimeout + hedgeDelay);
  }

  /// Convenience: race the same resolver twice (e.g. two Innertube clients
  /// or primary + fallback) with dedup-friendly stagger.
  ///
  /// Only useful when [resolver] performs a genuinely independent attempt each
  /// call. A resolver that coalesces identical in-flight work — such as
  /// `YtmService.resolveStream` with its default `coalesce: true` — turns this
  /// into a race of one future against itself, which buys no tail latency.
  /// Hedged callers should call [race] with a second attempt that opts out of
  /// coalescing instead.
  static Future<T> raceDuplicate<T>(
    Future<T> Function() resolver, {
    Duration hedgeDelay = const Duration(milliseconds: 250),
    Duration? timeout,
  }) =>
      race([resolver, resolver],
          hedgeDelay: hedgeDelay, timeout: timeout);
}
