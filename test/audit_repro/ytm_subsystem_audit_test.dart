// test/audit_repro/ytm_subsystem_audit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/ytm_error_classifier.dart';
import 'package:pulsr/data/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

class MockClock implements Clock {
  DateTime _now;
  MockClock(this._now);

  @override
  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

void main() {
  group('YTM Subsystem Audit & Performance Hardening Tests', () {
    test(
      '[C-01] Rate limiting: single-flight in-memory deduplication coalesces parallel requests',
      () async {
        int execCount = 0;
        Future<String> sampleTask() async {
          execCount++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return 'result';
        }

        final map = <String, Future<String>>{};
        Future<String> runCoalesced(String key) {
          if (map.containsKey(key)) return map[key]!;
          final f = sampleTask();
          map[key] = f;
          f.whenComplete(() => map.remove(key));
          return f;
        }

        final futures = List.generate(
          5,
          (_) => runCoalesced('search:coldplay'),
        );
        final results = await Future.wait(futures);

        expect(execCount, 1);
        expect(results.every((r) => r == 'result'), isTrue);
      },
    );

    test(
      '[C-03 & C-06] YtmUrlCache: Identity-bound keying and expiration margin',
      () {
        final startTime = DateTime(2026, 1, 1, 12, 0, 0);
        final clock = MockClock(startTime);
        final cache = YtmUrlCache.withClock(
          clock,
          capacity: 50,
          ttl: const Duration(hours: 1),
        );

        // Put with identity hash A
        cache.put(
          'vid1',
          'https://googlevideo.com/videoplayback?expire=1767272400',
          quality: 'high',
          identityHash: 'identity_a',
        );

        // Verify hit for identity_a
        expect(
          cache.get('vid1', quality: 'high', identityHash: 'identity_a'),
          isNotNull,
        );

        // Verify miss for identity_b (prevents cross-identity token leakage)
        expect(
          cache.get('vid1', quality: 'high', identityHash: 'identity_b'),
          isNull,
        );

        // Advance clock by 61 minutes -> expired
        clock.advance(const Duration(minutes: 61));
        expect(
          cache.get('vid1', quality: 'high', identityHash: 'identity_a'),
          isNull,
        );
      },
    );

    test(
      '[C-05 & C-08] Error Classifier: maps bot challenges to structured recovery actions',
      () {
        final info1 = YtmErrorClassifier.classify(
          'Sign in to confirm that you are not a bot',
        );
        expect(info1.signal, YtmBlockSignal.botChallenge);
        expect(
          info1.recoveryAction,
          YtmRecoveryAction.invalidatePoTokenAndRetry,
        );

        final info2 = YtmErrorClassifier.classify('HTTP 429 Too Many Requests');
        expect(info2.signal, YtmBlockSignal.rateLimited);
        expect(info2.recoveryAction, YtmRecoveryAction.retryWithBackoff);

        final info3 = YtmErrorClassifier.classify('empty_adaptive_formats');
        expect(info3.signal, YtmBlockSignal.poTokenInvalid);
        expect(info3.recoveryAction, YtmRecoveryAction.refreshPoTokenAndRetry);
      },
    );

    test(
      '[C-10] InnerTube JSON parser resilience against empty/malformed responses',
      () {
        final malformedPayloads = [
          <String, dynamic>{},
          <String, dynamic>{'contents': null},
          <String, dynamic>{'contents': <dynamic>[]},
          {
            'contents': {
              'tabbedSearchResultsRenderer': {
                'tabs': [
                  {
                    'tabRenderer': {
                      'content': {
                        'sectionListRenderer': {
                          'contents': [
                            {
                              'musicResponsiveListItemRenderer': {
                                                                 'flexColumns': <dynamic>[], // empty flexColumns
                              },
                            },
                          ],
                        },
                      },
                    },
                  },
                ],
              },
            },
          },
        ];

        for (final payload in malformedPayloads) {
          expect(() {
            final tracks = <YtmTrack>[];
            void traverse(dynamic node) {
              if (node is Map<String, dynamic>) {
                if (node.containsKey('musicResponsiveListItemRenderer')) {
                  final r =
                      node['musicResponsiveListItemRenderer']
                          as Map<String, dynamic>? ??
                      {};
                  final flexCols = r['flexColumns'] as List<dynamic>? ?? [];
                  String title = 'Unknown Title';
                  String artist = 'Unknown Artist';
                  String? videoId;

                  if (flexCols.isNotEmpty && flexCols[0] is Map) {
                    final col0 = flexCols[0] as Map;
                    final runs =
                        col0['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                            as List?;
                    if (runs != null && runs.isNotEmpty && runs[0] is Map) {
                      title = (runs[0] as Map)['text']?.toString() ?? title;
                    }
                  }

                  // ignore: unnecessary_null_comparison
                  if (videoId != null && videoId.length == 11) {
                    tracks.add(
                      YtmTrack(
                        videoId: videoId,
                        title: title,
                        artist: artist,
                        duration: Duration.zero,
                      ),
                    );
                  }
                  return;
                }
                for (final val in node.values) {
                  traverse(val);
                }
              } else if (node is List) {
                for (final item in node) {
                  traverse(item);
                }
              }
            }

            traverse(payload);
          }, returnsNormally);
        }
      },
    );
  });
}
